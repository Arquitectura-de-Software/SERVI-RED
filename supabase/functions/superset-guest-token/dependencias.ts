// Dependencias reales de superset-guest-token: Supabase (con la sesión del
// usuario) y la API de Superset. Toda credencial viene del entorno:
//   SUPERSET_URL, SUPERSET_USER, SUPERSET_PASSWORD, SUPERSET_DASHBOARD_ID
//   (local: supabase/functions/.env, que no se sube; ver .env.example)
//   SUPABASE_URL y SUPABASE_ANON_KEY los pone el runtime de Supabase.
import { createClient } from 'npm:@supabase/supabase-js@2';
import type { Dependencias, Identidad, PeticionGuestToken } from './handler.ts';

function requerida(nombre: string): string {
  const v = Deno.env.get(nombre);
  if (!v) throw new Error(`Falta la variable de entorno ${nombre}`);
  return v;
}

async function identidad(authorization: string): Promise<Identidad | null> {
  const sb = createClient(requerida('SUPABASE_URL'), requerida('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const jwt = authorization.replace(/^Bearer\s+/i, '');
  const { data, error } = await sb.auth.getUser(jwt);
  if (error || !data.user) return null;

  // Con la sesión del usuario: la base decide el rol y la empresa (P1).
  const [rol, empresa] = await Promise.all([sb.rpc('rol_actual'), sb.rpc('empresa_actual')]);
  if (rol.error) throw new Error(`rol_actual: ${rol.error.message}`);
  if (empresa.error) throw new Error(`empresa_actual: ${empresa.error.message}`);
  return { usuarioId: data.user.id, rol: rol.data as string | null, empresaId: empresa.data as string | null };
}

/** login -> csrf -> guest_token (API de Superset 4/5). */
async function guestToken(p: PeticionGuestToken): Promise<string> {
  const base = requerida('SUPERSET_URL').replace(/\/$/, '');
  const login = await fetch(`${base}/api/v1/security/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username: requerida('SUPERSET_USER'),
      password: requerida('SUPERSET_PASSWORD'),
      provider: 'db',
      refresh: false,
    }),
  });
  if (!login.ok) throw new Error(`login ${login.status}`);
  const { access_token } = (await login.json()) as { access_token: string };

  const csrf = await fetch(`${base}/api/v1/security/csrf_token/`, {
    headers: { Authorization: `Bearer ${access_token}` },
  });
  if (!csrf.ok) throw new Error(`csrf ${csrf.status}`);
  const { result: csrfToken } = (await csrf.json()) as { result: string };
  const cookie = (csrf.headers.get('set-cookie') ?? '').split(';')[0];

  const r = await fetch(`${base}/api/v1/security/guest_token/`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${access_token}`,
      'X-CSRFToken': csrfToken,
      ...(cookie ? { Cookie: cookie, Referer: base } : {}),
    },
    body: JSON.stringify({
      user: p.usuario,
      resources: [{ type: 'dashboard', id: p.dashboardId }],
      rls: p.rls,
    }),
  });
  if (!r.ok) throw new Error(`guest_token ${r.status}`);
  const { token } = (await r.json()) as { token: string };
  return token;
}

export function dependenciasReales(): Dependencias {
  return {
    dashboardId: Deno.env.get('SUPERSET_DASHBOARD_ID'),
    identidad,
    guestToken,
    log: (e) => console.log(JSON.stringify(e)),
  };
}
