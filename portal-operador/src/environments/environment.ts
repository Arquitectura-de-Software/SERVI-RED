// Configuración pública del cliente web. La URL y la clave publicable se incluyen
// en el bundle; la seguridad depende de RLS. Nunca poner aquí la service_role.
export const environment = {
  production: false,
  supabaseUrl: 'https://dfjbmgzadgvdfswenuef.supabase.co',
  supabaseAnonKey:
    'sb_publishable_HwuRceE67mCr1AubpP4gGQ_QpJ93CXy',
  // Configurar cuando Superset tenga una URL accesible desde el portal.
  supersetUrl: 'https://artist-fitted-giving-strict.trycloudflare.com ',
  supersetDashboardId: '1a910b6e-5d17-4ce6-9286-5274fbd92db1',
};
