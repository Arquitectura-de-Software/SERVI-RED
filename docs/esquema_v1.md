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
