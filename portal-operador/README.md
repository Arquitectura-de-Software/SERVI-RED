# Portal del operador (SERVI-RED, Persona 4)

Angular 21 (standalone, zoneless) + Leaflet/OpenStreetMap + Supabase JS. Consume las vistas y RPC de las
migraciones `p4_*`; toda la seguridad está en la base (RLS y funciones), el portal solo la refleja.

## Requisitos
- Node 24 (Angular 21; Angular 22 exige Node ≥ 24.15).
- Supabase local corriendo (`npx supabase start`) y los usuarios de prueba de `supabase/seed_p4_demo.sql`.

## Comandos
```bash
npm install
npm start            # http://localhost:4200
npm test             # pruebas unitarias (Vitest)
npx playwright install chromium   # una vez
npm run e2e          # pruebas e2e contra el Supabase local
```

## Configuración
`src/environments/environment.ts` solo tiene la URL local y la anon key de demostración del Supabase CLI
(pública, igual en todas las instalaciones). Nunca poner aquí la `service_role` ni claves de la nube.

## Pantallas
| Ruta | Roles | Qué hace |
|---|---|---|
| `/mapa` | operador, admin | Mapa (Leaflet + OSM) y lista de incidentes; filtros por servicio, prioridad, departamento/municipio y estado; orden por prioridad sugerida |
| `/incidentes/:id` | operador, admin | Cambiar estado, priorizar, asignar, responder (opcionalmente visible a los ciudadanos), línea de tiempo, reportes y evidencias |
| `/moderacion` | operador | Cola de denuncias y reportes; rechazar exige motivo |
| `/exportar` | operador, regulador, admin | CSV regulatorio por rango de fechas |
| `/indicadores` | operador, admin | Tablero de Superset embebido (guest token de la Edge Function `superset-guest-token`) o enlace de respaldo |

## Detalles
- Cada llamada lleva `x-correlation-id` (UUID); las acciones llevan `client_request_id` y se reintentan una vez
  si falla la red (la base es idempotente).
- Tiempo real: canal privado `empresa:<id>` (operador) o `admin` (Broadcast). Si el canal falla, la pantalla
  se refresca cada 30 s.
