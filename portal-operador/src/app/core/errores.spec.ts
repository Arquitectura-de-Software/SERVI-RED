import { exigir, traducirError } from './errores';

describe('traducirError', () => {
  it('42501 es falta de permiso', () => {
    expect(traducirError({ code: '42501', message: 'No gestiona este incidente' })).toEqual({
      tipo: 'permiso',
      codigo: '42501',
      mensaje: 'No gestiona este incidente',
    });
  });

  it('PT409 conserva el hint con los estados permitidos', () => {
    const e = traducirError({
      code: 'PT409',
      message: 'Transición no permitida: recibido -> restablecido',
      hint: 'Desde recibido se puede pasar a: en_atencion, cerrado',
    });
    expect(e.tipo).toBe('conflicto');
    expect(e.detalle).toContain('en_atencion');
  });

  it('PT400 y PT404 se distinguen', () => {
    expect(traducirError({ code: 'PT400', message: 'x' }).tipo).toBe('datos');
    expect(traducirError({ code: 'PT404', message: '' }).mensaje).toMatch(/no existe/);
  });

  it('un fallo de red se reconoce para reintentar', () => {
    expect(traducirError(new TypeError('Failed to fetch')).tipo).toBe('red');
  });

  it('un error ya traducido se devuelve igual', () => {
    const e = { tipo: 'datos' as const, mensaje: 'falta el motivo' };
    expect(traducirError(e)).toBe(e);
  });

  it('exigir devuelve los datos o lanza el error traducido', () => {
    expect(exigir({ data: [1], error: null })).toEqual([1]);
    expect(() => exigir({ data: null, error: { code: '42501', message: 'no' } })).toThrow();
  });
});
