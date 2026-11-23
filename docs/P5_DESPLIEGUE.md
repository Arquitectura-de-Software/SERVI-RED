# Persona 5 — entrega de consolidación

## Implementado en este paquete
- Dos vistas materializadas de indicadores sin información personal: `open_data.continuidad_mensual` y `open_data.llenado_mensual`.
- Función de refresco y tarea pg_cron cada 15 minutos, si está habilitado.
- Edge Function protegida por secreto para refresco alternativo.
- Generador de CSV sintético independiente de los datos reales.

## Pendiente de configuración / validación
- Configurar conexión de Superset como `open_data_reader`, con contraseña y TLS.
- Crear/importar datasets y dashboards en Superset y verificar filtros, permisos, y mapas GeoJSON DANE.
- Construir el portal público Angular, descargas CSV/GeoJSON y formulario de solicitudes.
- Ejecutar pruebas de carga y documentar resultados reales.
- Definir y validar el significado de `llenado`: el porcentaje de vinculación implementado es un indicador provisional, no una tasa de completitud de campos.
- `frecuencia_interrupciones` cuenta incidentes por periodo/zona, no SAIFI (faltan usuarios afectados).
- El tiempo medio de restauración requiere fechas válidas; no representa necesariamente MTTR contractual.

## Despliegue
1. Hacer copia de seguridad y comprobar estado de migraciones con `npx supabase migration list --linked`.
2. Ejecutar `npx supabase db push --linked` **solo tras revisar** las migraciones pendientes de otros integrantes.
3. Alternativa controlada: pegar únicamente la nueva migración en Supabase SQL Editor y ejecutar.
4. Validar con `select * from open_data.continuidad_mensual limit 10;` y `select * from open_data.llenado_mensual limit 10;`.
5. Validar tarea: `select jobid,jobname,schedule from cron.job where jobname='p5-refrescar-indicadores';` si existe pg_cron.
6. Para refresco manual: `select open_data.refrescar_indicadores();`.
7. Para la función opcional: `npx supabase secrets set P5_CRON_SECRET='<SECRETO_LARGO>' --project-ref <REF>` y `npx supabase functions deploy p5-refresh --project-ref <REF> --no-verify-jwt`. No publicar el secreto. Programar invocación autenticada en un scheduler seguro; no habilitar acceso público a la función sin el chequeo de secreto.
8. Generar datos: `python3 scripts/p5_generador_sintetico.py --cantidad 5000`. El CSV no altera la base real.

## Advertencias
- No se han probado estas migraciones contra la base de datos de producción; primero usar entorno de pruebas.
- La migración original de Persona 5 ya tiene permisos sobre una vista normal: no borrarla.
- La publicación pública debe incluir política de supresión de grupos pequeños y revisión de privacidad antes de exponer indicadores.
