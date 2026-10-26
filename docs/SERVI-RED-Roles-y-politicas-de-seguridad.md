# SERVI-RED: Roles y políticas de seguridad

Persona 1 · Plataforma de datos, seguridad y operación · Arquitectura de Software · 26 de octubre de 2026

## 1. Principios

- **Denegar por defecto.** Todas las tablas tienen seguridad por filas (RLS) activa. Sin una política que lo permita, nadie accede.
- **El rol nunca lo decide el cliente.** Cada usuario nuevo es ciudadano. Operadores, reguladores y administradores se promueven solo desde el servidor.
- **Mínimo privilegio.** Cada rol ve y modifica solo lo que necesita, incluso a nivel de columna.
- **Anonimato real.** Los ciudadanos usan sesiones anónimas y las denuncias no guardan nada que identifique a quien denuncia.
- **Separación de lo público y lo operacional.** Los dashboards leen vistas agregadas por roles de solo lectura, nunca las tablas operacionales.
- **Trazabilidad.** Las acciones importantes quedan en un registro de auditoría con un identificador que permite seguirlas entre componentes.

## 2. Roles de la plataforma

Son los cuatro valores del tipo `rol_usuario`. Se guardan en la tabla `perfil` y las políticas los consultan con la función `rol_actual()`. Un perfil marcado como inactivo no ve nada.

### Ciudadano

- **Cómo se obtiene:** automáticamente. Al crearse una sesión anónima en Supabase Auth, un trigger crea su perfil como ciudadano y un alias tipo `Ciudadano-xxxxxxxx`. No se guarda correo, teléfono ni nombre.
- **Puede:** registrar reportes con `registrar_reporte()`, ver solo los suyos, ver los incidentes, confirmar un restablecimiento a su nombre, leer las respuestas a sus reportes y subir fotos a su propia carpeta.
- **No puede:** ver reportes de otros, leer denuncias (ni siquiera las suyas), ver indicadores ni auditoría.

### Operador

- **Cómo se obtiene:** `promover_usuario()`, ejecutable solo desde el servidor. Queda asociado a una empresa.
- **Su alcance:** lo define la tabla `empresa_cobertura` (qué empresa presta qué servicio en qué municipio).
- **Puede:** ver reportes y denuncias de los servicios y municipios que cubre su empresa, cambiar su estado, crear y gestionar los incidentes de su empresa, asignarlos a operadores de su misma empresa, responder, validar y leer indicadores.
- **No puede:** editar la descripción o la ubicación de un reporte, saltarse las transiciones de estado válidas, cambiar la empresa de un incidente, ver datos de otras empresas, ni leer la auditoría o la cola de eventos.

### Regulador

- **Cómo se obtiene:** `promover_usuario()`.
- **Puede:** leer indicadores y ver los incidentes.
- **No puede:** ver reportes individuales ni denuncias, ni gestionar nada.

### Administrador

- **Cómo se obtiene:** `promover_usuario()`.
- **Puede:** ver todos los reportes, denuncias, perfiles y la auditoría, gestionar incidentes y cambiar el estado de reportes y denuncias.
- **No puede (desde el cliente):** escribir en la auditoría, tocar la cola de eventos ni ejecutar `promover_usuario()`.

## 3. Quién puede qué

| Dato | Sin sesión | Ciudadano | Operador | Regulador | Admin |
| --- | --- | --- | --- | --- | --- |
| Catálogos (departamentos, municipios, servicios, empresas) | Lee | Lee | Lee | Lee | Lee |
| Reportes | No | Crea y ve los suyos | Ve los de su cobertura y cambia estado e incidente | No | Ve todos y cambia estado e incidente |
| Incidentes | No | Ve todos | Ve todos; crea y gestiona los de su empresa | Ve todos | Ve y gestiona todos |
| Denuncias | Registra y consulta con su código | Igual; no las lee | Ve las de su cobertura y cambia su estado | No | Ve todas y cambia su estado |
| Confirmaciones ciudadanas | No | Crea y ve las suyas | Ve las de incidentes de su empresa | No | Ve todas |
| Respuestas | No | Lee las de sus reportes | Crea y lee las de su cobertura y empresa | No | Lee todas |
| Validaciones | No | No | Crea y edita las propias; ve las de su empresa | No | Ve todas |
| Indicadores | No | No | Lee | Lee | Lee |
| Perfiles y datos de usuario | No | El suyo | El suyo y los compañeros de su empresa | El suyo | Todos |
| Auditoría | No | No | No | No | Lee |
| Cola de eventos (outbox) | No | No | No | No | No (solo el servidor) |
| Fotos de reportes | No | Sube y lee las suyas | Lee las de su cobertura | No | Lee todas |
| Fotos de denuncias | No | Sube, pero no puede leerlas | Lee las de su cobertura | No | Lee todas |

## 4. Roles técnicos de la base de datos

Los roles de la plataforma (sección 2) viven dentro de los datos. Estos son los roles de PostgreSQL y de Supabase con los que se conecta cada pieza.

- **`anon`**: peticiones sin sesión. Solo lee catálogos y puede llamar `registrar_denuncia()` y `consultar_denuncia()`.
- **`authenticated`**: peticiones con sesión, incluidas las anónimas de los ciudadanos. Los cuatro roles de la plataforma entran por aquí, y la RLS los distingue con `rol_actual()`.
- **`service_role`**: el servidor. Se salta la RLS. Lo usan las funciones del outbox, `promover_usuario()` y `reintentar_evento_outbox()`. **Nunca** va en el frontend, en el repositorio ni en los logs.
- **`postgres`**: administración y migraciones.
- **`metrics_reader`**: solo lectura sobre el esquema `metrics`. Lo usa Superset para el dashboard de métricas operativas.
- **`open_data_reader`**: solo lectura sobre el esquema `open_data`. Está reservado para los dashboards públicos de la Persona 5.

Los dos roles de lectura trabajan con transacciones de solo lectura, un tiempo máximo de 30 segundos por consulta y un máximo de 10 conexiones. No pueden crear objetos ni leer tablas operacionales.

## 5. Políticas de seguridad

### 5.1 Funciones de apoyo

`rol_actual()`, `empresa_actual()` y `operador_cubre()` calculan el rol, la empresa y la cobertura del usuario a partir de su sesión. Son `SECURITY DEFINER` con ruta de búsqueda vacía, y las políticas las reutilizan para no repetir lógica.

### 5.2 Permisos por columna

Aunque una política permita actualizar una fila, el cliente solo puede cambiar estas columnas:

- `reporte`: `estado`, `incidente_id`.
- `incidente`: `estado`, `prioridad`, `operador_asignado`, `inicio_en`.
- `denuncia`: `estado`.
- `validacion`: `estado`, `comentario`.

Las fechas de restablecimiento y de cierre las fija un trigger, no el cliente.

### 5.3 Integridad del ciclo de vida

Los incidentes solo avanzan por transiciones permitidas: recibido → en atención → restablecido → cerrado; además recibido → cerrado (descartar) y restablecido → en atención (reabrir). Cualquier otra transición se rechaza.

### 5.4 Anonimato de las denuncias

- La tabla `denuncia` no tiene ninguna columna de autor y no admite `INSERT` directo.
- Se registra con `registrar_denuncia()`, que no exige sesión.
- El cliente genera un código de seguimiento de entre 16 y 256 caracteres y lo guarda en el dispositivo. El servidor guarda solo su hash SHA-256.
- Con `consultar_denuncia(código)` el denunciante ve únicamente el estado y la fecha.
- Los ciudadanos no pueden leer denuncias, y la auditoría nunca guarda el hash.
- La ubicación de una denuncia es opcional y aproximada.

### 5.5 Fotos de evidencia (Storage)

- Dos buckets privados: `evidencias-reportes` y `evidencias-denuncias`. Solo admiten JPEG, PNG y WebP, con un máximo de 5 MB.
- **Reportes:** la ruta debe ser `<id del ciudadano>/<archivo>`. Cada ciudadano solo sube a su carpeta. La ruta guardada en el reporte debe empezar por el id de quien lo crea, y así nadie puede apuntar a la foto de otro. Las lee su autor, los operadores que cubren el reporte y el admin.
- **Denuncias:** nombre plano y aleatorio, sin carpeta por usuario. Quien sube la foto no puede leerla. Solo la leen los operadores que cubren la denuncia y el admin.
- Las fotos se suben antes de crear el reporte o la denuncia, y se sugiere usar una sesión anónima nueva para las denuncias.

### 5.6 Validación y anti-abuso

- `registrar_reporte()` y `registrar_denuncia()` validan campos obligatorios, coordenadas en rango y longitud de textos (reportes: hasta 1000 caracteres; denuncias: entre 10 y 2000).
- **Idempotencia:** repetir una solicitud con el mismo `client_request_id` devuelve el mismo resultado y no duplica nada. Los reintentos no consumen cuota.
- **Límites de solicitudes:**
  - Reportes por usuario: 5 por minuto y 30 por día.
  - Reportes por IP: 60 por minuto y 1000 por día.
  - Denuncias por IP: 3 cada 10 minutos y 10 por día.
- Al superar un límite la respuesta es 429. La IP se guarda solo como un hash con un secreto, en un esquema que ningún cliente puede leer.

### 5.7 Auditoría y trazabilidad

- Triggers registran en `audit_log` los cambios en incidentes, validaciones, respuestas, reportes y denuncias, con el actor, el estado anterior y el nuevo.
- Solo el admin lee la auditoría. Nadie la escribe desde el cliente.
- Cada operación lleva un `correlation_id` (cabecera `x-correlation-id`) que se propaga a la auditoría y a los eventos del outbox.

### 5.8 Eventos asíncronos

La tabla `evento_outbox` está cerrada para cualquier cliente. Sus funciones (`reclamar_eventos_outbox`, `marcar_evento_outbox_procesado`, `registrar_fallo_evento_outbox`, `reintentar_evento_outbox`) solo las ejecuta `service_role`. Los eventos llevan identificadores, estados, servicio y municipio, y **nunca** descripciones, ubicaciones, evidencias ni hashes. Se limpian automáticamente: los procesados a los 7 días y los fallidos a los 30.

### 5.9 Esquemas

- `public`: tablas operacionales, con RLS, expuestas por la API.
- `private`: límites, secretos y alertas. No está expuesto ni es legible por ningún cliente.
- `metrics`: vistas agregadas de métricas operativas (sin datos personales ni ubicaciones). Las lee `metrics_reader`.
- `open_data`: vistas de datos abiertos de la Persona 5. Las lee `open_data_reader`.

### 5.10 Alertas

Cada 5 minutos se evalúan cuatro reglas: 3 o más eventos fallidos, un evento pendiente de más de 10 minutos, 20 o más reportes del mismo servicio y municipio en 10 minutos, e incidentes sin atender por más de 2 horas. Se consultan en `metrics.alertas_activas`.

### 5.11 Claves y secretos

- La clave `anon` es pública: la seguridad depende de la RLS.
- La clave `service_role` y las contraseñas de la base y de los roles de lectura son secretas y nunca van al repositorio.
- Los archivos `.env` están ignorados por Git.
- Superset se conecta solo como `metrics_reader`, nunca como `postgres` ni `service_role`.

## 6. Límites conocidos

- La cobertura de un operador se calcula por código de municipio, no por geometría. Un reporte sin `municipio_codigo` no lo ve ningún operador. Hoy lo envía el cliente.
- La protección del anonimato depende también de la aplicación: redondear coordenadas, quitar los datos EXIF de las fotos y usar una sesión nueva para denunciar.
- La detección de IP depende de los encabezados del proxy de Supabase. Se verificó con una prueba de límites en la nube.
- En la nube hay datos de demostración con ids que empiezan por `de0de0de-`. Se borran con `docs/limpiar_datos_demo.sql`.
- Las pruebas automáticas cubren la base de datos, pero no el frontend ni la red.

## 7. Cómo verificarlo

Las políticas, los permisos y las funciones tienen pruebas pgTAP en `supabase/tests/database`. Se ejecutan con `npx supabase db reset` y `npx supabase test db`. Toda política nueva o cambio de permisos debe acompañarse de su prueba antes del Pull Request.
