import { Routes } from '@angular/router';
import { rolGuard } from './core/rol.guard';

export const routes: Routes = [
  {
    path: '',
    pathMatch: 'full',
    loadComponent: () => import('./features/inicio/inicio').then((m) => m.Inicio),
  },
  { path: 'datos-abiertos', loadComponent: () => import('./features/publico/publico').then(m => m.Publico) },
  { path: 'login', loadComponent: () => import('./features/login/login').then((m) => m.Login) },
  {
    path: '',
    loadComponent: () => import('./features/shell/shell').then((m) => m.Shell),
    canActivate: [rolGuard(['operador', 'regulador', 'admin'])],
    children: [
      {
        path: 'mapa',
        canActivate: [rolGuard(['operador', 'admin'])],
        loadComponent: () => import('./features/mapa/mapa').then((m) => m.Mapa),
      },
      {
        path: 'incidentes/:id',
        canActivate: [rolGuard(['operador', 'admin'])],
        loadComponent: () => import('./features/detalle/detalle').then((m) => m.Detalle),
      },
      {
        // validacion.operador_id referencia a operador: solo un operador modera.
        path: 'moderacion',
        canActivate: [rolGuard(['operador'])],
        loadComponent: () => import('./features/moderacion/moderacion').then((m) => m.Moderacion),
      },
      {
        path: 'exportar',
        canActivate: [rolGuard(['operador', 'regulador', 'admin'])],
        loadComponent: () => import('./features/exportar/exportar').then((m) => m.Exportar),
      },
      {
        path: 'indicadores',
        canActivate: [rolGuard(['operador', 'admin'])],
        loadComponent: () => import('./features/indicadores/indicadores').then((m) => m.Indicadores),
      },
      { path: '', pathMatch: 'full', redirectTo: 'mapa' },
    ],
  },
  
  {
    path: 'publico',
    loadComponent: () =>
      import('./features/publico/publico').then(m => m.Publico)
  },
{ path: '**', redirectTo: '' },
];
