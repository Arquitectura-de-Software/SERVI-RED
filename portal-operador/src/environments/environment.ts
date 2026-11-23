// Configuración LOCAL (Supabase CLI). La anon key de abajo es la clave de demostración
// que trae el Supabase CLI: es la misma en todas las instalaciones locales y es pública
// por diseño (la seguridad la da la RLS). Nunca poner aquí la service_role ni claves de la nube.
// Valores: `npx supabase status`.
export const environment = {
  production: false,
  supabaseUrl: 'http://127.0.0.1:54321',
  supabaseAnonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
  // Tablero de Superset embebido (Paso 8). Vacío = se muestra el enlace de respaldo.
  supersetUrl: 'http://localhost:8088',
  supersetDashboardId: '',
};
