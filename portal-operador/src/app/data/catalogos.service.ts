import { Injectable, inject } from '@angular/core';
import { SupabaseService } from '../core/supabase.service';
import { exigir } from '../core/errores';
import { Catalogo, MunicipioCatalogo } from '../core/tipos';

/** Catálogos públicos (servicio, departamento, municipio, empresa). Se cargan una vez. */
@Injectable({ providedIn: 'root' })
export class CatalogosService {
  private readonly sb = inject(SupabaseService).client;
  private cache: Promise<{
    servicios: Catalogo[];
    departamentos: Catalogo[];
    municipios: MunicipioCatalogo[];
    empresas: Catalogo[];
  }> | null = null;

  todos() {
    this.cache ??= (async () => {
      const [s, d, m, e] = await Promise.all([
        this.sb.from('servicio').select('id, descripcion').order('id'),
        this.sb.from('departamento').select('codigo_dane, nombre').order('nombre'),
        this.sb.from('municipio').select('codigo_dane, nombre, departamento_codigo').order('nombre'),
        this.sb.from('empresa').select('id, nombre').order('nombre'),
      ]);
      return {
        servicios: (exigir(s) ?? []).map((x: { id: number; descripcion: string }) => ({ id: String(x.id), nombre: x.descripcion })),
        departamentos: (exigir(d) ?? []).map((x: { codigo_dane: string; nombre: string }) => ({ id: x.codigo_dane, nombre: x.nombre })),
        municipios: (exigir(m) ?? []).map((x: { codigo_dane: string; nombre: string; departamento_codigo: string }) => ({
          id: x.codigo_dane,
          nombre: x.nombre,
          departamento: x.departamento_codigo,
        })),
        empresas: (exigir(e) ?? []).map((x: { id: string; nombre: string }) => ({ id: x.id, nombre: x.nombre })),
      };
    })();
    this.cache.catch(() => (this.cache = null));
    return this.cache;
  }
}
