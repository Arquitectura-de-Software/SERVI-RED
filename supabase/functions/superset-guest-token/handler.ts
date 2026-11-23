// SERVI-RED | Persona 4 | Lógica de la Edge Function superset-guest-token.
// Separada de index.ts para poder probarla con dependencias falsas (Deno test).
//
// Flujo: JWT del usuario -> rol y empresa (con SU sesión, la base decide) ->
// guest token de Superset para UN dashboard, con RLS por empresa.
//   sin JWT o JWT inválido      -> 401
//   rol distinto de operador/admin -> 403
//   operador                   -> rls: empresa_id = '<su empresa>'
//   admin                      -> sin filtro (ve todas las empresas)
// Nunca se registran tokens ni contraseñas en los logs.

export interface Identidad {
  usuarioId: string;
  rol: string | null;
  empresaId: string | null;
}

export interface PeticionGuestToken {
  dashboardId: string;
  usuario: { username: string; first_name: string; last_name: string };
  rls: { clause: string }[];
}

export interface Dependencias {
  dashboardId: string | undefined;
  /** Valida el JWT y lee rol/empresa con la sesión del usuario. null = JWT inválido. */
  identidad(authorization: string): Promise<Identidad | null>;
  /** Pide el guest token a Superset con la cuenta de servicio (credenciales por entorno). */
  guestToken(p: PeticionGuestToken): Promise<string>;
  log(entrada: Record<string, unknown>): void;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-correlation-id',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(status: number, cuerpo: unknown, correlationId: string): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json', 'x-correlation-id': correlationId },
  });
}

/** Cláusula RLS de Superset para la empresa. Solo acepta UUID (evita inyección en el SQL de Superset). */
export function clausulaEmpresa(empresaId: string): string {
  if (!UUID.test(empresaId)) {
    throw new Error('empresa_id inválido');
  }
  return `empresa_id = '${empresaId.toLowerCase()}'`;
}

export function crearHandler(deps: Dependencias): (req: Request) => Promise<Response> {
  return async (req) => {
    const recibido = req.headers.get('x-correlation-id') ?? '';
    const correlationId = UUID.test(recibido) ? recibido : crypto.randomUUID();
    const inicio = Date.now();
    const log = (nivel: string, evento: string, extra: Record<string, unknown> = {}) =>
      deps.log({ nivel, evento, funcion: 'superset-guest-token', correlation_id: correlationId, ms: Date.now() - inicio, ...extra });

    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: CORS });
    }
    if (req.method !== 'POST') {
      return json(405, { error: 'Método no permitido' }, correlationId);
    }

    const authorization = req.headers.get('Authorization') ?? '';
    if (!/^Bearer\s+\S+$/i.test(authorization)) {
      log('warn', 'sin_jwt');
      return json(401, { error: 'Falta la sesión' }, correlationId);
    }

    let identidad: Identidad | null;
    try {
      identidad = await deps.identidad(authorization);
    } catch (e) {
      log('error', 'identidad_fallo', { detalle: String((e as Error)?.message ?? e) });
      return json(502, { error: 'No se pudo validar la sesión' }, correlationId);
    }
    if (!identidad) {
      log('warn', 'jwt_invalido');
      return json(401, { error: 'Sesión inválida o vencida' }, correlationId);
    }
    if (identidad.rol !== 'operador' && identidad.rol !== 'admin') {
      log('warn', 'rol_no_permitido', { usuario_id: identidad.usuarioId, rol: identidad.rol });
      return json(403, { error: 'Solo operadores y administradores ven los indicadores' }, correlationId);
    }
    if (identidad.rol === 'operador' && !identidad.empresaId) {
      log('warn', 'operador_sin_empresa', { usuario_id: identidad.usuarioId });
      return json(403, { error: 'El operador no tiene empresa asociada' }, correlationId);
    }
    if (!deps.dashboardId) {
      log('error', 'sin_configuracion');
      return json(503, { error: 'El tablero de indicadores no está configurado' }, correlationId);
    }

    const rls = identidad.rol === 'operador' ? [{ clause: clausulaEmpresa(identidad.empresaId!) }] : [];
    try {
      const token = await deps.guestToken({
        dashboardId: deps.dashboardId,
        usuario: { username: `portal-${identidad.usuarioId}`, first_name: 'Portal', last_name: identidad.rol },
        rls,
      });
      log('info', 'guest_token_emitido', {
        usuario_id: identidad.usuarioId,
        rol: identidad.rol,
        empresa_id: identidad.empresaId,
        filtrado: rls.length > 0,
      });
      return json(200, { token, dashboard_id: deps.dashboardId }, correlationId);
    } catch (e) {
      log('error', 'superset_fallo', { detalle: String((e as Error)?.message ?? e) });
      return json(502, { error: 'Superset no respondió' }, correlationId);
    }
  };
}
