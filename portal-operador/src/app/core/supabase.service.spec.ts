import { fetchConCorrelacion } from './supabase.service';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

describe('fetchConCorrelacion', () => {
  it('agrega un x-correlation-id UUID distinto en cada llamada', async () => {
    const vistos: string[] = [];
    const base = vi.fn(async (_i: RequestInfo | URL, init?: RequestInit) => {
      vistos.push(new Headers(init?.headers).get('x-correlation-id') ?? '');
      return new Response('{}');
    });
    const f = fetchConCorrelacion(base as unknown as typeof fetch);
    await f('http://x/rest/v1/a', { headers: { apikey: 'k' } });
    await f('http://x/rest/v1/b');
    expect(vistos[0]).toMatch(UUID);
    expect(vistos[1]).toMatch(UUID);
    expect(vistos[0]).not.toBe(vistos[1]);
  });

  it('conserva los encabezados existentes y un correlation-id ya puesto', async () => {
    let h = new Headers();
    const base = vi.fn(async (_i: RequestInfo | URL, init?: RequestInit) => {
      h = new Headers(init?.headers);
      return new Response('{}');
    });
    await fetchConCorrelacion(base as unknown as typeof fetch)('http://x', {
      headers: { apikey: 'k', 'x-correlation-id': 'fijo' },
    });
    expect(h.get('apikey')).toBe('k');
    expect(h.get('x-correlation-id')).toBe('fijo');
  });
});
