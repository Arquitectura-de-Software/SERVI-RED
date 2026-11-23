import { TestBed } from '@angular/core/testing';
import { signal } from '@angular/core';
import { ActivatedRouteSnapshot, Router, RouterStateSnapshot, UrlTree, provideRouter } from '@angular/router';
import { AuthService } from './auth.service';
import { inicioDe, rolGuard } from './rol.guard';
import { Rol } from './tipos';

function authFalso(rol: Rol | null, conSesion = true) {
  return {
    iniciar: () => Promise.resolve(),
    sesion: signal(conSesion ? ({} as object) : null),
    rol: signal(rol),
  };
}

async function correr(permitidos: Rol[], auth: ReturnType<typeof authFalso>) {
  TestBed.configureTestingModule({
    providers: [provideRouter([]), { provide: AuthService, useValue: auth }],
  });
  const r = await TestBed.runInInjectionContext(() =>
    rolGuard(permitidos)({} as ActivatedRouteSnapshot, {} as RouterStateSnapshot),
  );
  const router = TestBed.inject(Router);
  return r instanceof UrlTree ? router.serializeUrl(r) : r;
}

describe('rolGuard', () => {
  afterEach(() => TestBed.resetTestingModule());

  it('sin sesión manda a /login', async () => {
    expect(await correr(['operador'], authFalso(null, false))).toBe('/login');
  });

  it('deja pasar un rol permitido', async () => {
    expect(await correr(['operador', 'admin'], authFalso('operador'))).toBe(true);
  });

  it('el regulador va a la exportación si no puede ver la ruta', async () => {
    expect(await correr(['operador', 'admin'], authFalso('regulador'))).toBe('/exportar');
  });

  it('el admin no entra a moderación y vuelve al mapa', async () => {
    expect(await correr(['operador'], authFalso('admin'))).toBe('/mapa');
  });

  it('un ciudadano no tiene pantalla en el portal', async () => {
    expect(await correr(['operador', 'regulador', 'admin'], authFalso('ciudadano'))).toBe('/login');
  });
});

describe('inicioDe', () => {
  it('cada rol tiene su pantalla de inicio', () => {
    expect(inicioDe('operador')).toBe('/mapa');
    expect(inicioDe('admin')).toBe('/mapa');
    expect(inicioDe('regulador')).toBe('/exportar');
    expect(inicioDe('ciudadano')).toBe('/login');
  });
});
