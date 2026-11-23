// Configuración LOCAL (Supabase CLI). La anon key de abajo es la clave de demostración
// que trae el Supabase CLI: es la misma en todas las instalaciones locales y es pública
// por diseño (la seguridad la da la RLS). Nunca poner aquí la service_role ni claves de la nube.
// Valores: `npx supabase status`.
export const environment = {
  production: false,
  supabaseUrl: 'https://dfjbmgzadgvdfswenuef.supabase.co',
  supabaseAnonKey:
    'sb_publishable_HwuRceE67mCr1AubpP4gGQ_QpJ93CXy',
  // Tablero de Superset embebido (Paso 8). Vacío = se muestra el enlace de respaldo.
  supersetUrl: 'http://localhost:8088',
  supersetDashboardId: '',
};
