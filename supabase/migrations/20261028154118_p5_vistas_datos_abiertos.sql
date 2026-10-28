--Devuelve tres columnas: mes, servicio y total de reportes, el municipio y 
-- el identificador del servicio.

CREATE SCHEMA IF NOT EXISTS open_data;

CREATE OR REPLACE VIEW open_data.reportes_mensuales_servicio
WITH (security_invoker = true)
AS
SELECT
    DATE_TRUNC('month', r.creado_en)::date AS mes,
    s.id AS servicio_id,
    s.descripcion AS servicio,
    r.municipio_codigo,
    m.nombre AS municipio,
    COUNT(*) AS total_reportes
FROM public.reporte r
JOIN public.servicio s
    ON r.servicio_id = s.id
LEFT JOIN public.municipio m
    ON r.municipio_codigo = m.codigo_dane
GROUP BY
    DATE_TRUNC('month', r.creado_en)::date,
    s.id,
    s.descripcion,
    r.municipio_codigo,
    m.nombre;