# Arranque de backend local

Este documento explica cómo iniciar localmente el backend de SERVI-RED:
Supabase (base de datos, API y Studio) y Apache Superset (dashboards).

## Requisitos

- Windows 10/11 de 64 bits.
- Docker Desktop instalado y abierto. Docker debe estar en estado **Running**.
- Node.js instalado, que incluye `npx`.
- Acceso a internet la primera vez para descargar la CLI de Supabase y las
  imágenes de Docker.
- Espacio disponible para las imágenes y los volúmenes locales de ambos
  servicios.
- El archivo `superset/.env` configurado localmente. Para prepararlo:
  1. Copia `superset/.env.example` como `superset/.env`.
  2. Configura los valores según el documento privado **“claves y contraseñas
     importantes”**. No subas `superset/.env` al repositorio ni compartas sus
     secretos.

## Arranque completo con un comando

El script `scripts/iniciar-backend-local.ps1` inicia Supabase y Apache Superset
en orden. No ejecuta reset de base de datos ni pruebas.

Desde la raíz del repositorio, abre PowerShell y ejecuta:

```powershell
.\scripts\iniciar-backend-local.ps1
```

Si PowerShell bloquea la ejecución del script por la política local, ejecútalo
solo para esta sesión con:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\iniciar-backend-local.ps1
```

El script comprueba que Docker esté activo y que exista `superset/.env`. Si una
etapa falla, muestra el error y se detiene.

## Arrancar paso a paso

Usa estos pasos si prefieres ejecutar cada componente por separado o necesitas
diagnosticar un fallo.

### A. Supabase local

Desde la raíz del repositorio:

```powershell
npx supabase start
```

Abre Supabase Studio en <http://127.0.0.1:54323>. La API local está disponible
en `http://127.0.0.1:54321`.

### B. Apache Superset

Desde la raíz del repositorio, entra primero a su carpeta:

```powershell
cd superset
```

Solo la primera vez, crea `superset/.env` copiando `.env.example` y configura
sus valores con el documento privado **“claves y contraseñas importantes”**.
Luego ejecuta:

```powershell
docker compose up -d --build
```

Abre <http://localhost:8088>. Para el usuario y la contraseña de administrador,
consulta el documento privado **“claves y contraseñas importantes”**.

En el dashboard, comprueba que aparezca el dashboard exportado y que sus
datasets estén cargados. Si el metastore local de Superset está vacío, importa
el archivo ZIP disponible en `superset/dashboards/` desde la interfaz de
Superset.

## Comandos de mantenimiento y comprobación

Ejecuta estos comandos desde la raíz del repositorio.

### Reconstruir la base local y cargar los seeds

```powershell
npx supabase db reset
```

**Importante:** esto elimina y vuelve a crear los datos de la base de datos
local, aplica las migraciones y carga los seeds. Úsalo únicamente contra el
entorno local y cuando necesites reconstruirlo, por ejemplo después de cambios
en migraciones o seeds. No lo ejecutes contra una base compartida o de
producción.

### Probar la base antes de desplegar cambios

```powershell
npx supabase test db
```

Ejecuta las pruebas pgTAP para comprobar que las migraciones, permisos y
comportamientos cubiertos por la suite siguen funcionando antes de subir
cambios a la nube.

### Consultar estado y registros de Superset

Desde `superset/`:

```powershell
docker compose ps
docker compose logs superset --tail 50
```

## Detener los servicios y conservar sus datos

### Detener Supabase

Desde la raíz del repositorio:

```powershell
npx supabase stop
```

### Detener Superset

Desde la raíz del repositorio:

```powershell
docker compose -f superset/docker-compose.yml down
```

Estos comandos detienen los servicios pero conservan los datos persistidos.

## Limpiar los datos locales y detener todo

> **Acciones destructivas:** estos pasos eliminan datos locales de desarrollo.
> No los ejecutes si necesitas conservar reportes de prueba, usuarios, datasets
> u otra información local.

### Restablecer y detener Supabase

Desde la raíz del repositorio:

```powershell
npx supabase db reset
npx supabase stop
```

El reset deja la base recreada con migraciones y seeds, no como una base vacía.

### Borrar los datos persistidos de Superset y detenerlo

Desde la raíz del repositorio:

```powershell
docker compose -f superset/docker-compose.yml down -v
```

La opción `-v` elimina también los volúmenes de Superset: borra su metastore,
configuración de dashboards/datasets guardada en él y estado persistido. Para
volver a usar Superset, ejecuta otra vez el procedimiento de arranque.
