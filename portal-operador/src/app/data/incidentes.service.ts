import { Injectable, inject } from '@angular/core';
import { SupabaseService } from '../core/supabase.service';
import { exigir } from '../core/errores';
import {
  EstadoIncidente,
  EventoLineaTiempo,
  IncidenteOperacion,
  OperadorEmpresa,
  ReporteDetalle,
} from '../core/tipos';
import { conReintento } from './acciones';

export interface FiltrosIncidentes {
  servicioId: number | null;
  estados: EstadoIncidente[];
  prioridadMax: number | null;
  departamento: string | null;
  municipio: string | null;
}

export const FILTROS_INICIALES: FiltrosIncidentes = {
  servicioId: null,
  estados: ['recibido', 'en_atencion', 'restablecido'],
  prioridadMax: null,
  departamento: null,
  municipio: null,
};

@Injectable({ providedIn: 'root' })
export class IncidentesService {
  private readonly sb = inject(SupabaseService).client;

  /** Incidentes visibles (la vista incidente_operacion aplica la RLS de quien consulta). */
  async listar(f: FiltrosIncidentes): Promise<IncidenteOperacion[]> {
    let q = this.sb.from('incidente_operacion').select('*');
    if (f.servicioId !== null) q = q.eq('servicio_id', f.servicioId);
    if (f.estados.length) q = q.in('estado', f.estados);
    if (f.prioridadMax !== null) q = q.lte('prioridad', f.prioridadMax);
    if (f.departamento) q = q.eq('departamento_codigo', f.departamento);
    if (f.municipio) q = q.eq('municipio_codigo', f.municipio);
    return exigir(await q.order('prioridad').order('actualizado_en', { ascending: false }).limit(500)) ?? [];
  }

  async obtener(id: string): Promise<IncidenteOperacion | null> {
    return exigir(await this.sb.from('incidente_operacion').select('*').eq('id', id).maybeSingle<IncidenteOperacion>());
  }

  async lineaTiempo(id: string): Promise<EventoLineaTiempo[]> {
    return exigir(await this.sb.rpc('linea_tiempo_incidente', { p_incidente_id: id })) ?? [];
  }

  /** Reportes del incidente: el operador que lo cubre sí ve descripción y evidencia (RLS reporte_select). */
  async reportes(id: string): Promise<ReporteDetalle[]> {
    return (
      exigir(
        await this.sb
          .from('reporte')
          .select('id, estado, descripcion, url_evidencia, creado_en')
          .eq('incidente_id', id)
          .order('creado_en'),
      ) ?? []
    );
  }

  async operadoresDeEmpresa(empresaId: string): Promise<OperadorEmpresa[]> {
    return (
      exigir(
        await this.sb.from('operador').select('id, nombre_completo').eq('empresa_id', empresaId).order('nombre_completo'),
      ) ?? []
    );
  }

  cambiarEstado(id: string, estado: EstadoIncidente, mensaje: string | null) {
    return conReintento(async (crid) =>
      exigir(
        await this.sb.rpc('cambiar_estado_incidente', {
          p_incidente_id: id,
          p_estado: estado,
          p_mensaje: mensaje,
          p_client_request_id: mensaje ? crid : null,
        }),
      ),
    );
  }

  asignar(id: string, operadorId: string | null) {
    return conReintento(async () =>
      exigir(await this.sb.rpc('asignar_incidente', { p_incidente_id: id, p_operador_id: operadorId })),
    );
  }

  priorizar(id: string, prioridad: number) {
    return conReintento(async () =>
      exigir(await this.sb.rpc('priorizar_incidente', { p_incidente_id: id, p_prioridad: prioridad })),
    );
  }

  asignarEmpresa(id: string, empresaId: string) {
    return conReintento(async () =>
      exigir(await this.sb.rpc('asignar_empresa_incidente', { p_incidente_id: id, p_empresa_id: empresaId })),
    );
  }

  /** aReportes = true: el mensaje llega a cada ciudadano con reporte vinculado. */
  responder(id: string, mensaje: string, aReportes: boolean) {
    return conReintento(async (crid) => {
      const filas = exigir(
        await this.sb.rpc('responder', {
          p_mensaje: mensaje,
          p_incidente_id: id,
          p_reporte_id: null,
          p_client_request_id: crid,
          p_a_reportes: aReportes,
        }),
      ) as { respuesta_id: string; reportes_notificados: number }[];
      return filas[0];
    });
  }

  /** URL firmada (5 min) de una evidencia; la política de Storage de P1 lo permite al operador que cubre. */
  async urlEvidencia(bucket: 'evidencias-reportes' | 'evidencias-denuncias', ruta: string): Promise<string> {
    const r = await this.sb.storage.from(bucket).createSignedUrl(ruta, 300);
    return exigir(r).signedUrl;
  }
}
