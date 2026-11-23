import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'app-inicio',
  imports: [RouterLink],
  template: `
    <main class="pagina">
      <header class="encabezado">
        <p class="marca">SERVI-RED</p>
        <h1>¿Cómo quieres ingresar?</h1>
        <p>Elige el portal que corresponde a lo que necesitas hacer.</p>
      </header>

      <section class="opciones" aria-label="Portales de SERVI-RED">
        <article class="opcion operador">
          <p class="tipo">GESTIÓN DE SERVICIOS</p>
          <h2>¿Eres operador?</h2>
          <p>Ingresa para consultar incidentes, revisar reportes y gestionar su atención.</p>
          <a class="accion" routerLink="/login">Ingresar al portal de operador</a>
        </article>

        <article class="opcion ciudadano">
          <p class="tipo">INFORMACIÓN PÚBLICA</p>
          <h2>¿Eres ciudadano?</h2>
          <p>Consulta indicadores agregados y descarga datos abiertos de los servicios.</p>
          <a class="accion" routerLink="/datos-abiertos">Consultar el portal público</a>
        </article>
      </section>

      <footer>Información de servicios públicos en un solo lugar.</footer>
    </main>
  `,
  styles: `
    .pagina {
      min-height: 100vh;
      display: grid;
      align-content: center;
      justify-items: center;
      gap: 2rem;
      padding: 2rem 1rem;
      background: linear-gradient(145deg, #f4f6f9, #e9eef5);
    }
    .encabezado { text-align: center; max-width: 42rem; }
    .marca { margin: 0 0 .75rem; color: var(--primario); font-weight: 800; letter-spacing: .14em; }
    h1 { margin: 0; font-size: clamp(1.8rem, 5vw, 2.8rem); }
    .encabezado > p:last-child { color: var(--texto-suave); }
    .opciones { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1.25rem; width: min(58rem, 100%); }
    .opcion {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      min-height: 15rem;
      padding: 1.5rem;
      background: var(--tarjeta);
      border: 1px solid var(--borde);
      border-top: 4px solid var(--primario);
      border-radius: 12px;
      box-shadow: 0 8px 24px #163a6912;
    }
    .ciudadano { border-top-color: #27805a; }
    .tipo { margin: 0; color: var(--texto-suave); font-size: .75rem; font-weight: 700; letter-spacing: .08em; }
    h2 { margin: 1rem 0 .25rem; font-size: 1.35rem; }
    .opcion > p:not(.tipo) { flex: 1; color: var(--texto-suave); line-height: 1.55; }
    .accion {
      display: inline-block;
      padding: .7rem 1rem;
      border-radius: 7px;
      background: var(--primario);
      color: #fff;
      font-weight: 650;
      text-decoration: none;
    }
    .accion:hover { background: var(--primario-oscuro); }
    .ciudadano .accion { background: #21744f; }
    .ciudadano .accion:hover { background: #185c3e; }
    footer { color: var(--texto-suave); font-size: .9rem; text-align: center; }
    @media (max-width: 640px) {
      .opciones { grid-template-columns: 1fr; max-width: 28rem; }
      .opcion { min-height: 13rem; }
    }
  `,
})
export class Inicio {}
