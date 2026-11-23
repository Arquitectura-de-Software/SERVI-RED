import { Component, DestroyRef, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { filter } from 'rxjs';
import { ErrorPortal, traducirError } from '../../core/errores';
import { TiempoRealService } from '../../core/tiempo-real.service';
import { Decision, ElementoCola } from '../../core/tipos';
import { IncidentesService } from '../../data/incidentes.service';
import { ModeracionService } from '../../data/moderacion.service';

const TEXTO_DECISION: Record<Decision, string> = {
  pendiente: 'marcada en revisión',
  aprobada: 'aprobada',
  rechazada: 'rechazada',
};

@Component({
  selector: 'app-moderacion',
  imports: [FormsModule, RouterLink, DatePipe],
  template: `
    <h1>Cola de moderación</h1>
    <p class="ayuda">Denuncias y reportes de su zona pendientes de revisión. Rechazar exige indicar el motivo.</p>

    @if (aviso(); as a) { <p class="ok" role="status" data-testid="confirmacion">{{ a }}</p> }
    @if (error(); as e) {
      <div class="error" role="alert" data-testid="error"><strong>{{ e.mensaje }}</strong>
        @if (e.detalle) { <div>{{ e.detalle }}</div> }
      </div>
    }

    <div class="cola">
      @for (item of cola(); track item.tipo + item.id) {
        <article class="tarjeta" [attr.data-id]="item.id" [attr.data-tipo]="item.tipo">
          <header>
            <span class="tipo" [class.denuncia]="item.tipo === 'denuncia'">{{ item.tipo === 'denuncia' ? 'Denuncia' : 'Reporte' }}</span>
            <strong>{{ item.servicio_tipo }}</strong> · {{ item.municipio }} · {{ item.creado_en | date: 'dd/MM HH:mm' }}
            @if (item.estado === 'en_revision') { <span class="revision">En revisión</span> }
          </header>
          <p>{{ item.descripcion ?? '(sin descripción)' }}</p>
          @if (item.ultimo_comentario) { <p class="previo">Nota previa: {{ item.ultimo_comentario }}</p> }
          <div class="pie">
            @if (item.incidente_id) { <a [routerLink]="['/incidentes', item.incidente_id]">Ver incidente</a> }
            @if (item.url_evidencia) {
              <button type="button" class="enlace" (click)="verEvidencia(item)">Ver evidencia</button>
            }
          </div>
          <label>Comentario / motivo
            <input [name]="'c-' + item.id" maxlength="2000" [(ngModel)]="comentarios[item.id]" data-testid="comentario" />
          </label>
          <div class="botones">
            <button type="button" (click)="decidir(item, 'aprobada')" [disabled]="ocupado()">Aprobar</button>
            @if (item.tipo === 'denuncia' && item.estado !== 'en_revision') {
              <button type="button" class="secundario" (click)="decidir(item, 'pendiente')" [disabled]="ocupado()">En revisión</button>
            }
            <button type="button" class="peligro" (click)="decidir(item, 'rechazada')" [disabled]="ocupado()">Rechazar</button>
          </div>
        </article>
      } @empty {
        <p class="vacio">No hay elementos pendientes.</p>
      }
    </div>
  `,
  styles: `
    h1 { font-size: 1.3rem; margin: 0; }
    .ayuda { color: var(--texto-suave); }
    .cola { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 1rem; }
    article { display: grid; gap: .5rem; align-content: start; }
    article p { margin: 0; }
    .tipo { background: #2d6cdf; color: #fff; border-radius: 4px; padding: .05rem .4rem; font-size: .75rem; margin-right: .3rem; }
    .tipo.denuncia { background: #8e44ad; }
    .revision { color: #b36b00; font-size: .8rem; margin-left: .3rem; }
    .previo { color: var(--texto-suave); font-size: .85rem; }
    label { display: grid; gap: .25rem; font-size: .85rem; font-weight: 600; }
    .botones, .pie { display: flex; gap: .5rem; flex-wrap: wrap; }
    .vacio { color: var(--texto-suave); }
  `,
})
export class Moderacion {
  private readonly svc = inject(ModeracionService);
  private readonly incidentes = inject(IncidentesService);
  private readonly tiempoReal = inject(TiempoRealService);

  protected readonly cola = signal<ElementoCola[]>([]);
  protected readonly ocupado = signal(false);
  protected readonly error = signal<ErrorPortal | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected comentarios: Record<string, string> = {};

  constructor() {
    void this.cargar();
    const sub = this.tiempoReal.eventos
      .pipe(filter((e) => e.evento === 'cola_cambiada' || e.evento === 'sondeo'))
      .subscribe(() => void this.cargar());
    inject(DestroyRef).onDestroy(() => sub.unsubscribe());
  }

  private async cargar(): Promise<void> {
    try {
      this.cola.set(await this.svc.cola());
    } catch (e) {
      this.error.set(traducirError(e));
    }
  }

  protected async decidir(item: ElementoCola, decision: Decision): Promise<void> {
    const comentario = (this.comentarios[item.id] ?? '').trim() || null;
    this.error.set(null);
    this.aviso.set(null);
    if (decision === 'rechazada' && !comentario) {
      this.error.set({ tipo: 'datos', mensaje: 'Para rechazar hay que indicar el motivo.' });
      return;
    }
    this.ocupado.set(true);
    try {
      await this.svc.moderar(item, decision, comentario);
      delete this.comentarios[item.id];
      this.aviso.set(`${item.tipo === 'denuncia' ? 'Denuncia' : 'Reporte'} ${TEXTO_DECISION[decision]}.`);
      await this.cargar();
    } catch (e) {
      this.error.set(traducirError(e));
    } finally {
      this.ocupado.set(false);
    }
  }

  protected async verEvidencia(item: ElementoCola): Promise<void> {
    if (!item.url_evidencia) return;
    try {
      const bucket = item.tipo === 'denuncia' ? 'evidencias-denuncias' : 'evidencias-reportes';
      window.open(await this.incidentes.urlEvidencia(bucket, item.url_evidencia), '_blank', 'noopener');
    } catch (e) {
      this.error.set(traducirError(e));
    }
  }
}
