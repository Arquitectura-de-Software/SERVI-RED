-- =====================================================================
-- SERVI-RED | Persona 1 | Seeds mínimos de desarrollo
-- =====================================================================
-- Departamentos: los 32 departamentos + Bogotá D.C. (códigos DANE).
insert into departamento (codigo_dane, nombre) values
  ('05','Antioquia'), ('08','Atlántico'), ('11','Bogotá, D.C.'), ('13','Bolívar'),
  ('15','Boyacá'), ('17','Caldas'), ('18','Caquetá'), ('19','Cauca'), ('20','Cesar'),
  ('23','Córdoba'), ('25','Cundinamarca'), ('27','Chocó'), ('41','Huila'),
  ('44','La Guajira'), ('47','Magdalena'), ('50','Meta'), ('52','Nariño'),
  ('54','Norte de Santander'), ('63','Quindío'), ('66','Risaralda'), ('68','Santander'),
  ('70','Sucre'), ('73','Tolima'), ('76','Valle del Cauca'), ('81','Arauca'),
  ('85','Casanare'), ('86','Putumayo'),
  ('88','Archipiélago de San Andrés, Providencia y Santa Catalina'),
  ('91','Amazonas'), ('94','Guainía'), ('95','Guaviare'), ('97','Vaupés'), ('99','Vichada');

-- Municipios de prueba (subconjunto; la carga completa DANE queda para después)
insert into municipio (codigo_dane, departamento_codigo, nombre) values
  ('11001','11','Bogotá, D.C.'),
  ('05001','05','Medellín'),
  ('76001','76','Cali'),
  ('08001','08','Barranquilla'),
  ('13001','13','Cartagena de Indias'),
  ('68001','68','Bucaramanga'),
  ('54001','54','Cúcuta'),
  ('15001','15','Tunja'),
  ('25175','25','Chía'),
  ('25754','25','Soacha');

insert into servicio (tipo, descripcion) values
  ('energia',        'Energía eléctrica'),
  ('gas',            'Gas natural domiciliario'),
  ('acueducto',      'Acueducto'),
  ('alcantarillado', 'Alcantarillado'),
  ('aseo',           'Aseo');

-- Empresas DEMO (datos ficticios, solo para desarrollo y pruebas)
insert into empresa (nombre, nit, tipo_entidad) values
  ('Operador Demo Energía',   'DEMO-0001', 'Empresa de servicios públicos'),
  ('Operador Demo Acueducto', 'DEMO-0002', 'Empresa de servicios públicos'),
  ('Operador Demo Gas',       'DEMO-0003', 'Empresa de servicios públicos');

-- Cobertura demo: cada empresa presta su servicio en todos los municipios de prueba
insert into empresa_cobertura (empresa_id, servicio_id, municipio_codigo)
select e.id, s.id, m.codigo_dane
from (values ('DEMO-0001','energia'), ('DEMO-0002','acueducto'), ('DEMO-0003','gas')) v(nit, tipo)
join empresa e on e.nit = v.nit
join servicio s on s.tipo = v.tipo::tipo_servicio
cross join municipio m;
