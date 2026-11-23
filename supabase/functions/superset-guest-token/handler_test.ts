// Pruebas de superset-guest-token con dependencias falsas (sin Supabase ni Superset).
// Ejecutar: deno test supabase/functions/superset-guest-token/
import { assertEquals, assertMatch, assertThrows } from 'jsr:@std/assert@1';
import { clausulaEmpresa, crearHandler, type Dependencias, type Identidad, type PeticionGuestToken } from './handler.ts';

const EMPRESA = '7b1f0c2e-1111-4a2b-8c3d-000000000001';

function deps(identidad: Identidad | null, opciones: Partial<Dependencias> = {}) {
  const pedidas: PeticionGuestToken[] = [];
  const logs: Record<string, unknown>[] = [];
  const d: Dependencias = {
    dashboardId: 'dash-uuid',
    identidad: () => Promise.resolve(identidad),
    guestToken: (p) => {
      pedidas.push(p);
      return Promise.resolve('token-secreto');
    },
    log: (e) => logs.push(e),
    ...opciones,
  };
  return { d, pedidas, logs };
}

function post(headers: Record<string, string> = {}) {
  return new Request('http://localhost/superset-guest-token', { method: 'POST', headers });
}

Deno.test('sin JWT responde 401', async () => {
  const { d, pedidas } = deps(null);
  const r = await crearHandler(d)(post());
  assertEquals(r.status, 401);
  assertEquals(pedidas.length, 0);
});

Deno.test('JWT inválido responde 401', async () => {
  const { d } = deps(null);
  const r = await crearHandler(d)(post({ Authorization: 'Bearer basura' }));
  assertEquals(r.status, 401);
});

Deno.test('un ciudadano o un regulador reciben 403', async () => {
  for (const rol of ['ciudadano', 'regulador']) {
    const { d, pedidas } = deps({ usuarioId: 'u1', rol, empresaId: null });
    const r = await crearHandler(d)(post({ Authorization: 'Bearer x' }));
    assertEquals(r.status, 403);
    assertEquals(pedidas.length, 0);
  }
});

Deno.test('operador: guest token filtrado por su empresa', async () => {
  const { d, pedidas } = deps({ usuarioId: 'u1', rol: 'operador', empresaId: EMPRESA });
  const r = await crearHandler(d)(post({ Authorization: 'Bearer x' }));
  assertEquals(r.status, 200);
  assertEquals(await r.json(), { token: 'token-secreto', dashboard_id: 'dash-uuid' });
  assertEquals(pedidas[0].rls, [{ clause: `empresa_id = '${EMPRESA}'` }]);
  assertEquals(pedidas[0].dashboardId, 'dash-uuid');
});

Deno.test('admin: guest token sin filtro', async () => {
  const { d, pedidas } = deps({ usuarioId: 'u2', rol: 'admin', empresaId: null });
  const r = await crearHandler(d)(post({ Authorization: 'Bearer x' }));
  assertEquals(r.status, 200);
  assertEquals(pedidas[0].rls, []);
});

Deno.test('operador sin empresa recibe 403', async () => {
  const { d } = deps({ usuarioId: 'u1', rol: 'operador', empresaId: null });
  assertEquals((await crearHandler(d)(post({ Authorization: 'Bearer x' }))).status, 403);
});

Deno.test('sin dashboard configurado responde 503; Superset caído responde 502', async () => {
  const sin = deps({ usuarioId: 'u1', rol: 'admin', empresaId: null }, { dashboardId: undefined });
  assertEquals((await crearHandler(sin.d)(post({ Authorization: 'Bearer x' }))).status, 503);
  const caido = deps(
    { usuarioId: 'u1', rol: 'admin', empresaId: null },
    { guestToken: () => Promise.reject(new Error('guest_token 500')) },
  );
  assertEquals((await crearHandler(caido.d)(post({ Authorization: 'Bearer x' }))).status, 502);
});

Deno.test('los logs llevan correlation-id y nunca el token', async () => {
  const cid = '11111111-2222-4333-8444-555555555555';
  const { d, logs } = deps({ usuarioId: 'u1', rol: 'operador', empresaId: EMPRESA });
  const r = await crearHandler(d)(post({ Authorization: 'Bearer jwt-del-usuario', 'x-correlation-id': cid }));
  assertEquals(r.headers.get('x-correlation-id'), cid);
  assertEquals(logs.at(-1)?.correlation_id, cid);
  const texto = JSON.stringify(logs);
  assertEquals(texto.includes('token-secreto'), false);
  assertEquals(texto.includes('jwt-del-usuario'), false);
});

Deno.test('un correlation-id que no es UUID se reemplaza', async () => {
  const { d } = deps(null);
  const r = await crearHandler(d)(post({ 'x-correlation-id': "x'; drop" }));
  assertMatch(r.headers.get('x-correlation-id') ?? '', /^[0-9a-f-]{36}$/);
});

Deno.test('OPTIONS responde CORS y GET 405', async () => {
  const { d } = deps(null);
  const h = crearHandler(d);
  const o = await h(new Request('http://localhost/', { method: 'OPTIONS' }));
  assertEquals(o.status, 200);
  assertMatch(o.headers.get('Access-Control-Allow-Headers') ?? '', /x-correlation-id/);
  assertEquals((await h(new Request('http://localhost/'))).status, 405);
});

Deno.test('la cláusula RLS solo acepta UUID', () => {
  assertEquals(clausulaEmpresa(EMPRESA.toUpperCase()), `empresa_id = '${EMPRESA}'`);
  assertThrows(() => clausulaEmpresa("x' or '1'='1"));
});
