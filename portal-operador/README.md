# Portal del operador (SERVI-RED, Persona 4)

Angular 21 (standalone, zoneless) + Leaflet/OpenStreetMap + Supabase JS. Consume las vistas y RPC de las
migraciones `p4_*`; toda la seguridad está en la base (RLS y funciones), el portal solo la refleja.

## Requisitos
- Node 24 (Angular 21; Angular 22 exige Node ≥ 24.15).
- Proyecto Supabase accesible y configurado en `src/environments/environment.ts`.
- Para entrar al portal se necesitan usuarios con perfiles y roles de operador/regulador/admin creados en Supabase.

## Comandos
```bash
npm ci
npm start            # http://localhost:4200
npm test             # pruebas unitarias (Vitest)
npx playwright install chromium   # una vez
npm run e2e          # pruebas e2e contra el Supabase local
```

Las pruebas E2E esperan usuarios de `supabase/seed_p4_demo.sql`; ese archivo no está incluido actualmente.

## Configuración
`src/environments/environment.ts` contiene la URL y la clave publicable del proyecto Supabase. La clave
publicable puede estar en el frontend; nunca agregues `service_role` ni otras credenciales privadas.
`supersetUrl` y `supersetDashboardId` deben permanecer vacíos hasta que Superset esté publicado y
configurado. Así el portal no ofrece un enlace local que no funcionaría para sus usuarios.

## Pantallas
| Ruta | Roles | Qué hace |
|---|---|---|
| `/` | público | Portada para elegir entre el portal del operador y la consulta ciudadana de datos abiertos |
| `/login` | público | Inicio de sesión para operador, regulador y admin |
| `/datos-abiertos` | público | Indicadores agregados y descarga de CSV/GeoJSON |
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

## Despliegue estático en Cloudflare Pages

El portal público (`/datos-abiertos`) y el portal del operador son rutas de esta misma aplicación Angular:
se despliega una sola vez desde `portal-operador/`.

1. En Cloudflare, crea un proyecto de Pages e importa el repositorio GitHub.
2. Establece el directorio raíz en `portal-operador`.
3. Usa `npm run build` como comando de build y `dist/portal-operador/browser` como directorio de salida.
4. Define `NODE_VERSION=24` en las variables de entorno de build.
5. Despliega y comprueba directamente tanto `/datos-abiertos` como `/login` en el dominio `pages.dev`.
6. Configura el dominio final en Supabase Auth como URL del sitio y en las URL de redirección permitidas.

La aplicación consume Supabase directamente desde el navegador; nunca agregues `service_role` como variable
de Pages ni al código del portal. Cloudflare Pages aloja el frontend, no Apache Superset. Para habilitar los
indicadores embebidos se requiere publicar Superset por separado y configurar `supersetUrl` y
`supersetDashboardId`.
