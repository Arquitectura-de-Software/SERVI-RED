begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create function public.t_dml(p_sql text) returns text language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok:' || n;
exception when others then return 'error:' || sqlstate;
end $$;

insert into auth.users (id) values
  ('c1111111-1111-1111-1111-111111111111');

insert into public.incidente (id, servicio_id, municipio_codigo)
values (
  '20000000-0000-0000-0000-000000000001',
  (select id from public.servicio where tipo = 'energia'),
  '11001'
);

insert into public.reporte (
  id, client_request_id, ciudadano_id, servicio_id, municipio_codigo, ubicacion, descripcion
)
values (
  '10000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  'c1111111-1111-1111-1111-111111111111',
  (select id from public.servicio where tipo = 'energia'),
  '11001',
  extensions.st_setsrid(extensions.st_makepoint(-74.07, 4.65), 4326)::extensions.geography,
  'Texto privado del reporte'
);

update public.reporte
set estado = 'vinculado',
    incidente_id = '20000000-0000-0000-0000-000000000001'
where id = '10000000-0000-0000-0000-000000000001';

update public.incidente
set estado = 'en_atencion'
where id = '20000000-0000-0000-0000-000000000001';

insert into public.denuncia (
  id, client_request_id, servicio_id, municipio_codigo, descripcion, seguimiento_hash
)
values (
  '30000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000002',
  (select id from public.servicio where tipo = 'energia'),
  '11001',
  'Descripción privada de denuncia',
  'hash-privado-de-prueba'
);

update public.denuncia
set estado = 'en_revision'
where id = '30000000-0000-0000-0000-000000000001';

select is((select count(*) from public.evento_outbox where tipo = 'reporte.creado'),
  1::bigint, 'insertar un reporte encola reporte.creado');
select is((select count(*) from public.evento_outbox where tipo = 'reporte.estado_cambiado'),
  1::bigint, 'cambiar el estado de un reporte encola un evento');
select is((select count(*) from public.evento_outbox where tipo = 'incidente.estado_cambiado'),
  1::bigint, 'cambiar el estado de un incidente encola un evento');
select is((select count(*) from public.evento_outbox where tipo = 'denuncia.estado_cambiado'),
  1::bigint, 'cambiar el estado de una denuncia encola un evento');
select ok(
  (select correlation_id is not null from public.evento_outbox where tipo = 'reporte.creado'),
  'cada evento recibe un correlation_id'
);
select ok(
  (select not (payload ? 'ciudadano_id' or payload ? 'descripcion' or payload ? 'ubicacion')
   from public.evento_outbox where tipo = 'reporte.creado'),
  'el evento de reporte no contiene datos personales ni contenido privado'
);

create temporary table eventos_reclamados on commit drop as
select * from public.reclamar_eventos_outbox(10, 60);

select is((select count(*) from eventos_reclamados), 4::bigint,
  'el consumidor reclama los cuatro eventos disponibles');
select ok(
  (select bool_and(lease_token is not null and intentos = 1) from eventos_reclamados),
  'la reclamación crea un lease e incrementa intentos'
);
select ok(
  not has_function_privilege('anon', 'public.reclamar_eventos_outbox(integer,integer)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.reclamar_eventos_outbox(integer,integer)', 'EXECUTE'),
  'solo el servidor puede reclamar eventos'
);

select is(public.t_dml(
  'select public.registrar_fallo_evento_outbox('
  || (select id::text from eventos_reclamados where tipo = 'reporte.creado')
  || ', ''00000000-0000-0000-0000-000000000000'', ''token invalido'')'
), 'error:P0002', 'un lease inválido no puede modificar el evento');

select is(public.registrar_fallo_evento_outbox(
  (select id from eventos_reclamados where tipo = 'reporte.creado'),
  (select lease_token from eventos_reclamados where tipo = 'reporte.creado'),
  'Fallo temporal de prueba'
)::text, 'pendiente', 'el primer fallo deja el evento pendiente para reintento');

select ok(
  (select intentos = 1 and siguiente_intento > now()
       and lease_token is null and bloqueado_hasta is null
   from public.evento_outbox
   where tipo = 'reporte.creado'),
  'el fallo registra el error, agenda el reintento y libera el lease'
);
select ok(
  (select extract(epoch from (siguiente_intento - now())) between 14 and 16
   from public.evento_outbox
   where tipo = 'reporte.creado'),
  'el primer reintento usa un backoff de aproximadamente 15 segundos'
);

do $$
declare
  v_token uuid;
  v_estado public.estado_evento;
  v_intento integer;
begin
  for v_intento in 2..5 loop
    update public.evento_outbox
    set siguiente_intento = now()
    where tipo = 'reporte.creado';

    select c.lease_token into v_token
    from public.reclamar_eventos_outbox(1, 60) c
    where c.tipo = 'reporte.creado';

    if v_token is null then
      raise exception 'No se pudo reclamar el intento %', v_intento;
    end if;

    v_estado := public.registrar_fallo_evento_outbox(
      (select id from public.evento_outbox where tipo = 'reporte.creado'),
      v_token,
      'Fallo persistente de prueba'
    );

    if v_intento < 5 and v_estado <> 'pendiente' then
      raise exception 'El intento % debió quedar pendiente', v_intento;
    end if;
    if v_intento = 5 and v_estado <> 'fallido' then
      raise exception 'El quinto intento debió quedar fallido';
    end if;
  end loop;
end;
$$;

select is((select estado::text from public.evento_outbox where tipo = 'reporte.creado'),
  'fallido', 'el evento agotado queda en la cola terminal de fallos');
select is((select intentos from public.evento_outbox where tipo = 'reporte.creado'),
  5, 'el evento no supera cinco intentos');

update public.evento_outbox
set bloqueado_hasta = now() - interval '1 second'
where tipo = 'reporte.estado_cambiado';

create temporary table eventos_reclamados_de_nuevo on commit drop as
select * from public.reclamar_eventos_outbox(1, 60);

select ok(
  (select n.lease_token <> a.lease_token and n.intentos = 2
   from eventos_reclamados a
   join eventos_reclamados_de_nuevo n on n.id = a.id
   where a.tipo = 'reporte.estado_cambiado'),
  'un lease vencido vuelve a reclamarse con token nuevo'
);
select is(public.t_dml(
  'select public.marcar_evento_outbox_procesado('
  || (select id::text from eventos_reclamados where tipo = 'reporte.estado_cambiado')
  || ', '''
  || (select lease_token::text from eventos_reclamados where tipo = 'reporte.estado_cambiado')
  || ''')'
), 'error:P0002', 'el token anterior no puede confirmar un lease reclamado de nuevo');
select public.marcar_evento_outbox_procesado(
  (select id from eventos_reclamados_de_nuevo where tipo = 'reporte.estado_cambiado'),
  (select lease_token from eventos_reclamados_de_nuevo where tipo = 'reporte.estado_cambiado')
);

select public.marcar_evento_outbox_procesado(
  (select id from eventos_reclamados where tipo = 'incidente.estado_cambiado'),
  (select lease_token from eventos_reclamados where tipo = 'incidente.estado_cambiado')
);
select is((select estado::text from public.evento_outbox where tipo = 'incidente.estado_cambiado'),
  'procesado', 'el consumidor puede confirmar un evento procesado');
select ok(
  (select procesado_en is not null and lease_token is null and bloqueado_hasta is null
   from public.evento_outbox where tipo = 'incidente.estado_cambiado'),
  'confirmar procesamiento guarda la fecha y libera el lease'
);

select * from finish();
rollback;
