import { Injectable } from '@angular/core';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { environment } from '../../environments/environment';

/** UUID v4 para correlation-id y client_request_id. */
export function nuevoUuid(): string {
  return crypto.randomUUID();
}

/**
 * fetch que agrega `x-correlation-id` a cada llamada. La base lo lee en
 * private.correlation_id_actual() (P1) y lo guarda en audit_log y en el outbox,
 * así una acción del portal se puede seguir de punta a punta (req. 19).
 */
export function fetchConCorrelacion(base: typeof fetch): typeof fetch {
  return (input, init) => {
    const origen = init?.headers ?? (input instanceof Request ? input.headers : undefined);
    const headers = new Headers(origen);
    if (!headers.has('x-correlation-id')) {
      headers.set('x-correlation-id', nuevoUuid());
    }
    return base(input, { ...init, headers });
  };
}

@Injectable({ providedIn: 'root' })
export class SupabaseService {
  readonly client: SupabaseClient = createClient(environment.supabaseUrl, environment.supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true },
    global: { fetch: fetchConCorrelacion((input, init) => fetch(input, init)) },
  });
}
