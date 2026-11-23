import { Component, DestroyRef, ElementRef, afterNextRender, inject, signal, viewChild } from '@angular/core';
import { embedDashboard } from '@superset-ui/embedded-sdk';
import { environment } from '../../../environments/environment';
import { SupabaseService } from '../../core/supabase.service';

/**
 * Tablero de Superset (lo construye la Persona 5) embebido y filtrado por la
 * empresa del operador. El guest token lo emite la Edge Function
 * superset-guest-token, que aplica la RLS por empresa; el portal nunca ve
 * credenciales de Superset. Si el embebido no está habilitado (EMBEDDED_SUPERSET
 * en superset_config.py, P1) o falla, se muestra el enlace directo.
 */
@Component({
  selector: 'app-indicadores',
  template: `
    <h1>Indicadores</h1>
    @if (problema()) {
      <p class="aviso" role="status" data-testid="respaldo">
        {{ problema() }}
        <a [href]="supersetUrl" target="_blank" rel="noopener">Abrir Superset en otra pestaña</a>.
      </p>
    }
    <div #tablero class="tablero" [hidden]="!!problema()"></div>
  `,
  styles: `
    h1 { font-size: 1.3rem; margin: 0 0 .75rem; }
    .tablero { height: calc(100vh - 160px); min-height: 480px; }
    .tablero ::ng-deep iframe { width: 100%; height: 100%; border: 0; border-radius: 10px; background: #fff; }
  `,
})
export class Indicadores {
  private readonly sb = inject(SupabaseService).client;
  private readonly contenedor = viewChild.required<ElementRef<HTMLDivElement>>('tablero');
  protected readonly supersetUrl = environment.supersetUrl;
  protected readonly problema = signal<string | null>(null);

  constructor() {
    let desmontar: (() => void) | null = null;
    inject(DestroyRef).onDestroy(() => desmontar?.());

    afterNextRender(async () => {
      if (!environment.supersetDashboardId) {
        this.problema.set('El tablero embebido aún no está configurado.');
        return;
      }
      try {
        // Se pide un token antes de montar para detectar a tiempo 401/403/503.
        await this.pedirToken();
        const d = await embedDashboard({
          id: environment.supersetDashboardId,
          supersetDomain: environment.supersetUrl,
          mountPoint: this.contenedor().nativeElement,
          fetchGuestToken: () => this.pedirToken(),
          dashboardUiConfig: { hideTitle: false, filters: { expanded: false } },
        });
        desmontar = () => d.unmount();
      } catch {
        this.problema.set('No se pudo cargar el tablero embebido.');
      }
    });
  }

  private async pedirToken(): Promise<string> {
    const { data, error } = await this.sb.functions.invoke<{ token: string }>('superset-guest-token', { method: 'POST' });
    if (error || !data?.token) {
      throw error ?? new Error('sin token');
    }
    return data.token;
  }
}
