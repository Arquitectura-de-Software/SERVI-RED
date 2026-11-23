import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { traducirError } from '../../core/errores';
import { inicioDe } from '../../core/rol.guard';

@Component({
  selector: 'app-login',
  imports: [FormsModule],
  template: `
    <div class="login">
      <form class="tarjeta" (ngSubmit)="entrar()" aria-labelledby="titulo-login">
        <h1 id="titulo-login">Portal del operador</h1>
        <p class="ayuda">SERVI-RED · gestión de incidentes de servicios públicos</p>
        <label>Correo
          <input name="email" type="email" autocomplete="username" required [(ngModel)]="email" />
        </label>
        <label>Contraseña
          <input name="password" type="password" autocomplete="current-password" required [(ngModel)]="password" />
        </label>
        @if (error()) {
          <p class="error" role="alert">{{ error() }}</p>
        }
        <button type="submit" [disabled]="cargando()">{{ cargando() ? 'Entrando…' : 'Entrar' }}</button>
      </form>
    </div>
  `,
  styles: `
    .login { min-height: 100vh; display: grid; place-items: center; padding: 1rem; background: var(--fondo-alt); }
    .tarjeta { width: min(380px, 100%); display: grid; gap: .9rem; }
    h1 { margin: 0; font-size: 1.4rem; }
    .ayuda { margin: -.5rem 0 .25rem; color: var(--texto-suave); font-size: .9rem; }
    label { display: grid; gap: .3rem; font-weight: 600; font-size: .9rem; }
  `,
})
export class Login {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected email = '';
  protected password = '';
  protected readonly error = signal<string | null>(null);
  protected readonly cargando = signal(false);

  async entrar(): Promise<void> {
    this.error.set(null);
    this.cargando.set(true);
    try {
      const perfil = await this.auth.entrar(this.email.trim(), this.password);
      await this.router.navigateByUrl(inicioDe(perfil.rol));
    } catch (e) {
      this.error.set(traducirError(e).mensaje);
    } finally {
      this.cargando.set(false);
    }
  }
}
