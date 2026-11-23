import { traducirError } from '../core/errores';
import { nuevoUuid } from '../core/supabase.service';

/**
 * Ejecuta una acción con un client_request_id fijo y la reintenta una vez si
 * falla la red. Como la base es idempotente por ese id, el reintento no duplica
 * la respuesta ni la validación.
 */
export async function conReintento<T>(accion: (clientRequestId: string) => Promise<T>): Promise<T> {
  const id = nuevoUuid();
  try {
    return await accion(id);
  } catch (e) {
    if (traducirError(e).tipo === 'red') {
      return await accion(id);
    }
    throw e;
  }
}
