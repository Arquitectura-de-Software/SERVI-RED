# Esquema v1 (contrato para las Personas 2 a 5)

Catálogos (lectura pública): departamento, municipio, codigo_postal, servicio, empresa, empresa_cobertura.
Usuarios: perfil (rol), ciudadano (alias anónimo), operador (empresa, cargo).
Núcleo: reporte, incidente, confirmacion_ciudadana, denuncia, validacion, respuesta, indicador.
Transversal: audit_log, evento_outbox, transicion_incidente.

## Cambios respecto al ER del SAD
- Se eliminan Usuario.password (lo gestiona Supabase Auth) y Ciudadano.telefono (anonimato y minimización).
- Se agregan Incidente, AuditLog, evento_outbox, Denuncia y confirmacion_ciudadana, que el SAD exige pero el ER no tenía.
- Reporte.latitud/longitud pasan a una sola columna geography (ubicacion).
- Denuncia no tiene ninguna columna que identifique al denunciante. El denunciante consulta su caso con un código de seguimiento; solo se guarda su hash.

## Para cada persona
- Persona 2: reporte (client_request_id para idempotencia), confirmacion_ciudadana, incidente (lectura).
- Persona 3: reporte (lectura por ciudadano), denuncia, evento_outbox (cuando esté la Fase 3).
- Persona 4: incidente, validacion, respuesta, audit_log, transicion_incidente.
- Persona 5: indicador, y lectura de reporte e incidente para agregados.

## Estado de seguridad
RLS está activo en todas las tablas. Sin políticas, solo los catálogos son legibles. Las políticas por rol llegan con la Fase 2; mientras tanto, en local se trabaja con la clave service_role o con el usuario postgres.

## Cómo arrancar (local)

Requisitos: Docker Desktop corriendo, Node.js y Git.

1. Clonar el repositorio y entrar a la carpeta del proyecto.
2. `npx supabase start` (la primera vez descarga varias imágenes y tarda).
3. `npx supabase db reset` (aplica las migraciones y carga el seed).
4. Abrir Studio en http://127.0.0.1:54323 y verificar que existen 19 tablas en `public` y 33 departamentos.

`npx supabase status` muestra la URL y las claves de la base local. Esas claves sirven solo para desarrollo local.

## Reglas del equipo

1. Se trabaja siempre en local. La base de la nube es el entorno de integración y demo: no se modifica desde el dashboard (ni Table Editor ni SQL Editor). Todo cambio de esquema es una migración.
2. Para crear una migración: `npx supabase migration new pN_descripcion`, donde pN es tu persona (p2, p3, p4 o p5). Por ejemplo: `npx supabase migration new p2_funciones_reportes`.
3. Nunca se edita una migración que ya existe en el repositorio. Si algo está mal, se crea una migración nueva que lo corrija.
4. Cada cambio entra por rama y Pull Request. La Persona 1 aplica a la nube los cambios ya fusionados (`npx supabase db push --linked`).
5. No se suben al repositorio contraseñas ni la clave `service_role`. Los valores de configuración van en archivos `.env`, que están ignorados por git.
6. En migraciones y funciones, los tipos y funciones de PostGIS se escriben con prefijo `extensions.` (ver `docs/convenciones.md`).
7. Si necesitas cambiar una tabla de otra persona o del núcleo (reporte, incidente, denuncia), se lo pides a la Persona 1 antes de tocarla.