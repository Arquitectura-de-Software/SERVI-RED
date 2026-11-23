# Persona 5 — consolidación

## Incluido en este parche
- Vista materializada de continuidad y llenado; función de actualización; agregación municipio/departamento.
- RPC pública que no publica celdas de incidentes con menos de cinco observaciones.
- Página Angular `/datos-abiertos` con tabla y exportaciones CSV y GeoJSON de atributos (sin geometrías).
- Edge Function de lectura y script ligero de prueba de latencia.

## Obligatorio antes de entregar
1. Revisar la migración P5 anterior `20261123090000_p5_indicadores_materializados.sql`: usa nombres de columnas incompatibles. **No desplegarla**; retirarla solo si no se aplicó.
2. Validar esquema, permisos, migraciones aplicadas y `npm run build`.
3. Configurar cron en Supabase SQL Editor si pg_cron está activo: `select cron.schedule('p5-refresh','0 * * * *','select open_data.p5_actualizar()');` (requiere permisos apropiados).
4. Crear datasets en Superset con acceso a datos agregados y panel de reguladores con roles; nunca usar acceso anónimo para panel restringido.
5. Embebido de Superset requiere URL, dashboard y guest-token correctamente configurados; no se ha automatizado por falta de acceso al servidor.
6. Solicitudes ciudadanas deben reutilizar el flujo de autenticación y API existentes; no exponer escritura sin validación/RLS.
7. Un mapa real requiere capa DANE y asociación geográfica. GeoJSON exportado aquí tiene `geometry:null` intencionalmente.
8. Generar datos sintéticos en ambiente aislado y validar requisitos de carga 4 y 5, no sobre producción.
9. Revisar el significado funcional de 'frecuencia' y 'tiempo medio de restablecimiento' con el SRS antes de afirmar cumplimiento.

## Comandos locales
`cd portal-operador && npm ci && npm run build`
`git status`

No hacer `supabase db push` sin revisar el historial de migraciones de la nube.
