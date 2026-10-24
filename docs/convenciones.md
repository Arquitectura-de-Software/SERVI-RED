# Convenciones del proyecto (Persona 1)

## Esquemas
- public: tablas operacionales y catálogos (RLS activo en todas).
- open_data: vistas materializadas y datos abiertos (Persona 5, rol de solo lectura).
- metrics: métricas operativas para el dashboard interno (Persona 1, rol de solo lectura).

## Nombres
- snake_case en español, sin tildes, tablas en singular (reporte, incidente).
- IDs en UUID (gen_random_uuid()). Excepciones: codigo_dane (texto), servicio.id (smallint) y las tablas de log (bigint).
- Fechas en timestamptz (UTC). Ubicaciones en geography(Point, 4326).
- Enumerados para estados y tipos (ver migración 1).

## Migraciones
- Una sola carpeta: supabase/migrations (la CLI no soporta subcarpetas).
- Nombre: <timestamp>_<pN>_<descripcion>.sql, donde pN es la persona dueña (p1, p2, p3, p4, p5).
- Cada persona solo crea migraciones con su prefijo y no edita las de otra persona.
- Nunca se edita una migración ya aplicada: se crea una nueva.

## Estados del incidente
recibido -> en_atencion -> restablecido -> cerrado
Además: recibido -> cerrado (descartar), restablecido -> en_atencion (reabrir).
Se validan en la tabla transicion_incidente.

## Claves
- anon key: pública, va en el frontend (por eso RLS es obligatorio).
- service_role key: secreta, nunca en frontend ni en el repositorio.

## PostGIS en la nube
En el proyecto de Supabase en la nube, el esquema `extensions` no está en el
search_path de las migraciones. Por eso, en migraciones y funciones, los tipos
y funciones de PostGIS se escriben con prefijo:
- extensions.geography(Point, 4326)
- extensions.st_dwithin(...)
Alternativa: fijar el search_path dentro de la función con
`set search_path = public, extensions`.