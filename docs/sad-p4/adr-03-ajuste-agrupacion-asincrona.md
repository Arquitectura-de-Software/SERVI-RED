# Ajuste a ADR-03: la agrupación de reportes es un proceso asíncrono

**Fecha:** 22/11/2026 (Persona 4).

## Contexto
ADR-03 establece que lo secundario se procesa de forma asíncrona y el flujo 8.1 indica que la evaluación
espacial ocurre **después** de confirmar al ciudadano. La primera versión de la agrupación usaba un trigger
AFTER INSERT en `reporte`: la confirmación esperaba a la consulta espacial y la transacción del ciudadano
generaba eventos y auditoría extra.

## Decisión
- `registrar_reporte` (P1) confirma al ciudadano de inmediato; el reporte queda en `recibido` sin incidente.
- Un job de **pg_cron** (`p4-agrupar-reportes`, cada 30 s) ejecuta `private.agrupar_pendientes()`:
  toma hasta 200 reportes pendientes en orden de llegada con `FOR UPDATE SKIP LOCKED` y aplica la regla de
  agrupación (mismo servicio y municipio, `ST_DWithin` al centroide con el radio de `config_agrupacion`,
  actividad dentro de la ventana; si no hay incidente, crea uno).
- Un candado consultivo por servicio y municipio evita incidentes duplicados si dos procesos coinciden.

## Consecuencias
- (+) La respuesta al ciudadano no depende de la consulta espacial.
- (+) El proceso es idempotente y reanudable: si falla, la siguiente ejecución retoma los pendientes.
- (−) Consistencia eventual: un reporte tarda hasta 30 s en aparecer en su incidente. La app (P3) muestra el
  reporte como "recibido" mientras tanto; el portal se entera por Broadcast cuando se crea o cambia el incidente.
- Métrica de vigilancia: `metrics.incidentes_sin_empresa` (incidentes que la agrupación deja sin responsable).
