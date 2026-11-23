# **SERVI-RED: División de trabajo, Entrega 2**

El trabajo se reparte entre las cinco personas por módulos verticales: cada una es dueña de su lógica, su interfaz y sus datos. Se usa solo el stack del SAD (Supabase, Power Apps o Kotlin, OpenStreetMap) más Apache Superset para la capa analítica.

## **Arquitectura de referencia**

* Supabase (esquema, RLS, Auth, Storage, eventos, observabilidad): Persona 1\.  
* Apache Superset (despliegue y roles de solo lectura): Persona 1\.  
* App móvil ciudadana (Power Apps, o Kotlin de respaldo según ADR-06): Personas 2 y 3\.  
* Portal web del operador: Persona 4\.  
* Portal público, indicadores y dashboards de Superset: Persona 5\.

## **Persona 1: Plataforma de datos, seguridad y operación**

**Responsabilidades:**

* Modelo físico PostgreSQL/PostGIS a partir del ER Chen, más lo que falta: Incidente, AuditLog y outbox de eventos.  
* Seeds: municipios DANE, empresas y servicios.  
* Supabase Auth con roles (operador, regulador, admin) y claims en el JWT.  
* Políticas RLS (ADR-02), incluida la inserción anónima de denuncias.  
* Buckets de Storage para evidencias.  
* Infraestructura de eventos asíncronos (ADR-03): outbox, triggers, reintentos y cola de fallos.  
* Validación de entradas y protección contra abuso (req. 15 y 16).  
* Observabilidad: logs estructurados, correlation-id, métricas y alertas (req. 18 y 25 a 29).  
* Despliegue de Apache Superset en el docker-compose, con su base de metadatos y Redis opcional.  
* Roles de PostgreSQL de solo lectura: uno limitado al esquema open\_data para los dashboards públicos y otro limitado al esquema de métricas operativas para el dashboard interno. Superset nunca se conecta al rol principal de Supabase ni ve tablas operacionales (req. 12 y 13).  
* Dashboard de métricas operativas en Superset (req. 26: reportes recibidos, incidentes abiertos, notificaciones fallidas). Si el tiempo aprieta, sustituye a Grafana; Prometheus y Grafana quedan solo para métricas técnicas, o se omiten.  
* Entorno local, CI y migraciones versionadas.

**Herramientas:** Supabase CLI, PostgreSQL/PostGIS, SQL/PL/pgSQL, pgTAP, Deno/TypeScript, Docker, GitHub Actions, Apache Superset (despliegue), Grafana/Prometheus (opcional).

**Entregables:**

* Migraciones y ER físico actualizado.  
* Políticas RLS con sus pruebas.  
* Seeds y documento de roles.  
* Outbox con reintentos.  
* Entorno local reproducible y pipeline de CI.  
* Configuración de Superset reproducible y documentación de los roles de base de datos.  
* Dashboard de métricas operativas.  
* SAD: Vista Física y de Despliegue (con Superset), y ajustes a ADR-02 y ADR-03.

## **Persona 2: Móvil, reporte de interrupciones y restablecimiento**

**Responsabilidades:**

* Pantalla de reporte de corte: tipo de servicio, foto, descripción, GPS automático, inicio estimado y área afectada.  
* Confirmación de recibo con ID de trazabilidad.  
* Reporte de restablecimiento y validación comunitaria (confirmaciones de usuarios cercanos).  
* Mapa de reportes cercanos con OpenStreetMap.  
* Lógica propia en RPC y Edge Functions: idempotencia con client\_request\_id (req. 22), detección de duplicados con ST\_DWithin, umbral de confirmaciones y cálculo de duración de la interrupción.

**Herramientas:** Kotlin, SDK de Supabase, PostGIS, mapas OSM.

**Entregables:**

* Flujos móviles de reporte y restablecimiento.  
* Funciones SQL y Edge de su módulo, con pruebas.  
* Colección Postman del contrato.

## **Persona 3: Móvil, base de la app, seguimiento, denuncias anónimas y notificaciones**

**Responsabilidades:**

* Esqueleto de la app: navegación, tema accesible, lenguaje claro (req. 30 y 31\) y cliente API.  
* Conectividad limitada (restricción 4): cola local con reintentos.  
* Seguimiento de reportes por ID sin cuenta, con línea de tiempo de estados.  
* Denuncias anónimas: formulario sin datos personales, anti-abuso y enrutamiento al operador según servicio y municipio.  
* Notificaciones: Edge Function que consume el outbox, push (por ejemplo FCM) y avisos in-app vía Realtime, con registro de fallas (req. 24 y 26).  
* Reporte por voz y reconocimiento al ciudadano reportador.

**Herramientas:** Kotlin, Supabase Realtime, Edge Functions (TypeScript), FCM.

**Entregables:**

* Esqueleto de la app en la primera semana, para que la Persona 2 se conecte.  
* Módulos de seguimiento y denuncias.  
* Función de notificaciones con reintentos.  
* Pruebas de modo sin conexión.

## **Persona 4: Operador, gestión de incidentes (lógica y portal web)**

**Responsabilidades:**

* Lógica de incidentes en SQL y Edge Functions: agrupación de reportes en incidentes (servicio, cercanía y tiempo), máquina de estados con transiciones permitidas aplicada con constraints y triggers (req. 20), asignación de incidentes, moderación de denuncias (Validacion), respuestas del operador (Respuesta), auditoría de acciones (req. 19\) y exportación para SSPD/CRA en CSV.  
* Portal web del operador: login, mapa interactivo con filtros por servicio, severidad, zona y estado, detalle del incidente con línea de tiempo, cola de moderación y actualización en tiempo real (WebSockets).  
* Embeber en su portal un dashboard de Superset con indicadores de gestión (tiempo medio de restablecimiento, incidentes por operador), filtrado por el operador autenticado. Lo construye la Persona 5; la Persona 4 solo lo integra.

**Herramientas:** Angular, Leaflet, Supabase JS (Auth y Realtime), PL/pgSQL, TypeScript (Edge Functions), PostGIS.

**Entregables:**

* Funciones y triggers del ciclo de vida, con pruebas.  
* Portal del operador funcionando.  
* SAD: componentes (C4 nivel 3\) de gestión de incidentes y vista lógica del módulo de operación.

## **Persona 5: Indicadores, datos abiertos y Superset (más consolidación)**

**Responsabilidades:**

* Esquema aislado de datos abiertos y vistas materializadas (ADR-04).  
* Cálculo de indicadores de continuidad (horas promedio de interrupción, frecuencia, tiempo medio de restablecimiento) y llenado de Indicador.  
* Refresco periódico con pg\_cron o una Edge Function programada.  
* Agregación por municipio y departamento, sin datos personales ni operacionales.  
* Datasets de Superset apuntando solo al esquema open\_data y sus vistas materializadas.  
* Dashboards públicos en Superset: continuidad por servicio y periodo, mapa por municipio y departamento (capa deck.gl con GeoJSON de DANE), tendencias y comparativas.  
* Dashboard de reguladores con rol restringido.  
* Portal público: un shell liviano en Angular que embebe los dashboards (SDK de embebido y guest tokens, o enlace directo si el tiempo no alcanza) y la página de descargas de datasets en CSV y GeoJSON, con límite de solicitudes. Ya no programa gráficas a mano.  
* Generador de datos sintéticos, para no depender de que los demás terminen y para pruebas de carga que simulen una caída masiva (req. 4 y 5).

**Herramientas:** SQL (vistas materializadas), pg\_cron, Edge Functions, Apache Superset, SDK de embebido de Superset (opcional), Angular, Leaflet, k6 para carga.

**Entregables:**

* Esquema open\_data y vistas, con pruebas.  
* Dashboards de Superset exportados como archivos (.zip) para importarlos en cualquier entorno, con un documento de dashboards y datasets.  
* Portal público.  
* Generador de datos y reporte de carga.