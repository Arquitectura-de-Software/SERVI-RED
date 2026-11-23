// Traduce los errores de PostgREST/RPC a mensajes para el operador.
// Códigos que usan las funciones de la Persona 4:
//   42501 -> sin permiso (403) | PT400 -> datos inválidos | PT404 -> no existe | PT409 -> conflicto

export interface ErrorBase {
  code?: string;
  message?: string;
  details?: string | null;
  hint?: string | null;
}

export interface ErrorPortal {
  tipo: 'permiso' | 'datos' | 'no_existe' | 'conflicto' | 'sesion' | 'red' | 'desconocido';
  mensaje: string;
  detalle?: string;
  codigo?: string;
}

export function traducirError(e: unknown): ErrorPortal {
  if (esErrorPortal(e)) {
    return e;
  }
  const err = (e ?? {}) as ErrorBase;
  const codigo = err.code;
  const msg = (err.message ?? '').trim();
  switch (codigo) {
    case '42501':
      return { tipo: 'permiso', codigo, mensaje: msg || 'No tiene permiso para esta acción.' };
    case 'PT400':
    case '22023':
    case '23514':
      return { tipo: 'datos', codigo, mensaje: msg || 'Revise los datos enviados.' };
    case 'PT404':
      return { tipo: 'no_existe', codigo, mensaje: msg || 'El elemento no existe o no está en su zona.' };
    case 'PT409':
      return { tipo: 'conflicto', codigo, mensaje: msg || 'La operación no es posible en el estado actual.', detalle: err.hint ?? undefined };
    case '23505':
      return { tipo: 'conflicto', codigo, mensaje: 'La operación ya se registró con otro identificador.' };
    case 'PGRST301':
    case 'PGRST303':
      return { tipo: 'sesion', codigo, mensaje: 'La sesión expiró. Vuelva a iniciar sesión.' };
  }
  if (e instanceof TypeError || /failed to fetch|network/i.test(msg)) {
    return { tipo: 'red', mensaje: 'No hay conexión con el servidor. Intente de nuevo.' };
  }
  return { tipo: 'desconocido', codigo, mensaje: msg || 'Ocurrió un error inesperado.' };
}

/** Devuelve los datos o lanza el error traducido (respuestas de supabase-js). */
export function exigir<T>(r: { data: T | null; error: unknown }): T {
  if (r.error) {
    throw traducirError(r.error);
  }
  return r.data as T;
}

export function esErrorPortal(e: unknown): e is ErrorPortal {
  return typeof e === 'object' && e !== null && 'tipo' in e && 'mensaje' in e;
}
