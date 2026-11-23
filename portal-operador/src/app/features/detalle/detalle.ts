import { Component, DestroyRef, computed, inject, input, signal, effect } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { filter } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ErrorPortal, traducirError } from '../../core/errores';
import { TiempoRealService } from '../../core/tiempo-real.service';
import {
  Catalogo,
  ETIQUETA_ESTADO,
  EstadoIncidente,
  EventoLineaTiempo,
  IncidenteOperacion,
  OperadorEmpresa,
  ReporteDetalle,
  TRANSICIONES,
} from '../../core/tipos';
import { CatalogosService } from '../../data/catalogos.service';
import { IncidentesService } from '../../data/incidentes.service';
import { COLOR_ESTADO } from '../mapa/mapa';

@Component({
  selector: 'app-detalle',
  imports: [FormsModule, RouterLink, DatePipe],
  template: `
    <p><a routerLink="/mapa">← Volver a incidentes</a></p>

    @if (aviso(); as a) {
      <p class="ok" role="status" data-testid="confirmacion">{{ a }}</p>
    }
    @if (error(); as e) {
      <div class="error" role="alert" data-testid="error">
        <strong>{{ e.mensaje }}</strong>
        @if (e.detalle) { <div>{{ e.detalle }}</div> }
      </div>
    }

    @if (inc(); as i) {
      <section class="cabecera tarjeta">
        <div>
          <h1>{{ i.servicio }} · {{ i.municipio }}</h1>
          <p class="meta">
            <span class="estado" [style.background]="color[i.estado]" data-testid="estado">{{ etiqueta[i.estado] }}</span>
            Prioridad <strong data-testid="prioridad">{{ i.prioridad }}</strong>
            @if (i.prioridad_sugerida) { (sugerida {{ i.prioridad_sugerida }}) }
            · {{ i.total_reportes }} reporte(s)
            · {{ i.empresa ?? 'Sin empresa asignada' }}
            · Asignado a: <span data-testid="asignado">{{ i.operador_asignado_nombre ?? 'nadie' }}</span>
          </p>
          <p class="meta">Creado {{ i.creado_en | date: 'dd/MM/yyyy HH:mm' }}
            @if (i.restablecido_en) { · Restablecido {{ i.restablecido_en | date: 'dd/MM HH:mm' }} }
            @if (i.cerrado_en) { · Cerrado {{ i.cerrado_en | date: 'dd/MM HH:mm' }} }
          </p>
        </div>
      </section>

      @if (auth.puedeGestionar() && i.estado !== 'cerrado') {
        <section class="acciones">
          <form class="tarjeta" (ngSubmit)="cambiarEstado()" aria-label="Cambiar estado">
            <h2>Estado</h2>
            <label>Nuevo estado
              <select name="estado" [(ngModel)]="nuevoEstado" data-testid="nuevo-estado">
                @for (e of opcionesEstado(); track e) { <option [ngValue]="e">{{ etiqueta[e] }}</option> }
              </select>
            </label>
            <label>Mensaje (opcional)
              <input name="mensaje" [(ngModel)]="mensajeEstado" maxlength="2000" />
            </label>
            <button type="submit" [disabled]="ocupado() || !nuevoEstado">Cambiar estado</button>
          </form>

          <form class="tarjeta" (ngSubmit)="priorizar()" aria-label="Priorizar">
            <h2>Prioridad</h2>
            <label>1 = más urgente
              <select name="prioridad" [(ngModel)]="nuevaPrioridad" data-testid="nueva-prioridad">
                @for (p of [1, 2, 3, 4, 5]; track p) { <option [ngValue]="p">{{ p }}</option> }
              </select>
            </label>
            @if (i.prioridad_sugerida && i.prioridad_sugerida !== i.prioridad) {
              <button type="button" class="secundario" (click)="nuevaPrioridad = i.prioridad_sugerida!">
                Usar la sugerida ({{ i.prioridad_sugerida }})
              </button>
            }
            <button type="submit" [disabled]="ocupado()">Guardar prioridad</button>
          </form>

          @if (i.empresa_id) {
            <form class="tarjeta" (ngSubmit)="asignar()" aria-label="Asignar">
              <h2>Asignación</h2>
              <label>Operador
                <select name="operador" [(ngModel)]="operadorElegido" data-testid="operador">
                  <option [ngValue]="null">Sin asignar</option>
                  @for (o of operadores(); track o.id) { <option [ngValue]="o.id">{{ o.nombre_completo }}</option> }
                </select>
              </label>
              <button type="submit" [disabled]="ocupado()">Asignar</button>
            </form>
          } @else if (auth.rol() === 'admin') {
            <form class="tarjeta" (ngSubmit)="asignarEmpresa()" aria-label="Asignar empresa">
              <h2>Empresa responsable</h2>
              <label>Empresa
                <select name="empresa" [(ngModel)]="empresaElegida">
                  @for (e of empresas(); track e.id) { <option [ngValue]="e.id">{{ e.nombre }}</option> }
                </select>
              </label>
              <button type="submit" [disabled]="ocupado() || !empresaElegida">Asignar empresa</button>
            </form>
          }

          @if (auth.esOperador()) {
            <form class="tarjeta" (ngSubmit)="responder()" aria-label="Responder">
              <h2>Responder</h2>
              <label>Mensaje
                <textarea name="respuesta" rows="3" maxlength="2000" required [(ngModel)]="mensaje" data-testid="mensaje"></textarea>
              </label>
              <label class="check">
                <input type="checkbox" name="visible" [(ngModel)]="visibleCiudadanos" /> Visible para los ciudadanos que reportaron
              </label>
              <button type="submit" [disabled]="ocupado() || !mensaje.trim()">Enviar respuesta</button>
            </form>
          }
        </section>
      }

      <div class="dos">
        <section class="tarjeta" aria-label="Línea de tiempo">
          <h2>Línea de tiempo</h2>
          <ol class="tiempo" data-testid="linea-tiempo">
            @for (ev of linea(); track ev.orden + ev.tipo + ev.ocurrido_en) {
              <li [attr.data-tipo]="ev.tipo">
                <time>{{ ev.ocurrido_en | date: 'dd/MM HH:mm:ss' }}</time>
                <span class="desc">{{ ev.descripcion }}</span>
                <span class="actor">{{ ev.actor_nombre ?? ev.actor_rol }}</span>
              </li>
            } @empty {
              <li>Sin eventos.</li>
            }
          </ol>
        </section>

        <section class="tarjeta" aria-label="Reportes">
          <h2>Reportes ciudadanos</h2>
          <ul class="reportes">
            @for (r of reportes(); track r.id) {
              <li>
                <time>{{ r.creado_en | date: 'dd/MM HH:mm' }}</time> · {{ r.estado }}
                @if (r.descripcion) { <p>{{ r.descripcion }}</p> }
                @if (r.url_evidencia) {
                  <button type="button" class="enlace" (click)="verEvidencia(r.url_evidencia)">Ver evidencia</button>
                }
              </li>
            } @empty {
              <li>No hay reportes vinculados.</li>
            }
          </ul>
        </section>
      </div>
    } @else if (!cargando()) {
      <p>No se encontró el incidente o no tiene acceso a él.</p>
    }
  `,
  styles: `
    h1 { font-size: 1.3rem; margin: 0 0 .4rem; }
    h2 { font-size: 1rem; margin: 0 0 .6rem; }
    .meta { margin: .25rem 0; color: var(--texto-suave); }
    .estado { color: #fff; padding: .15rem .55rem; border-radius: 999px; font-size: .8rem; margin-right: .5rem; }
    .acciones { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 1rem; margin: 1rem 0; }
    .acciones form { display: grid; gap: .6rem; align-content: start; }
    .acciones label { display: grid; gap: .25rem; font-size: .85rem; font-weight: 600; }
    .check { display: flex !important; align-items: center; gap: .4rem; font-weight: 400 !important; }
    .dos { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 1rem; }
    .tiempo { list-style: none; padding: 0; margin: 0; display: grid; gap: .5rem; }
    .tiempo li { display: grid; grid-template-columns: 7.5rem 1fr auto; gap: .5rem; border-left: 3px solid var(--primario); padding-left: .6rem; font-size: .9rem; }
    .tiempo time, .reportes time { color: var(--texto-suave); font-variant-numeric: tabular-nums; }
    .actor { color: var(--texto-suave); font-size: .8rem; }
    .reportes { list-style: none; padding: 0; margin: 0; display: grid; gap: .6rem; }
    .reportes p { margin: .2rem 0; }
    .cabecera { margin-top: .5rem; }
  `,
})
export class Detalle {
  readonly id = input.required<string>();

  protected readonly auth = inject(AuthService);
  private readonly svc = inject(IncidentesService);
  private readonly catalogos = inject(CatalogosService);
  private readonly tiempoReal = inject(TiempoRealService);

  protected readonly etiqueta = ETIQUETA_ESTADO;
  protected readonly color = COLOR_ESTADO;

  protected readonly inc = signal<IncidenteOperacion | null>(null);
  protected readonly linea = signal<EventoLineaTiempo[]>([]);
  protected readonly reportes = signal<ReporteDetalle[]>([]);
  protected readonly operadores = signal<OperadorEmpresa[]>([]);
  protected readonly empresas = signal<Catalogo[]>([]);
  protected readonly cargando = signal(true);
  protected readonly ocupado = signal(false);
  protected readonly error = signal<ErrorPortal | null>(null);
  protected readonly aviso = signal<string | null>(null);

  protected readonly opcionesEstado = computed(() => {
    const i = this.inc();
    return i ? TRANSICIONES[i.estado] : [];
  });

  protected nuevoEstado: EstadoIncidente | null = null;
  protected mensajeEstado = '';
  protected nuevaPrioridad = 3;
  protected operadorElegido: string | null = null;
  protected empresaElegida: string | null = null;
  protected mensaje = '';
  protected visibleCiudadanos = true;

  constructor() {
    effect(() => {
      this.id();
      void this.cargar(true);
    });
    const sub = this.tiempoReal.eventos
      .pipe(filter((e) => e.evento === 'sondeo' || (e.evento === 'incidente_cambiado' && e.payload['id'] === this.id())))
      .subscribe(() => void this.cargar(false));
    inject(DestroyRef).onDestroy(() => sub.unsubscribe());
  }

  private async cargar(inicial: boolean): Promise<void> {
    if (inicial) this.cargando.set(true);
    try {
      const i = await this.svc.obtener(this.id());
      this.inc.set(i);
      if (!i) return;
      const [linea, reportes] = await Promise.all([this.svc.lineaTiempo(i.id), this.svc.reportes(i.id)]);
      this.linea.set(linea);
      this.reportes.set(reportes);
      if (inicial) {
        this.nuevoEstado = TRANSICIONES[i.estado][0] ?? null;
        this.nuevaPrioridad = i.prioridad;
        this.operadorElegido = i.operador_asignado;
        if (i.empresa_id) {
          this.operadores.set(await this.svc.operadoresDeEmpresa(i.empresa_id));
        } else if (this.auth.rol() === 'admin') {
          this.empresas.set((await this.catalogos.todos()).empresas);
        }
      } else if (!TRANSICIONES[i.estado].includes(this.nuevoEstado as EstadoIncidente)) {
        this.nuevoEstado = TRANSICIONES[i.estado][0] ?? null;
      }
    } catch (e) {
      this.error.set(traducirError(e));
    } finally {
      this.cargando.set(false);
    }
  }

  /** Ejecuta una acción, muestra su confirmación o el error de la base, y recarga. */
  private async ejecutar(accion: () => Promise<string>): Promise<void> {
    this.ocupado.set(true);
    this.error.set(null);
    this.aviso.set(null);
    try {
      this.aviso.set(await accion());
      await this.cargar(false);
    } catch (e) {
      this.error.set(traducirError(e));
    } finally {
      this.ocupado.set(false);
    }
  }

  protected cambiarEstado(): Promise<void> {
    const estado = this.nuevoEstado;
    if (!estado) return Promise.resolve();
    const mensaje = this.mensajeEstado.trim() || null;
    return this.ejecutar(async () => {
      await this.svc.cambiarEstado(this.id(), estado, mensaje);
      this.mensajeEstado = '';
      return `Estado cambiado a «${ETIQUETA_ESTADO[estado]}».`;
    });
  }

  protected priorizar(): Promise<void> {
    const p = this.nuevaPrioridad;
    return this.ejecutar(async () => {
      await this.svc.priorizar(this.id(), p);
      return `Prioridad guardada: ${p}.`;
    });
  }

  protected asignar(): Promise<void> {
    const op = this.operadorElegido;
    const nombre = this.operadores().find((o) => o.id === op)?.nombre_completo;
    return this.ejecutar(async () => {
      await this.svc.asignar(this.id(), op);
      return op ? `Asignado a ${nombre}.` : 'Se quitó la asignación.';
    });
  }

  protected asignarEmpresa(): Promise<void> {
    const emp = this.empresaElegida;
    if (!emp) return Promise.resolve();
    return this.ejecutar(async () => {
      await this.svc.asignarEmpresa(this.id(), emp);
      await this.cargar(true);
      return 'Empresa asignada.';
    });
  }

  protected responder(): Promise<void> {
    const texto = this.mensaje.trim();
    const visible = this.visibleCiudadanos;
    return this.ejecutar(async () => {
      const r = await this.svc.responder(this.id(), texto, visible);
      this.mensaje = '';
      return visible
        ? `Respuesta enviada a ${r?.reportes_notificados ?? 0} ciudadano(s).`
        : 'Respuesta interna registrada.';
    });
  }

  protected async verEvidencia(ruta: string): Promise<void> {
    try {
      window.open(await this.svc.urlEvidencia('evidencias-reportes', ruta), '_blank', 'noopener');
    } catch (e) {
      this.error.set(traducirError(e));
    }
  }
}
