--security_invoker = false: permite que la vista acceda a las tablas utilizando los permisos de su propietario.
--REVOKE: evita que cualquier rol tenga acceso a la vista únicamente por pertenecer a PUBLIC.
--GRANT SELECT: autoriza expresamente al rol open_data_reader a consultar la vista.

ALTER VIEW open_data.reportes_mensuales_servicio
SET (security_invoker = false);

REVOKE ALL ON open_data.reportes_mensuales_servicio
FROM PUBLIC;

GRANT SELECT ON open_data.reportes_mensuales_servicio
TO open_data_reader;