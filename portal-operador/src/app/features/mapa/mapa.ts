import {
  Component,
  DestroyRef,
  ElementRef,
  afterNextRender,
  computed,
  effect,
  inject,
  signal,
  viewChild,
} from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import * as L from 'leaflet';
import { filter } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { traducirError } from '../../core/errores';
import { TiempoRealService } from '../../core/tiempo-real.service';
import { Catalogo, ESTADOS, ETIQUETA_ESTADO, EstadoIncidente, IncidenteOperacion, MunicipioCatalogo } from '../../core/tipos';
import { CatalogosService } from '../../data/catalogos.service';
import { FILTROS_INICIALES, FiltrosIncidentes, IncidentesService } from '../../data/incidentes.service';

export const COLOR_ESTADO: Record<EstadoIncidente, string> = {
  recibido: '#d64545',
  en_atencion: '#e08a00',
  restablecido: '#2f8f4e',
  cerrado: '#7a7a7a',
};

/** Radio del marcador: más grande cuanto más urgente (prioridad 1). */
export function radioPrioridad(p: number): number {
  return 6 + (5 - Math.min(5, Math.max(1, p))) * 2.5;
}

@Component({
  selector: 'app-mapa',
  imports: [FormsModule, RouterLink, DatePipe],
  template: `
    <section class="filtros tarjeta" aria-label="Filtros">
      <label>Servicio
        <select name="servicio" [ngModel]="filtros().servicioId" (ngModelChange)="cambiar({ servicioId: $event })">
          <option [ngValue]="null">Todos</option>
          @for (s of servicios(); track s.id) { <option [ngValue]="+s.id">{{ s.nombre }}</option> }
        </select>
      </label>
      <label>Prioridad
        <select name="prioridad" [ngModel]="filtros().prioridadMax" (ngModelChange)="cambiar({ prioridadMax: $event })">
          <option [ngValue]="null">Todas</option>
          @for (p of [1, 2, 3, 4]; track p) { <option [ngValue]="p">1 a {{ p }}</option> }
        </select>
      </label>
      <label>Departamento
        <select name="departamento" [ngModel]="filtros().departamento"
                (ngModelChange)="cambiar({ departamento: $event, municipio: null })">
          <option [ngValue]="null">Todos</option>
          @for (d of departamentos(); track d.id) { <option [ngValue]="d.id">{{ d.nombre }}</option> }
        </select>
      </label>
      <label>Municipio
        <select name="municipio" [ngModel]="filtros().municipio" (ngModelChange)="cambiar({ municipio: $event })">
          <option [ngValue]="null">Todos</option>
          @for (m of municipiosFiltrados(); track m.id) { <option [ngValue]="m.id">{{ m.nombre }}</option> }
        </select>
      </label>
      <fieldset>
        <legend>Estado</legend>
        @for (e of estados; track e) {
          <label class="check">
            <input type="checkbox" [checked]="filtros().estados.includes(e)" (change)="alternarEstado(e)" />
            <span class="punto" [style.background]="color[e]"></span>{{ etiqueta[e] }}
          </label>
        }
      </fieldset>
      <label class="check orden">
        <input type="checkbox" name="sugerida" [checked]="ordenarPorSugerida()" (change)="ordenarPorSugerida.set(!ordenarPorSugerida())" /> Ordenar por prioridad sugerida
      </label>
    </section>

    @if (error()) { <p class="error" role="alert">{{ error() }}</p> }
    @if (mosaicosFallaron()) {
      <p class="aviso" role="status">No se pudieron cargar los mosaicos del mapa. Use la lista de incidentes.</p>
    }

    <div class="vista">
      <div #mapa class="mapa tarjeta" role="region" aria-label="Mapa de incidentes"></div>

      <section class="lista tarjeta" aria-label="Lista de incidentes">
        <h2>{{ ordenados().length }} incidentes @if (cargando()) { <small>actualizando…</small> }</h2>
        <table data-testid="tabla-incidentes">
          <thead>
            <tr><th>Prior.</th><th>Sug.</th><th>Servicio</th><th>Municipio</th><th>Estado</th><th>Rep.</th><th>Actualizado</th></tr>
          </thead>
          <tbody>
            @for (i of ordenados(); track i.id) {
              <tr [attr.data-id]="i.id">
                <td><span class="prioridad p{{ i.prioridad }}">{{ i.prioridad }}</span></td>
                <td>{{ i.prioridad_sugerida ?? '–' }}</td>
                <td><a [routerLink]="['/incidentes', i.id]">{{ i.servicio }}</a></td>
                <td>{{ i.municipio }}</td>
                <td><span class="estado" [style.background]="color[i.estado]">{{ etiqueta[i.estado] }}</span></td>
                <td>{{ i.total_reportes }}</td>
                <td>{{ i.actualizado_en | date: 'dd/MM HH:mm' }}</td>
              </tr>
            } @empty {
              <tr><td colspan="7" class="vacio">No hay incidentes con estos filtros.</td></tr>
            }
          </tbody>
        </table>
      </section>
    </div>
  `,
  styles: `
    .filtros { display: flex; flex-wrap: wrap; gap: .75rem 1rem; align-items: end; margin-bottom: 1rem; }
    .filtros label { display: grid; gap: .25rem; font-size: .85rem; font-weight: 600; }
    fieldset { border: 0; padding: 0; margin: 0; display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
    legend { font-size: .85rem; font-weight: 600; float: left; margin-right: .5rem; }
    .check { display: inline-flex !important; grid-auto-flow: column; align-items: center; gap: .3rem; font-weight: 400 !important; }
    .punto { width: .7rem; height: .7rem; border-radius: 50%; display: inline-block; }
    .vista { display: grid; grid-template-columns: minmax(0, 3fr) minmax(0, 2fr); gap: 1rem; }
    @media (max-width: 960px) { .vista { grid-template-columns: 1fr; } }
    .mapa { height: 560px; padding: 0; overflow: hidden; }
    .lista { overflow: auto; max-height: 560px; }
    .lista h2 { font-size: 1rem; margin: 0 0 .5rem; }
    .estado { color: #fff; padding: .1rem .45rem; border-radius: 999px; font-size: .78rem; white-space: nowrap; }
    .vacio { text-align: center; color: var(--texto-suave); padding: 1.5rem; }
  `,
})
export class Mapa {
  private readonly incidentes = inject(IncidentesService);
  private readonly catalogos = inject(CatalogosService);
  private readonly tiempoReal = inject(TiempoRealService);
  private readonly router = inject(Router);
  protected readonly auth = inject(AuthService);

  private readonly contenedor = viewChild.required<ElementRef<HTMLDivElement>>('mapa');
  private mapa: L.Map | null = null;
  private capa = L.layerGroup();

  protected readonly estados = ESTADOS;
  protected readonly etiqueta = ETIQUETA_ESTADO;
  protected readonly color = COLOR_ESTADO;

  protected readonly filtros = signal<FiltrosIncidentes>({ ...FILTROS_INICIALES });
  protected readonly datos = signal<IncidenteOperacion[]>([]);
  protected readonly cargando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly mosaicosFallaron = signal(false);
  protected readonly ordenarPorSugerida = signal(false);
  /** Solo se reencuadra el mapa al cambiar filtros, no en cada refresco en vivo. */
  private reencuadrar = true;

  protected readonly servicios = signal<Catalogo[]>([]);
  protected readonly departamentos = signal<Catalogo[]>([]);
  private readonly municipios = signal<MunicipioCatalogo[]>([]);
  protected readonly municipiosFiltrados = computed(() => {
    const d = this.filtros().departamento;
    return d ? this.municipios().filter((m) => m.departamento === d) : this.municipios();
  });

  protected readonly ordenados = computed(() => {
    const lista = [...this.datos()];
    if (this.ordenarPorSugerida()) {
      lista.sort((a, b) => (a.prioridad_sugerida ?? 9) - (b.prioridad_sugerida ?? 9) || a.prioridad - b.prioridad);
    }
    return lista;
  });

  constructor() {
    void this.catalogos.todos().then((c) => {
      this.servicios.set(c.servicios);
      this.departamentos.set(c.departamentos);
      this.municipios.set(c.municipios);
    });

    afterNextRender(() => this.crearMapa());

    effect(() => {
      this.filtros();
      void this.cargar();
    });

    effect(() => this.pintar(this.datos()));

    // Tiempo real: cualquier cambio de un incidente refresca la lista con la RLS.
    const sub = this.tiempoReal.eventos
      .pipe(filter((e) => e.evento === 'incidente_cambiado' || e.evento === 'sondeo'))
      .subscribe(() => void this.cargar());
    inject(DestroyRef).onDestroy(() => {
      sub.unsubscribe();
      this.mapa?.remove();
    });
  }

  protected cambiar(parcial: Partial<FiltrosIncidentes>): void {
    this.reencuadrar = true;
    this.filtros.update((f) => ({ ...f, ...parcial }));
  }

  protected alternarEstado(e: EstadoIncidente): void {
    this.reencuadrar = true;
    this.filtros.update((f) => ({
      ...f,
      estados: f.estados.includes(e) ? f.estados.filter((x) => x !== e) : [...f.estados, e],
    }));
  }

  private async cargar(): Promise<void> {
    this.cargando.set(true);
    try {
      this.datos.set(await this.incidentes.listar(this.filtros()));
      this.error.set(null);
    } catch (e) {
      this.error.set(traducirError(e).mensaje);
    } finally {
      this.cargando.set(false);
    }
  }

  private crearMapa(): void {
    this.mapa = L.map(this.contenedor().nativeElement, { center: [4.65, -74.08], zoom: 11 });
    const mosaicos = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">colaboradores de OpenStreetMap</a>',
    });
    let errores = 0;
    mosaicos.on('tileerror', () => {
      if (++errores >= 4) this.mosaicosFallaron.set(true);
    });
    mosaicos.on('tileload', () => {
      errores = 0;
      this.mosaicosFallaron.set(false);
    });
    mosaicos.addTo(this.mapa);
    this.capa.addTo(this.mapa);
    this.pintar(this.datos());
  }

  private pintar(lista: IncidenteOperacion[]): void {
    if (!this.mapa) return;
    this.capa.clearLayers();
    const puntos: L.LatLngExpression[] = [];
    for (const i of lista) {
      if (i.lat === null || i.lng === null) continue;
      const m = L.circleMarker([i.lat, i.lng], {
        radius: radioPrioridad(i.prioridad),
        color: '#fff',
        weight: 1.5,
        fillColor: COLOR_ESTADO[i.estado],
        fillOpacity: 0.85,
      });
      m.bindTooltip(`${i.servicio} · ${ETIQUETA_ESTADO[i.estado]} · prioridad ${i.prioridad} · ${i.total_reportes} reporte(s)`);
      m.on('click', () => void this.router.navigate(['/incidentes', i.id]));
      m.addTo(this.capa);
      puntos.push([i.lat, i.lng]);
    }
    if (puntos.length && this.reencuadrar) {
      this.reencuadrar = false;
      this.mapa.fitBounds(L.latLngBounds(puntos), { maxZoom: 14, padding: [30, 30] });
    }
  }
}
