Observabilidad de SERVI-RED (Persona 1)

Qué cubre cada requerimiento
- Req. 18, trazabilidad entre componentes: el correlation_id (ver abajo).
- Req. 25, monitoreo: vistas del esquema metrics y dashboard de Superset.
- Req. 26, métricas operativas: reportes por día, incidentes abiertos, eventos del outbox, resumen general, uso de recursos y consultas lentas.
- Req. 27, registro de errores: columna ultimo_error del outbox (máximo 100 caracteres), audit_log y los registros de Supabase.
- Req. 28, observabilidad: correlation_id, vistas de metrics y registros, vistos en conjunto.
- Req. 29, alertas: tabla private.alerta, evaluada cada 5 minutos con pg_cron.

Correlation-id
- Header x-correlation-id con un UUID. Si el cliente no lo envía, la base genera uno por transacción. Un valor mal formado se rechaza.
- Se propaga a evento_outbox.correlation_id, a audit_log.correlation_id y a la respuesta de registrar_reporte.
- Cómo seguir una operación:
    select * from evento_outbox where correlation_id = '<uuid>';
    select * from audit_log where correlation_id = '<uuid>';
  Para buscar el mismo valor en los registros de Supabase, usar el visor de logs del dashboard.
- Quien llame a la API (apps, portales, Edge Functions) debe generar un UUID por acción del usuario y reutilizarlo en todas las llamadas de esa acción.

Reglas de registro para todo el equipo (req. 27)
- Formato: una línea JSON por evento, con estos campos: nivel (info, advertencia, error), componente, correlation_id, mensaje y codigo. Ejemplo en una Edge Function:
    console.log(JSON.stringify({ nivel: "error", componente: "notificaciones", correlation_id: id, codigo: "FCM_TIMEOUT", mensaje: "Fallo al enviar la notificación" }));
- Nunca registrar: nombres, correos, teléfonos, descripciones de reportes o denuncias, coordenadas exactas, códigos de seguimiento, hashes, tokens, claves, direcciones IP ni cuerpos completos de solicitudes.
- Para identificar un registro usar su id (reporte_id, incidente_id), nunca su contenido.
- Los mensajes de error que se guarden (por ejemplo en evento_outbox.ultimo_error) deben ser cortos y sin datos personales.

Alertas
Se evalúan cada 5 minutos con private.evaluar_alertas() y se ven en metrics.alertas_activas y metrics.alertas_recientes. Se cierran solas cuando la condición desaparece y se conservan 30 días.
- outbox_fallidos (crítica): 3 o más eventos en estado fallido. Qué hacer: revisar ultimo_error en evento_outbox; cuando se arregle la causa, devolver los eventos a la cola con reintentar_evento_outbox(id) (solo service_role).
- outbox_atrasado (crítica): un evento pendiente lleva más de 10 minutos. Qué hacer: el consumidor de la Persona 3 no está corriendo o falla. Revisar su Edge Function y los registros de Supabase.
- pico_reportes (advertencia): 20 o más reportes del mismo servicio y municipio en 10 minutos. Posible caída masiva. Avisar a los operadores del municipio y vigilar el rendimiento.
- incidentes_sin_atender (advertencia): incidentes en estado recibido por más de 2 horas. Avisar a los operadores de la empresa.

Métricas técnicas
- metrics.uso_recursos: tamaño de la base de datos frente al límite de 500 MB del plan gratuito, y tamaño de Storage. Revisarla antes de la demo.
- metrics.consultas_lentas: las 20 consultas con mayor tiempo medio (mínimo 5 llamadas). Excluye consultas que mencionen contraseñas, secretos o tokens.
- Solicitudes, tiempos de respuesta y errores de la API: panel de reportes del dashboard de Supabase.
- El plan gratuito pausa el proyecto tras una semana sin uso y conserva pocos días de registros. Reactivarlo con un día de margen antes de la demo.

Decisiones
- No se usan Prometheus ni Grafana: el dashboard de Superset y el panel de Supabase cubren lo necesario y evitan otro servidor.
- Las alertas no se envían fuera de la base de datos. Se consultan en Superset o en metrics.alertas_activas. Un aviso externo (por ejemplo a un webhook) queda como mejora futura.
- No hay trazas distribuidas completas. El correlation_id es la forma de seguir una operación entre componentes.

Dónde se ve todo
- Superset: http://localhost:8088 (en la máquina de la Persona 1). Datasets alertas_activas, alertas_recientes, consultas_lentas y uso_recursos, en la conexión Supabase-metrics.