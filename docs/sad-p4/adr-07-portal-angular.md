# ADR-07: Portal del operador en Angular + Leaflet

**Estado:** propuesto (Persona 4). **Fecha:** 22/11/2026.

## Contexto
La vista 5.3 del SAD indicaba Power Apps para el portal del operador. Al implementar el módulo de
operación aparecieron requisitos que esa opción cubre mal:
- El flujo 5.2 exige que el operador vea los incidentes nuevos y sus cambios **en tiempo real**
  (WebSockets / Supabase Realtime con canales privados y autorización por RLS).
- ADR-05 fija **Leaflet + OpenStreetMap** para los mapas; el portal debe mostrar incidentes por centroide con
  filtros de servicio, prioridad, zona y estado.
- Restricciones 17 y 19: aislamiento por empresa y trazabilidad de cada acción (correlation-id de punta a punta,
  `client_request_id` para reintentos idempotentes). Se necesita controlar los encabezados de cada llamada.
- El tablero de Superset (P5) debe embeberse con un guest token filtrado por empresa.

## Decisión
Construir el portal como SPA **Angular 21** (componentes standalone, sin zone.js) con `@supabase/supabase-js`,
Leaflet y `@superset-ui/embedded-sdk`, en la carpeta `portal-operador/` del repositorio.
- Toda la lógica de negocio y la seguridad quedan en la base (RPC `p4_*`, RLS de P1); el portal no decide permisos.
- Autenticación con Supabase Auth; el rol se lee de `perfil` con la sesión del usuario.
- Tiempo real con Broadcast privado (`empresa:<id>`, `admin`) y sondeo de respaldo cada 30 s.

## Alternativas
| Opción | Por qué no |
|---|---|
| Power Apps (vista 5.3 original) | Sin WebSockets nativos hacia Supabase; mapas Leaflet y encabezados por llamada requieren componentes personalizados; licenciamiento |
| React / Vue | Viables; Angular se eligió por estructura (inyección de dependencias, guards, formularios) y porque el equipo lo conoce |
| Superset como portal | Es de lectura; no sirve para gestionar estados, moderar ni responder |

## Consecuencias
- (+) Tiempo real, mapas y trazabilidad cumplen 5.2, ADR-05 y las restricciones 17 y 19.
- (+) Pruebas automatizadas: unitarias (Vitest) y e2e (Playwright) contra el Supabase local.
- (−) Un componente más que mantener y desplegar (hosting estático).
- (−) Requiere Node 24; Angular 22 exige Node ≥ 24.15 (se usa Angular 21 por compatibilidad del equipo).
- Se actualiza la vista 5.3 del SAD: "Portal web del operador (Angular)".
