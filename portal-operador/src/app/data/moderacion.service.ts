import { Injectable, inject } from '@angular/core';
import { SupabaseService } from '../core/supabase.service';
import { exigir } from '../core/errores';
import { Decision, ElementoCola } from '../core/tipos';
import { conReintento } from './acciones';

@Injectable({ providedIn: 'root' })
export class ModeracionService {
  private readonly sb = inject(SupabaseService).client;

  async cola(): Promise<ElementoCola[]> {
    return exigir(await this.sb.from('cola_moderacion').select('*').order('creado_en').limit(300)) ?? [];
  }

  /** Rechazar exige motivo (la base responde 400 si falta). */
  moderar(item: Pick<ElementoCola, 'tipo' | 'id'>, decision: Decision, comentario: string | null) {
    const fn = item.tipo === 'denuncia' ? 'moderar_denuncia' : 'moderar_reporte';
    const param = item.tipo === 'denuncia' ? 'p_denuncia_id' : 'p_reporte_id';
    return conReintento(async (crid) =>
      exigir(
        await this.sb.rpc(fn, {
          [param]: item.id,
          p_decision: decision,
          p_comentario: comentario,
          p_client_request_id: crid,
        }),
      ),
    );
  }
}
