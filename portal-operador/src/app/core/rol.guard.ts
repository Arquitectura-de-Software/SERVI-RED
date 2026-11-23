import { inject } from '@angular/core';
import { CanActivateFn, Router, UrlTree } from '@angular/router';
import { AuthService } from './auth.service';
import { Rol } from './tipos';

/** Pantalla de inicio de cada rol. */
export function inicioDe(rol: Rol | null): string {
  return rol === 'regulador' ? '/exportar' : rol === 'operador' || rol === 'admin' ? '/mapa' : '/login';
}

/**
 * Deja pasar solo a los roles indicados. Sin sesión -> /login; con un rol sin
 * permiso -> a su pantalla de inicio. Es comodidad de la interfaz: la seguridad
 * real está en la RLS y en las RPC de la base.
 */
export function rolGuard(permitidos: Rol[]): CanActivateFn {
  return async (): Promise<boolean | UrlTree> => {
    const auth = inject(AuthService);
    const router = inject(Router);
    await auth.iniciar();
    const rol = auth.rol();
    if (!auth.sesion() || !rol) {
      return router.parseUrl('/login');
    }
    if (permitidos.includes(rol)) {
      return true;
    }
    return router.parseUrl(inicioDe(rol));
  };
}
