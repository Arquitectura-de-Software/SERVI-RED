import { TestBed } from '@angular/core/testing';
import { SupabaseService } from '../core/supabase.service';
import { conReintento } from './acciones';
import { IncidentesService } from './incidentes.service';
import { ModeracionService } from './moderacion.service';
import { TiempoRealService } from '../core/tiempo-real.service';
import { hoyBogota, restarDias } from '../features/exportar/exportar';
import { radioPrioridad } from '../features/mapa/mapa';

/** Cliente de Supabase falso que guarda las llamadas a rpc. */
function clienteFalso(respuestas: Array<{ data: unknown; error: unknown } | Error>) {
  const llamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  return {
    llamadas,
    client: {
      rpc: vi.fn(async (fn: string, args: Record<string, unknown>) => {
        llamadas.push({ fn, args });
        const r = respuestas.shift();
        if (r instanceof Error) throw r;
        return r;
      }),
    },
  };
}

describe('conReintento', () => {
  it('reintenta una vez ante un fallo de red con el mismo client_request_id', async () => {
    const ids: string[] = [];
    const r = await conReintento(async (id) => {
      ids.push(id);
      if (ids.length === 1) throw new TypeError('Failed to fetch');
      return 'ok';
    });
    expect(r).toBe('ok');
    expect(ids).toHaveLength(2);
    expect(ids[0]).toBe(ids[1]);
  });

  it('no reintenta errores de negocio', async () => {
    let n = 0;
    await expect(
      conReintento(async () => {
        n++;
        throw { code: 'PT409', message: 'no' };
      }),
    ).rejects.toBeTruthy();
    expect(n).toBe(1);
  });
});

describe('IncidentesService', () => {
  afterEach(() => TestBed.resetTestingModule());

  it('cambiarEstado envía client_request_id solo cuando hay mensaje', async () => {
    const falso = clienteFalso([
      { data: [{}], error: null },
      { data: [{}], error: null },
    ]);
    TestBed.configureTestingModule({ providers: [{ provide: SupabaseService, useValue: falso }] });
    const svc = TestBed.inject(IncidentesService);
    await svc.cambiarEstado('i1', 'en_atencion', 'Cuadrilla en camino');
    await svc.cambiarEstado('i1', 'restablecido', null);
    expect(falso.llamadas[0].fn).toBe('cambiar_estado_incidente');
    expect(falso.llamadas[0].args['p_client_request_id']).toMatch(/-/);
    expect(falso.llamadas[1].args['p_client_request_id']).toBeNull();
  });

  it('responder pide la difusión a los reportes', async () => {
    const falso = clienteFalso([{ data: [{ respuesta_id: 'r', reportes_notificados: 3 }], error: null }]);
    TestBed.configureTestingModule({ providers: [{ provide: SupabaseService, useValue: falso }] });
    const r = await TestBed.inject(IncidentesService).responder('i1', 'Hola', true);
    expect(r.reportes_notificados).toBe(3);
    expect(falso.llamadas[0].args).toMatchObject({ p_incidente_id: 'i1', p_a_reportes: true, p_reporte_id: null });
  });

  it('propaga el 409 traducido', async () => {
    const falso = clienteFalso([{ data: null, error: { code: 'PT409', message: 'Transición no permitida', hint: 'Desde cerrado…' } }]);
    TestBed.configureTestingModule({ providers: [{ provide: SupabaseService, useValue: falso }] });
    await expect(TestBed.inject(IncidentesService).cambiarEstado('i1', 'recibido', null)).rejects.toMatchObject({
      tipo: 'conflicto',
      detalle: 'Desde cerrado…',
    });
  });
});

describe('ModeracionService', () => {
  afterEach(() => TestBed.resetTestingModule());

  it('usa la RPC según el tipo y manda el comentario', async () => {
    const falso = clienteFalso([
      { data: [{}], error: null },
      { data: [{}], error: null },
    ]);
    TestBed.configureTestingModule({ providers: [{ provide: SupabaseService, useValue: falso }] });
    const svc = TestBed.inject(ModeracionService);
    await svc.moderar({ tipo: 'denuncia', id: 'd1' }, 'rechazada', 'Sin evidencia');
    await svc.moderar({ tipo: 'reporte', id: 'r1' }, 'aprobada', null);
    expect(falso.llamadas[0]).toMatchObject({ fn: 'moderar_denuncia', args: { p_denuncia_id: 'd1', p_comentario: 'Sin evidencia' } });
    expect(falso.llamadas[1]).toMatchObject({ fn: 'moderar_reporte', args: { p_reporte_id: 'r1', p_decision: 'aprobada' } });
  });
});

describe('TiempoRealService.topicPara', () => {
  it('operador escucha su empresa, admin el canal admin, regulador nada', () => {
    expect(TiempoRealService.topicPara({ id: 'u', rol: 'operador', activo: true, empresaId: 'e1', nombre: null })).toBe('empresa:e1');
    expect(TiempoRealService.topicPara({ id: 'u', rol: 'admin', activo: true, empresaId: null, nombre: null })).toBe('admin');
    expect(TiempoRealService.topicPara({ id: 'u', rol: 'regulador', activo: true, empresaId: null, nombre: null })).toBeNull();
  });
});

describe('utilidades', () => {
  it('fechas de exportación en hora de Colombia', () => {
    // 2026-11-22 03:00 UTC = 2026-11-21 22:00 en Bogotá
    expect(hoyBogota(new Date('2026-11-22T03:00:00Z'))).toBe('2026-11-21');
    expect(restarDias('2026-03-01', 1)).toBe('2026-02-28');
  });

  it('el marcador es más grande cuanto más urgente', () => {
    expect(radioPrioridad(1)).toBeGreaterThan(radioPrioridad(5));
    expect(radioPrioridad(9)).toBe(radioPrioridad(5));
  });
});
