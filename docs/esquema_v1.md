Esquema v1 (contrato para las Personas 2 a 5)

Catálogos (lectura pública): departamento, municipio, codigo_postal, servicio, empresa, empresa_cobertura.
Usuarios: perfil (rol), ciudadano (alias anónimo), operador (empresa, cargo).
Núcleo: reporte, incidente, confirmacion_ciudadana, denuncia, validacion, respuesta, indicador.
Transversal: audit_log, evento_outbox, transicion_incidente.

Cambios respecto al ER del SAD
- Se eliminan Usuario.password (lo gestiona Supabase Auth) y Ciudadano.telefono (anonimato y minimización).
- Se agregan Incidente, AuditLog, evento_outbox, Denuncia y confirmacion_ciudadana, que el SAD exige pero el ER no tenía.
- Reporte.latitud/longitud pasan a una sola columna geography (ubicacion).
- Denuncia no tiene ninguna columna que identifique al denunciante. El denunciante consulta su caso con un código de seguimiento; solo se guarda su hash SHA-256.

Para cada persona
- Persona 2: reporte (client_request_id para idempotencia), confirmacion_ciudadana, incidente (lectura).
- Persona 3: reporte (lectura por ciudadano), denuncia, evento_outbox (cuando esté la Fase 3).
- Persona 4: incidente, validacion, respuesta, audit_log, transicion_incidente.
- Persona 5: indicador, y lectura de reporte e incidente para agregados.

Roles y sesiones
- Roles: ciudadano, operador, regulador, admin.
- Los ciudadanos usan sesiones anónimas de Supabase Auth (signInAnonymously). Su id no contiene datos personales y su perfil se crea solo, con rol ciudadano y un alias.
- El rol nunca viene del cliente. Operadores, reguladores y admin se promueven desde el servidor con promover_usuario() (solo service_role o SQL Editor). Coordinar con la Persona 1 para crear usuarios de prueba.
- La cobertura de un operador sale de empresa_cobertura (empresa, servicio, municipio_codigo). No es geoespacial por ahora.

Quién ve y hace qué (RLS activo en todas las tablas)
- reporte: el ciudadano crea y ve los suyos. Para idempotencia usa `registrar_reporte()`; un operador ve los reportes de servicios y municipios que cubre su empresa, y solo puede cambiar estado e incidente_id. Admin ve todo.
- Los reportes necesitan municipio_codigo para que un operador los vea. Por ahora lo envía el cliente. Rellenarlo desde la ubicación será de la Persona 2.
- incidente: cualquier sesión lo ve. Un operador crea y gestiona los de su empresa y cobertura. Columnas editables: estado, prioridad, operador_asignado, inicio_en. Solo se puede asignar a operadores de la misma empresa.
- Estados del incidente: recibido a en_atencion a restablecido a cerrado; además recibido a cerrado (descartar) y restablecido a en_atencion (reabrir). Cualquier otra transición falla con check_violation. Las fechas restablecido_en y cerrado_en las fija el trigger.
- confirmacion_ciudadana: el ciudadano confirma a su nombre y ve las suyas. Operadores ven las de incidentes de su empresa.
- respuesta: la crea un operador, a su nombre. La leen el autor del reporte respondido, operadores y admin. Los ciudadanos no ven respuestas a incidentes.
- validacion: la crea un operador sobre un reporte o denuncia que cubre. Editable: estado y comentario, solo por su autor.
- denuncia: no se inserta directamente. Los ciudadanos no la leen. Un operador que cubre el servicio y municipio la lee y cambia solo su estado.
- indicador: lo leen operadores, reguladores y admin. Lo escriben solo trabajos del servidor.
- audit_log: solo lo lee admin. Lo escriben los triggers (incidente, validacion, respuesta, reporte, denuncia). Nunca guarda el hash de seguimiento.
- evento_outbox: cerrada al cliente. Solo service_role.

Eventos asíncronos (ADR-03)
- `reporte.creado`: al insertar un reporte; payload con `reporte_id`, `servicio_id`, `municipio_codigo` y `creado_en`.
- `reporte.estado_cambiado`: al cambiar el estado de un reporte; payload con el ID, estado anterior/nuevo e incidente asociado.
- `incidente.estado_cambiado`: al cambiar el estado de un incidente; payload con el ID, servicio, municipio, estado anterior/nuevo y fecha del cambio.
- `denuncia.estado_cambiado`: al cambiar el estado de una denuncia; payload con el ID, servicio, municipio, estado anterior/nuevo y fecha del cambio.
- Los payloads no contienen identidad ciudadana, descripción, ubicación, evidencia ni código/hash de seguimiento. Cada fila tiene un `correlation_id` generado por el servidor.
- El consumidor de confianza reclama hasta 100 eventos mediante `reclamar_eventos_outbox(limite, lease_segundos)`. El lease dura entre 30 y 900 segundos y permite reclamar de nuevo un evento si el consumidor se cae.
- Tras cada fallo, se reintenta como máximo 5 veces, con espera exponencial de 15, 30, 60 y 120 segundos. El quinto fallo pasa a `fallido` (cola de fallos); `procesado` es terminal. El detalle del último error se limita a 1000 caracteres.
- Solo `service_role` puede ejecutar las funciones de reclamar, confirmar procesamiento o registrar fallos. Los cambios de datos y su evento outbox se guardan en la misma transacción.

Validación, idempotencia y anti-abuso (Fase 4)
- `reporte.client_request_id` y `denuncia.client_request_id` son únicos. `registrar_reporte(...)` devuelve el reporte existente al reintentar la misma clave desde el mismo ciudadano; una clave usada por otro ciudadano devuelve conflicto HTTP 409. `registrar_denuncia(...)` conserva su comportamiento idempotente.
- `registrar_reporte(p_client_request_id, p_servicio_id, p_municipio_codigo, p_lat, p_lng, p_descripcion, p_url_evidencia, p_inicio_estimado)` requiere sesión ciudadana; devuelve `reporte_id`, `estado`, `creado_en` y `correlation_id`.
- `x-correlation-id` acepta un UUID. Si no se envía, la base genera uno por transacción; un valor mal formado se rechaza. Se propaga a eventos outbox, auditoría y respuesta de `registrar_reporte`.
- La base responde con HTTP 429 al exceder: 5 reportes/minuto y 30/día por ciudadano, además de 20/minuto y 100/día por IP; 3 denuncias/10 minutos y 10/día por IP. Las llamadas públicas requieren una dirección de origen válida en los encabezados confiables del gateway (`cf-connecting-ip` o el último valor de `x-forwarded-for`).
- Los contadores y las cuotas están en el esquema no expuesto `private`; los valores se ajustan con una migración/operación administrativa. La clave de sujeto se almacena como hash con sal interna y los buckets de más de un día se limpian durante las solicitudes. Las entradas inválidas se rechazan en la RPC y con constraints en la base.

Contrato de denuncias (Persona 3)
- registrar_denuncia(p_client_request_id uuid, p_servicio_id smallint, p_municipio_codigo bpchar, p_descripcion text, p_codigo text, p_lat double precision default null, p_lng double precision default null, p_url_evidencia text default null) devuelve el uuid de la denuncia. No exige sesión. Reintentar con el mismo client_request_id devuelve la misma denuncia.
- p_codigo lo genera el cliente (aleatorio, 16 o más caracteres) y lo guarda en el dispositivo. El servidor guarda solo su hash.
- consultar_denuncia(p_codigo text) devuelve estado y creada_en.
- Redondear las coordenadas antes de enviarlas y subir fotos sin EXIF.

Storage (evidencias)
- Buckets privados: evidencias-reportes y evidencias-denuncias. Solo image/jpeg, image/png, image/webp. Máximo 5 MB.
- evidencias-reportes: la ruta debe ser <id_del_ciudadano>/<archivo>. La ruta exacta se guarda en reporte.url_evidencia. Lo leen su autor, los operadores que cubren ese reporte y admin.
- evidencias-denuncias: nombre plano y aleatorio, sin carpetas. Se sube con una sesión anónima NUEVA, distinta de la que crea reportes, para no enlazar la denuncia con un ciudadano. La ruta se guarda en p_url_evidencia. Lo leen solo operadores que cubren la denuncia y admin.
- Orden: primero subir la foto, después crear la fila (reporte o denuncia). Hasta que exista la fila, nadie salvo admin ve la foto.

Pruebas
- Las pruebas de base de datos están en supabase/tests/database. Se corren con: npx supabase test db
- Si cambias una política o una tabla, corre las pruebas antes del Pull Request.

Cómo arrancar (local)

Requisitos: Docker Desktop corriendo, Node.js y Git.

1. Clonar el repositorio y entrar a la carpeta del proyecto.
2. npx supabase start (la primera vez descarga varias imágenes y tarda).
3. npx supabase db reset (aplica las migraciones y carga el seed).
4. Abrir Studio en http://127.0.0.1:54323 y verificar que existen 19 tablas en public y 33 departamentos.

npx supabase status muestra la URL y las claves de la base local. Esas claves sirven solo para desarrollo local.

Reglas del equipo

1. Se trabaja siempre en local. La base de la nube es el entorno de integración y demo: no se modifica desde el dashboard (ni Table Editor ni SQL Editor). Todo cambio de esquema es una migración.
2. Para crear una migración: npx supabase migration new pN_descripcion, donde pN es tu persona (p2, p3, p4 o p5). Por ejemplo: npx supabase migration new p2_funciones_reportes.
3. Nunca se edita una migración que ya existe en el repositorio. Si algo está mal, se crea una migración nueva que lo corrija.
4. Cada cambio entra por rama y Pull Request. La Persona 1 aplica a la nube los cambios ya fusionados (npx supabase db push --linked).
5. No se suben al repositorio contraseñas ni la clave service_role. Los valores de configuración van en archivos .env, que están ignorados por git.
6. En migraciones y funciones, los tipos y funciones de PostGIS se escriben con prefijo extensions. (ver docs/convenciones.md). Lo mismo para extensions.digest.
7. Si necesitas cambiar una tabla de otra persona o del núcleo (reporte, incidente, denuncia), se lo pides a la Persona 1 antes de tocarla.
8. En PowerShell usar curl.exe, no curl.