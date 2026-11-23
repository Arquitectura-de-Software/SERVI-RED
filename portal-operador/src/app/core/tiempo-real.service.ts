import { Injectable, inject, signal } from '@angular/core';
import { RealtimeChannel } from '@supabase/supabase-js';
import { Subject } from 'rxjs';
import { SupabaseService } from './supabase.service';
import { Perfil } from './tipos';

export interface EventoTiempoReal {
  evento: 'incidente_cambiado' | 'cola_cambiada' | 'sondeo';
  payload: Record<string, unknown>;
}

export type EstadoCanal = 'desconectado' | 'conectando' | 'conectado' | 'respaldo';

/** Cada cuánto se refresca si el canal no está disponible (coincide con el job de agrupación). */
export const SONDEO_MS = 30_000;

/**
 * Canal privado de Broadcast (migración p4_realtime):
 *   operador -> `empresa:<empresa_id>`, admin -> `admin`.
 * Los mensajes solo traen ids; quien escucha vuelve a consultar con su RLS.
 * Si el canal falla, se cae a un sondeo cada 30 s para no dejar el mapa congelado.
 */
@Injectable({ providedIn: 'root' })
export class TiempoRealService {
  private readonly sb = inject(SupabaseService).client;
  private canal: RealtimeChannel | null = null;
  private sondeo: ReturnType<typeof setInterval> | null = null;

  readonly estado = signal<EstadoCanal>('desconectado');
  readonly eventos = new Subject<EventoTiempoReal>();

  static topicPara(perfil: Perfil): string | null {
    if (perfil.rol === 'operador' && perfil.empresaId) {
      return `empresa:${perfil.empresaId}`;
    }
    if (perfil.rol === 'admin') {
      return 'admin';
    }
    return null;
  }

  async conectar(perfil: Perfil): Promise<void> {
    await this.desconectar();
    const topic = TiempoRealService.topicPara(perfil);
    if (!topic) {
      return;
    }
    this.estado.set('conectando');
    const { data } = await this.sb.auth.getSession();
    await this.sb.realtime.setAuth(data.session?.access_token ?? null);

    this.canal = this.sb
      .channel(topic, { config: { private: true } })
      .on('broadcast', { event: 'incidente_cambiado' }, (m) =>
        this.eventos.next({ evento: 'incidente_cambiado', payload: (m['payload'] ?? {}) as Record<string, unknown> }),
      )
      .on('broadcast', { event: 'cola_cambiada' }, (m) =>
        this.eventos.next({ evento: 'cola_cambiada', payload: (m['payload'] ?? {}) as Record<string, unknown> }),
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          this.estado.set('conectado');
          this.detenerSondeo();
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          this.iniciarSondeo();
        }
      });
  }

  async desconectar(): Promise<void> {
    this.detenerSondeo();
    if (this.canal) {
      await this.sb.removeChannel(this.canal);
      this.canal = null;
    }
    this.estado.set('desconectado');
  }

  private iniciarSondeo(): void {
    this.estado.set('respaldo');
    if (!this.sondeo) {
      this.sondeo = setInterval(() => this.eventos.next({ evento: 'sondeo', payload: {} }), SONDEO_MS);
    }
  }

  private detenerSondeo(): void {
    if (this.sondeo) {
      clearInterval(this.sondeo);
      this.sondeo = null;
    }
  }
}
