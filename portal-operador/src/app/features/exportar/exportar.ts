import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { traducirError } from '../../core/errores';
import { Catalogo } from '../../core/tipos';
import { CatalogosService } from '../../data/catalogos.service';
import { ExportarService } from '../../data/exportar.service';

/** Fecha de hoy en Colombia (yyyy-mm-dd), que es como filtra la base. */
export function hoyBogota(d = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Bogota' }).format(d);
}

export function restarDias(fecha: string, dias: number): string {
  const d = new Date(`${fecha}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - dias);
  return d.toISOString().slice(0, 10);
}

@Component({
  selector: 'app-exportar',
  imports: [FormsModule],
  template: `
    <h1>Exportación regulatoria (CSV)</h1>
    <p class="ayuda">
      Una fila por incidente creado en el rango (hora de Colombia). Formato provisional, documentado para SSPD/CRA.
      @if (auth.esOperador()) { Solo incluye los incidentes de su empresa. }
      Cada exportación queda registrada en la auditoría.
    </p>
    <form class="tarjeta formulario" (ngSubmit)="exportar()">
      <label>Desde <input type="date" name="desde" required [(ngModel)]="desde" data-testid="desde" /></label>
      <label>Hasta <input type="date" name="hasta" required [(ngModel)]="hasta" data-testid="hasta" /></label>
      <label>Servicio
        <select name="servicio" [(ngModel)]="servicioId">
          <option [ngValue]="null">Todos</option>
          @for (s of servicios(); track s.id) { <option [ngValue]="+s.id">{{ s.nombre }}</option> }
        </select>
      </label>
      @if (!auth.esOperador()) {
        <label>Empresa
          <select name="empresa" [(ngModel)]="empresaId">
            <option [ngValue]="null">Todas</option>
            @for (e of empresas(); track e.id) { <option [ngValue]="e.id">{{ e.nombre }}</option> }
          </select>
        </label>
      }
      <button type="submit" [disabled]="ocupado() || !desde || !hasta">{{ ocupado() ? 'Generando…' : 'Descargar CSV' }}</button>
    </form>
    @if (error()) { <p class="error" role="alert" data-testid="error">{{ error() }}</p> }
    @if (resultado()) { <p class="ok" role="status" data-testid="confirmacion">{{ resultado() }}</p> }
  `,
  styles: `
    h1 { font-size: 1.3rem; margin: 0; }
    .ayuda { color: var(--texto-suave); max-width: 70ch; }
    .formulario { display: flex; flex-wrap: wrap; gap: 1rem; align-items: end; max-width: 900px; }
    label { display: grid; gap: .25rem; font-size: .85rem; font-weight: 600; }
  `,
})
export class Exportar {
  protected readonly auth = inject(AuthService);
  private readonly svc = inject(ExportarService);

  protected hasta = hoyBogota();
  protected desde = restarDias(this.hasta, 30);
  protected servicioId: number | null = null;
  protected empresaId: string | null = null;
  protected readonly servicios = signal<Catalogo[]>([]);
  protected readonly empresas = signal<Catalogo[]>([]);
  protected readonly ocupado = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly resultado = signal<string | null>(null);

  constructor() {
    void inject(CatalogosService)
      .todos()
      .then((c) => {
        this.servicios.set(c.servicios);
        this.empresas.set(c.empresas);
      });
  }

  async exportar(): Promise<void> {
    this.error.set(null);
    this.resultado.set(null);
    this.ocupado.set(true);
    try {
      const csv = await this.svc.csv({
        desde: this.desde,
        hasta: this.hasta,
        servicioId: this.servicioId,
        empresaId: this.empresaId,
      });
      const filas = Math.max(0, csv.trim().split('\n').length - 1);
      // BOM para que Excel abra bien las tildes.
      const blob = new Blob(['﻿', csv], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `incidentes_${this.desde}_${this.hasta}.csv`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      this.resultado.set(`Se exportaron ${filas} incidente(s).`);
    } catch (e) {
      this.error.set(traducirError(e).mensaje);
    } finally {
      this.ocupado.set(false);
    }
  }
}
