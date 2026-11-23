# API del módulo de operación (Persona 4)

Funciones y vistas de las migraciones `p4_*`, expuestas por PostgREST en `/rest/v1`. Todas exigen sesión
(`Authorization: Bearer <jwt>` + `apikey`). Ejemplos con el Supabase local (`http://127.0.0.1:54321`).

## Convenciones

| Código Postgres | HTTP | Significado |
|---|---|---|
| `42501` | 403 | Sin permiso (rol o empresa) |
| `PT400` | 400 | Datos inválidos |
| `PT404` | 404 | No existe o no está en su zona |
| `PT409` | 409 | Conflicto (transición no permitida, estado final, `client_request_id` reutilizado). En transiciones, `hint` lista los estados permitidos |

- **`x-correlation-id`** (UUID, opcional): se guarda en `audit_log` y en el outbox. Si no llega, la base genera uno.
- **`p_client_request_id`** (UUID, opcional): un reintento con el mismo id devuelve el resultado ya registrado.
- Las RPC volátiles se llaman con `POST /rest/v1/rpc/<nombre>` y cuerpo JSON con los parámetros.

## Vistas

### `incidente_operacion`
Incidentes para el mapa y la lista. Operador: solo los de su empresa; regulador y admin: todos. Ciudadano: nada.

Columnas: `id, servicio_id, servicio_tipo, servicio, empresa_id, empresa, municipio_codigo, municipio,
departamento_codigo, estado, prioridad, lat, lng, operador_asignado, operador_asignado_nombre, inicio_en,
restablecido_en, cerrado_en, creado_en, actualizado_en, total_reportes, ultimo_reporte_en, prioridad_sugerida`.

`prioridad_sugerida` (1 = más urgente, solo abiertos): 5 − (1 si ≥ 3 reportes, 2 si ≥ 10) − (1 si ≥ 4 h
abierto, 2 si ≥ 12 h) − (1 si energía o acueducto), entre 1 y 5.

```http
GET /rest/v1/incidente_operacion?estado=in.(recibido,en_atencion)&order=prioridad,actualizado_en.desc
```

### `cola_moderacion`
Denuncias en `recibida`/`en_revision` y reportes no descartados sin validación, de la zona del operador.
Columnas: `tipo ('denuncia'|'reporte'), id, servicio_id, servicio_tipo, municipio_codigo, municipio, estado,
descripcion, url_evidencia, lat, lng, incidente_id, creado_en, ultima_decision, ultimo_comentario,
ultima_decision_en`. Nunca incluye `ciudadano_id` ni `seguimiento_hash`.

### `metrics.incidentes_sin_empresa`
Solo `metrics_reader` (Superset). Incidentes abiertos sin empresa por servicio y municipio: `servicio,
municipio_dane, municipio, total, mas_antiguo`.

## Gestión de incidentes

### `cambiar_estado_incidente(p_incidente_id, p_estado, p_mensaje?, p_client_request_id?)`
Operador de la empresa del incidente o admin. Transiciones de `transicion_incidente` (P1). Repetir el estado
actual no hace nada. El mensaje se guarda como respuesta interna.

Respuesta: `incidente_id, estado, restablecido_en, cerrado_en, actualizado_en, respuesta_id`.
Errores: 403, 400, 404, 409 (`hint`: "Desde recibido se puede pasar a: cerrado, en_atencion").

```http
POST /rest/v1/rpc/cambiar_estado_incidente
{"p_incidente_id":"…","p_estado":"en_atencion","p_mensaje":"Cuadrilla en camino","p_client_request_id":"…"}
```

### `priorizar_incidente(p_incidente_id, p_prioridad)`
Prioridad 1 (más urgente) a 5. Operador de la empresa o admin. Igual prioridad = sin cambio.
Respuesta: `incidente_id, prioridad, actualizado_en`. Errores: 400 (fuera de rango), 403, 404, 409 (cerrado).

### `asignar_incidente(p_incidente_id, p_operador_id | null)`
El operador destino debe estar activo y ser de la empresa del incidente; `null` quita la asignación.
Respuesta: `incidente_id, operador_asignado, actualizado_en`. Errores: 400, 403, 404, 409 (cerrado o sin empresa).

### `asignar_empresa_incidente(p_incidente_id, p_empresa_id)` (solo admin)
Para incidentes sin empresa. La empresa debe cubrir servicio y municipio. Quita el operador asignado si cambia.
Respuesta: `incidente_id, empresa_id, actualizado_en`. Errores: 400, 403, 404, 409.

### `responder(p_mensaje, p_incidente_id?, p_reporte_id?, p_client_request_id?, p_a_reportes=false)`
Solo operador. Con `p_a_reportes = true` (solo con `p_incidente_id`) copia el mensaje a cada reporte
vinculado, para que cada ciudadano lo vea. La línea de tiempo y el CSV cuentan la difusión una vez.
Respuesta: `respuesta_id, respondida_en, reportes_notificados`. Errores: 400, 403, 409.

```http
POST /rest/v1/rpc/responder
{"p_mensaje":"Cuadrilla en camino","p_incidente_id":"…","p_client_request_id":"…","p_a_reportes":true}
```

### `incidentes_cercanos(p_servicio_id, p_lat, p_lng)`
Hasta 5 incidentes abiertos del servicio dentro del radio y la ventana de `config_agrupacion`.
Respuesta: `incidente_id, estado, distancia_m, creado_en, actualizado_en`. Para la app (aviso de duplicados).

## Moderación

### `moderar_denuncia(p_denuncia_id, p_decision, p_comentario?, p_client_request_id?)`
Solo operador con cobertura. `pendiente` → `en_revision`, `aprobada` → `validada`, `rechazada` → `descartada`
(exige comentario). Respuesta: `validacion_id, denuncia_id, estado_denuncia`. Errores: 400, 403, 404, 409 (ya final).

### `moderar_reporte(p_reporte_id, p_decision, p_comentario?, p_client_request_id?)`
`aprobada` o `rechazada` (exige comentario). Rechazar descarta el reporte, lo saca del incidente y recalcula
el centroide; si el incidente queda vacío y seguía en `recibido`, se cierra.
Respuesta: `validacion_id, reporte_id, estado_reporte, incidente_id, incidente_cerrado`. Errores: 400, 403, 404, 409.

## Trazabilidad y exportación

### `linea_tiempo_incidente(p_incidente_id)`
Operador (solo su empresa), regulador o admin. Eventos: `incidente_creado, estado_cambiado,
prioridad_cambiada, asignacion_cambiada, empresa_cambiada, reporte_vinculado, reporte_desvinculado,
reporte_moderado, respuesta`. Respuesta: `ocurrido_en, orden, tipo, descripcion, actor_rol, actor_nombre,
detalle (jsonb)`. Sin datos del ciudadano.

### `exportar_incidentes(p_desde, p_hasta, p_servicio_id?, p_empresa_id?)`
Operador (forzado a su empresa), regulador o admin. Rango ≤ 366 días, fechas de Colombia. Con
`Accept: text/csv` devuelve el CSV (formato en "PERSONA 4.md", sección 13). Cada exportación queda en `audit_log`.

```bash
curl -X POST http://127.0.0.1:54321/rest/v1/rpc/exportar_incidentes \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Accept: text/csv" \
  -H "Content-Type: application/json" -d '{"p_desde":"2026-11-01","p_hasta":"2026-11-30"}'
```

## Procesos internos (sin acceso de clientes)
- `private.agrupar_pendientes(p_limite=200)`: vincula reportes `recibido` sin incidente (pg_cron
  `p4-agrupar-reportes`, cada 30 s). Devuelve cuántos procesó.

## Tiempo real (Broadcast privado)
| Canal | Quién escucha | Eventos y contenido |
|---|---|---|
| `empresa:<empresa_id>` | operadores de esa empresa | `incidente_cambiado` {id, estado, prioridad, empresa_id, operador_asignado, servicio_id, municipio_codigo, operacion}; `cola_cambiada` {tipo, id} |
| `admin` | administradores | los mismos, de todas las empresas |

```ts
await supabase.realtime.setAuth(jwt);
supabase.channel(`empresa:${empresaId}`, { config: { private: true } })
  .on('broadcast', { event: 'incidente_cambiado' }, recargar)
  .subscribe();
```

## Edge Function `superset-guest-token`
`POST /functions/v1/superset-guest-token` con el JWT del usuario. 200 `{token, dashboard_id}` (operador:
RLS `empresa_id = '<su empresa>'`; admin: sin filtro), 401 sin sesión, 403 otro rol, 502 Superset caído,
503 sin configurar. Variables: `SUPERSET_URL, SUPERSET_USER, SUPERSET_PASSWORD, SUPERSET_DASHBOARD_ID`
(`supabase/functions/.env`, no se sube; ver `.env.example`).
