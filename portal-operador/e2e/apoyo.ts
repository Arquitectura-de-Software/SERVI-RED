import { Page, expect } from '@playwright/test';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { environment } from '../src/environments/environment';

// Usuarios SOLO locales de supabase/seed_p4_demo.sql (contraseña de desarrollo).
export const CLAVE_LOCAL = 'ServiRed-Local-2026';
export const USUARIOS = {
  a1: 'operador.energia1@servired.test',
  a2: 'operador.energia2@servired.test',
  b1: 'operador.acueducto1@servired.test',
  regulador: 'regulador@servired.test',
  admin: 'admin@servired.test',
} as const;

export function cliente(): SupabaseClient {
  return createClient(environment.supabaseUrl, environment.supabaseAnonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function clienteDe(email: string): Promise<SupabaseClient> {
  const c = cliente();
  const { error } = await c.auth.signInWithPassword({ email, password: CLAVE_LOCAL });
  if (error) throw new Error(`No se pudo entrar como ${email}: ${error.message}. ¿Cargó seed_p4_demo.sql?`);
  return c;
}

export async function entrar(page: Page, email: string): Promise<void> {
  await page.goto('/login');
  await page.getByLabel('Correo').fill(email);
  await page.getByLabel('Contraseña').fill(CLAVE_LOCAL);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).not.toHaveURL(/\/login/);
}

/** Punto aleatorio en Bogotá, lejos de otros incidentes de corridas anteriores. */
export function puntoAleatorio(): { lat: number; lng: number } {
  return { lat: 4.55 + Math.random() * 0.2, lng: -74.15 + Math.random() * 0.1 };
}

/**
 * Un ciudadano anónimo registra `n` reportes de energía a ~100 m entre sí y se
 * espera a que el job de pg_cron (cada 30 s) los agrupe. Devuelve el incidente.
 */
export async function reportesCercanos(n = 3): Promise<{ incidenteId: string; reportes: string[] }> {
  const c = cliente();
  const { error } = await c.auth.signInAnonymously();
  if (error) throw error;
  const base = puntoAleatorio();
  const reportes: string[] = [];
  for (let i = 0; i < n; i++) {
    const { data, error: e } = await c.rpc('registrar_reporte', {
      p_client_request_id: crypto.randomUUID(),
      p_servicio_id: 1, // energía (DEMO-0001 cubre Bogotá)
      p_municipio_codigo: '11001',
      p_lat: base.lat + (i * 100) / 111_320,
      p_lng: base.lng,
      p_descripcion: `Sin luz en la cuadra (prueba e2e ${i + 1})`,
    });
    if (e) throw e;
    reportes.push((data as { reporte_id: string }[])[0].reporte_id);
  }
  // El ciudadano lee sus propios reportes: se espera hasta que todos tengan incidente.
  const limite = Date.now() + 75_000;
  while (Date.now() < limite) {
    const { data } = await c.from('reporte').select('id, incidente_id').in('id', reportes);
    const ids = new Set((data ?? []).map((r) => r.incidente_id));
    if (data?.length === n && !ids.has(null) && ids.size === 1) {
      return { incidenteId: [...ids][0] as string, reportes };
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error('La agrupación no ocurrió en 75 s (¿está corriendo pg_cron?)');
}

/** Denuncia anónima de energía en Bogotá. */
export async function denunciaAnonima(texto: string): Promise<string> {
  const { data, error } = await cliente().rpc('registrar_denuncia', {
    p_client_request_id: crypto.randomUUID(),
    p_servicio_id: 1,
    p_municipio_codigo: '11001',
    p_descripcion: texto,
    p_codigo: `e2e-${crypto.randomUUID()}`,
  });
  if (error) throw error;
  return data as string;
}
