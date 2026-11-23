# Guía de Fase 7 para Persona 1

Esta guía separa el trabajo que Persona 1 puede completar ahora del que requiere
que existan los portales, la app móvil o las funciones de las demás personas.
El repositorio puede mantenerse como monorepo: cada módulo puede incorporarse
después en su propia carpeta, sin cambiar la ubicación de `supabase/`, `superset/`
ni `docs/`.

## Estado de partida

- Supabase local ya tiene configuración, migraciones, seeds y pruebas pgTAP.
- Superset ya tiene Docker Compose, una plantilla de variables y un dashboard
  exportado. Su configuración inicial está descrita en
  [`../superset/README.txt`](../superset/README.txt).
- Las convenciones de migraciones y secretos están en
  [`convenciones.md`](./convenciones.md); el esquema y los contratos están en
  [`esquema_v1.md`](./esquema_v1.md).
- La prueba de visibilidad de consultas en
  `supabase/tests/database/p1_metricas_tecnicas.test.sql` está marcada como
  `TODO`. pgTAP la reporta como pendiente, sin hacer fallar la suite.
- Aún no hay módulos de las Personas 2–5, GitHub Actions, Edge Functions ni un
  portal listo para publicar.

## 1. Entorno local reproducible (requerimiento 27)

### Lo que se puede completar ahora

Definir y probar el procedimiento de arranque desde un clon limpio. Requiere
Docker Desktop y Supabase CLI. Desde la raíz del repositorio:

1. Iniciar Supabase local:

   ```powershell
   npx supabase start
   ```

2. Crear la base local desde cero. **Esto borra y vuelve a crear los datos de la
   base local**, por lo que no debe usarse para borrar una base compartida o de
   producción:

   ```powershell
   npx supabase db reset
   ```

   Este paso aplica las migraciones y carga `supabase/seed.sql`.

3. Ejecutar las pruebas SQL:

   ```powershell
   npx supabase test db
   ```

   Confirma que la suite termina correctamente y que el único caso pendiente
   conocido sigue identificado como `TODO`.

4. En otra terminal, configurar y levantar Superset según
   [`../superset/README.txt`](../superset/README.txt). El archivo `.env` se crea
   localmente a partir de `.env.example`; nunca se comparte ni se sube al repo.
   Comprueba que `docker compose ps` muestre los servicios de Superset sanos y
   que `http://localhost:8088` permita iniciar sesión.

5. En Superset, prueba la conexión de solo lectura que corresponda al entorno
   disponible y confirma que solo expone las vistas autorizadas. No conectes
   Superset como `postgres`, `service_role` ni con un usuario que pueda leer las
   tablas operacionales.

### Criterio de aceptación

- Otra persona puede seguir estos pasos desde un clon limpio.
- `db reset` aplica todas las migraciones y seeds sin intervención manual.
- `test db` termina con éxito; los `TODO` quedan visibles como pendientes, no se
  convierten en pruebas omitidas silenciosamente.
- Superset inicia y su conexión usa un rol de solo lectura.

### Mejora opcional

Cuando el procedimiento manual esté verificado, crear un script de desarrollo
para Windows que orqueste Supabase y Superset. El script debe informar los
errores de cada comando y no borrar volúmenes de Superset ni datos salvo que el
usuario lo solicite. El comando de Supabase y el de Superset pueden seguir
siendo independientes si un único arranque hace más difícil diagnosticar fallos.

## 2. CI de base de datos (parte del requerimiento 28)

Esta parte **no depende** de que existan los módulos de las demás personas.
El primer workflow debe validar cambios de base de datos en Pull Requests, sin
desplegar nada en la nube:

1. Ejecutar en un runner Windows o Linux con Docker disponible.
2. Instalar una versión fijada de Supabase CLI, para que las ejecuciones sean
   repetibles.
3. Iniciar el stack local y restablecer la base con migraciones y seeds.
4. Ejecutar `supabase test db`.
5. Hacer fallar el workflow ante errores reales; conservar el `TODO` como
   pendiente explícito en el resultado de pgTAP.
6. Ejecutar el workflow en Pull Requests y en cambios a migraciones, seeds,
   configuración o pruebas.

La primera versión del CI no necesita secretos de Supabase en la nube. La
validación debe usar únicamente los servicios locales del runner.

### Despliegue de migraciones a la nube

Es una etapa distinta de las pruebas del Pull Request. Se puede preparar desde
ahora, pero conviene habilitarla solo cuando se defina el proyecto de
integración/demo y el equipo confirme quién aprueba los cambios:

- Usar un job separado, protegido por un GitHub Environment con aprobación
  manual.
- Guardar el token de acceso de Supabase, la referencia del proyecto y los
  datos necesarios para autenticar el despliegue como secretos del entorno.
- Aplicar únicamente migraciones ya revisadas y fusionadas, con
  `supabase db push --linked`.
- No ejecutar `db reset` contra la nube.
- No añadir contraseñas, tokens ni claves a los archivos YAML, al repositorio o
  a los logs.

No automatizar todavía `functions deploy`: no existe `supabase/functions/`.
Agregarlo cuando Persona 3 o Persona 4 entregue funciones Edge y se acuerden
sus pruebas y el entorno destino.

## 3. Variables y secretos (requerimiento 29)

### Acciones disponibles ahora

- Mantener `superset/.env.example` como plantilla sin credenciales reales.
- Crear `superset/.env` solo en la máquina local y verificar que Git lo ignore:

  ```powershell
  git check-ignore -v superset/.env
  git status --short
  ```

- Usar valores distintos para desarrollo, integración y demo; no reutilizar
  contraseñas personales.
- Guardar las variables de CI/despliegue en GitHub Actions Secrets o en un
  GitHub Environment, nunca en el frontend ni en archivos versionados.
- Para las aplicaciones cliente, la `anon` key puede ser pública según las
  convenciones del proyecto, pero la seguridad depende de RLS. La
  `service_role` key siempre es secreta y nunca va en código cliente, páginas
  públicas, archivos `.env` versionados ni logs.

### Comprobación antes de subir cambios

```powershell
git status --short
git diff --check
git check-ignore -v superset/.env
```

Estas comprobaciones ayudan a detectar archivos locales o errores de formato;
no sustituyen revisar el contenido de los archivos que se van a incluir en el
commit.

## 4. Runbook y preparación de Superset (requerimiento 30)

Persona 1 puede documentar y probar ya el runbook de su plataforma, aunque los
dashboards públicos y el portal todavía dependan de Persona 5.

### Lista de operación para la demo

- Confirmar que Docker Desktop está activo y que Supabase local o el proyecto
  remoto elegido está disponible.
- Verificar que las migraciones esperadas estén aplicadas en el entorno de
  destino. En nube, revisar el plan de `db push` antes de confirmarlo.
- Comprobar el inicio de Superset y la conexión de base de datos.
- Verificar con consultas de lectura que `metrics_reader` solo accede a
  `metrics` y que `open_data_reader` solo accede a `open_data`.
- Importar el ZIP exportado del dashboard si el metastore de Superset está
  vacío; confirmar que los datasets y gráficos carguen.
- Revisar el dashboard de métricas operativas de Persona 1 y anotar métricas
  aún no disponibles. Por ejemplo, los datos de notificaciones dependen de que
  exista e integre el consumidor del outbox.
- Confirmar que ningún dashboard o dataset revele datos personales ni permita
  consultas a tablas operacionales.
- Revisar la salud y los logs de Superset con `docker compose ps` y
  `docker compose logs superset --tail 50`.
- Mantener un respaldo del archivo exportado del dashboard; no usar
  `docker compose down -v` como procedimiento habitual, porque borra el
  metastore y los datos persistidos de Superset.

La observabilidad ya documentada (correlation ID, métricas y alertas) está en
[`observabilidad.md`](./observabilidad.md). El runbook puede ampliarse al
integrar los módulos y dashboards de las otras personas.

## 5. Qué se deja para integración del equipo

- **Funciones Edge y su despliegue:** cuando existan en el repo.
- **Publicación en GitHub Pages:** cuando Persona 5 entregue el portal público y
  su proceso de build; si la app se aloja en otro servicio, documentar ese
  destino en vez de asumir Pages.
- **Dashboards públicos, datasets y portal:** corresponden principalmente a
  Persona 5; Persona 1 prepara los roles, la conexión de Superset y el dashboard
  de métricas operativas propio.
- **Portal del operador y app móvil:** pueden agregarse en este mismo
  repositorio como módulos del monorepo si el equipo lo acuerda. Su build y
  despliegue se integran cuando se definan sus carpetas y herramientas.

## Orden recomendado de ejecución

1. Verificar el procedimiento manual de entorno local desde clon limpio.
2. Crear el workflow de CI para reset y pgTAP en Pull Requests.
3. Completar el runbook de despliegue seguro a Supabase y la operación/demo de
   Superset.
4. Documentar secretos y preparar, sin habilitar todavía, el job protegido de
   despliegue a la nube.
5. Añadir despliegues de Edge Functions y frontend cuando los módulos estén
   disponibles y el equipo acuerde sus destinos.
