import { Component, DestroyRef, OnInit, computed, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { TiempoRealService } from '../../core/tiempo-real.service';

/** Marco del portal: navegación según el rol, estado del tiempo real y salida. */
@Component({
  selector: 'app-shell',
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <header class="barra">
      <a class="marca" [routerLink]="rol() === 'regulador' ? '/exportar' : '/mapa'">SERVI-RED <span>Operación</span></a>
      <nav aria-label="Secciones">
        @if (rol() !== 'regulador') {
          <a routerLink="/mapa" routerLinkActive="activo">Incidentes</a>
        }
        @if (rol() === 'operador') {
          <a routerLink="/moderacion" routerLinkActive="activo">Moderación</a>
        }
        <a routerLink="/exportar" routerLinkActive="activo">Exportar CSV</a>
        @if (rol() !== 'regulador') {
          <a routerLink="/indicadores" routerLinkActive="activo">Indicadores</a>
        }
      </nav>
      <div class="usuario">
        @if (rol() !== 'regulador') {
          <span [class]="'rt rt-' + tr.estado()" [title]="textoTr()" data-testid="estado-tiempo-real">
            ● {{ textoTr() }}
          </span>
        }
        <span data-testid="usuario">{{ nombre() }}</span>
        <button type="button" class="secundario" (click)="salir()">Salir</button>
      </div>
    </header>
    <main class="contenido">
      <router-outlet />
    </main>
  `,
  styles: `
    .barra { display: flex; flex-wrap: wrap; gap: .75rem 1.5rem; align-items: center; padding: .6rem 1.25rem;
      background: var(--primario); color: #fff; }
    .marca { color: #fff; font-weight: 700; text-decoration: none; font-size: 1.1rem; }
    .marca span { font-weight: 400; opacity: .85; }
    nav { display: flex; flex-wrap: wrap; gap: .25rem; flex: 1; }
    nav a { color: #fff; text-decoration: none; padding: .35rem .7rem; border-radius: 6px; opacity: .9; }
    nav a.activo, nav a:hover { background: rgba(255,255,255,.18); opacity: 1; }
    .usuario { display: flex; gap: .75rem; align-items: center; font-size: .9rem; }
    .usuario .secundario { color: #fff; border-color: rgba(255,255,255,.6); background: transparent; }
    .rt { font-size: .8rem; }
    .rt-conectado { color: #9be7a9; } .rt-respaldo { color: #ffd479; } .rt-conectando, .rt-desconectado { color: #ddd; }
    .contenido { padding: 1rem 1.25rem; max-width: 1400px; margin: 0 auto; }
  `,
})
export class Shell implements OnInit {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  protected readonly tr = inject(TiempoRealService);
  private readonly destroy = inject(DestroyRef);

  protected readonly rol = this.auth.rol;
  protected readonly nombre = computed(() => {
    const p = this.auth.perfil();
    if (!p) return '';
    return p.nombre ?? (p.rol === 'admin' ? 'Administrador' : p.rol === 'regulador' ? 'Regulador' : '');
  });
  protected readonly textoTr = computed(
    () =>
      ({
        conectado: 'En vivo',
        conectando: 'Conectando…',
        respaldo: 'Actualiza cada 30 s',
        desconectado: 'Sin tiempo real',
      })[this.tr.estado()],
  );

  ngOnInit(): void {
    const perfil = this.auth.perfil();
    if (perfil) {
      void this.tr.conectar(perfil);
    }
    this.destroy.onDestroy(() => void this.tr.desconectar());
  }

  async salir(): Promise<void> {
    await this.tr.desconectar();
    await this.auth.salir();
    await this.router.navigateByUrl('/login');
  }
}
