// Tipos de lo que devuelve la base (vistas y RPC de la Persona 4).

export type Rol = 'ciudadano' | 'operador' | 'regulador' | 'admin';
export type EstadoIncidente = 'recibido' | 'en_atencion' | 'restablecido' | 'cerrado';
export type Decision = 'pendiente' | 'aprobada' | 'rechazada';

export const ESTADOS: EstadoIncidente[] = ['recibido', 'en_atencion', 'restablecido', 'cerrado'];

export const ETIQUETA_ESTADO: Record<EstadoIncidente, string> = {
  recibido: 'Recibido',
  en_atencion: 'En atención',
  restablecido: 'Restablecido',
  cerrado: 'Cerrado',
};

// Transiciones de la tabla transicion_incidente (P1). Solo para pintar botones;
// la base es la que decide (y responde 409 con la lista real en el hint).
export const TRANSICIONES: Record<EstadoIncidente, EstadoIncidente[]> = {
  recibido: ['en_atencion', 'cerrado'],
  en_atencion: ['restablecido'],
  restablecido: ['cerrado', 'en_atencion'],
  cerrado: [],
};

export interface Perfil {
  id: string;
  rol: Rol;
  activo: boolean;
  empresaId: string | null;
  nombre: string | null;
}

export interface IncidenteOperacion {
  id: string;
  servicio_id: number;
  servicio_tipo: string;
  servicio: string;
  empresa_id: string | null;
  empresa: string | null;
  municipio_codigo: string;
  municipio: string | null;
  departamento_codigo: string | null;
  estado: EstadoIncidente;
  prioridad: number;
  prioridad_sugerida: number | null;
  lat: number | null;
  lng: number | null;
  operador_asignado: string | null;
  operador_asignado_nombre: string | null;
  inicio_en: string | null;
  restablecido_en: string | null;
  cerrado_en: string | null;
  creado_en: string;
  actualizado_en: string;
  total_reportes: number;
  ultimo_reporte_en: string | null;
}

export interface EventoLineaTiempo {
  ocurrido_en: string;
  orden: number;
  tipo: string;
  descripcion: string;
  actor_rol: string;
  actor_nombre: string | null;
  detalle: Record<string, unknown>;
}

export interface ElementoCola {
  tipo: 'denuncia' | 'reporte';
  id: string;
  servicio_id: number;
  servicio_tipo: string;
  municipio_codigo: string;
  municipio: string | null;
  estado: string;
  descripcion: string | null;
  url_evidencia: string | null;
  lat: number | null;
  lng: number | null;
  incidente_id: string | null;
  creado_en: string;
  ultima_decision: Decision | null;
  ultimo_comentario: string | null;
  ultima_decision_en: string | null;
}

export interface ReporteDetalle {
  id: string;
  estado: string;
  descripcion: string | null;
  url_evidencia: string | null;
  creado_en: string;
}

export interface Catalogo {
  id: string;
  nombre: string;
}

export interface MunicipioCatalogo {
  id: string;
  nombre: string;
  departamento: string;
}

export interface OperadorEmpresa {
  id: string;
  nombre_completo: string;
}
