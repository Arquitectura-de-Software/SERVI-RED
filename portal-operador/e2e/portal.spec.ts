import { expect, test } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { USUARIOS, clienteDe, denunciaAnonima, entrar, reportesCercanos } from './apoyo';

test.describe('acceso por rol', () => {
  test('el operador entra al mapa con moderación', async ({ page }) => {
    await entrar(page, USUARIOS.a1);
    await expect(page).toHaveURL(/\/mapa/);
    await expect(page.getByRole('link', { name: 'Moderación' })).toBeVisible();
    await expect(page.getByTestId('usuario')).toHaveText('Ana Operadora Energía');
    await expect(page.getByTestId('estado-tiempo-real')).toContainText('En vivo');
  });

  test('el regulador solo ve la exportación', async ({ page }) => {
    await entrar(page, USUARIOS.regulador);
    await expect(page).toHaveURL(/\/exportar/);
    await expect(page.getByRole('link', { name: 'Incidentes' })).toHaveCount(0);
    await page.goto('/mapa');
    await expect(page).toHaveURL(/\/exportar/);
  });

  test('el admin ve incidentes pero no modera', async ({ page }) => {
    await entrar(page, USUARIOS.admin);
    await expect(page).toHaveURL(/\/mapa/);
    await expect(page.getByRole('link', { name: 'Moderación' })).toHaveCount(0);
  });

  test('sin sesión se va al login y una clave errada muestra error', async ({ page }) => {
    await page.goto('/mapa');
    await expect(page).toHaveURL(/\/login/);
    await page.getByLabel('Correo').fill(USUARIOS.a1);
    await page.getByLabel('Contraseña').fill('equivocada');
    await page.getByRole('button', { name: 'Entrar' }).click();
    await expect(page.getByRole('alert')).toContainText('incorrectos');
  });
});

test.describe.serial('ciclo de un incidente', () => {
  let incidenteId = '';

  test('3 reportes cercanos forman 1 incidente que ve su empresa', async ({ page }) => {
    const r = await reportesCercanos(3);
    incidenteId = r.incidenteId;
    await entrar(page, USUARIOS.a1);
    const fila = page.locator(`tr[data-id="${incidenteId}"]`);
    await expect(fila).toBeVisible();
    await expect(fila.locator('td').nth(5)).toHaveText('3');
  });

  test('otra empresa no ve el incidente', async ({ page }) => {
    await entrar(page, USUARIOS.b1);
    await expect(page.getByTestId('tabla-incidentes')).toBeVisible();
    await expect(page.locator(`tr[data-id="${incidenteId}"]`)).toHaveCount(0);
    await page.goto(`/incidentes/${incidenteId}`);
    await expect(page.getByText('No se encontró el incidente')).toBeVisible();
  });

  test('asignar, priorizar, atender, restablecer y cerrar', async ({ page }) => {
    await entrar(page, USUARIOS.a1);
    await page.goto(`/incidentes/${incidenteId}`);

    await page.getByTestId('operador').selectOption({ label: 'Andrés Técnico Energía' });
    await page.getByRole('button', { name: 'Asignar', exact: true }).click();
    await expect(page.getByTestId('confirmacion')).toContainText('Asignado a Andrés');
    await expect(page.getByTestId('asignado')).toHaveText('Andrés Técnico Energía');

    await page.getByTestId('nueva-prioridad').selectOption('1');
    await page.getByRole('button', { name: 'Guardar prioridad' }).click();
    await expect(page.getByTestId('prioridad')).toHaveText('1');

    for (const [valor, texto] of [
      ['En atención', 'En atención'],
      ['Restablecido', 'Restablecido'],
      ['Cerrado', 'Cerrado'],
    ]) {
      await page.getByTestId('nuevo-estado').selectOption({ label: valor });
      await page.getByRole('button', { name: 'Cambiar estado' }).click();
      await expect(page.getByTestId('estado')).toHaveText(texto);
    }
    await expect(page.getByRole('button', { name: 'Cambiar estado' })).toHaveCount(0);

    const linea = page.getByTestId('linea-tiempo');
    await expect(linea.locator('li[data-tipo="estado_cambiado"]')).toHaveCount(3);
    await expect(linea.locator('li[data-tipo="asignacion_cambiada"]')).toContainText('Andrés');
    await expect(linea.locator('li[data-tipo="reporte_vinculado"]')).toHaveCount(3);
  });

  test('el CSV del regulador incluye el incidente cerrado', async ({ page }) => {
    await entrar(page, USUARIOS.regulador);
    const descarga = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Descargar CSV' }).click();
    const archivo = await (await descarga).path();
    const csv = (await readFile(archivo, 'utf8')).replace(/^﻿/, '');
    const [cabecera, ...filas] = csv.trim().split('\n');
    expect(cabecera.split(',')).toEqual([
      'incidente_id', 'servicio', 'empresa_nit', 'empresa', 'departamento_dane', 'municipio_dane', 'municipio',
      'estado', 'prioridad', 'reportado_en', 'inicio_en', 'restablecido_en', 'cerrado_en', 'duracion_horas',
      'horas_hasta_atencion', 'total_reportes', 'total_respuestas', 'reabierto',
    ]);
    const fila = filas.find((f) => f.startsWith(incidenteId));
    expect(fila).toBeTruthy();
    expect(fila).toContain('cerrado');
    expect(fila).toContain('DEMO-0001');
    expect(csv).not.toContain('prueba e2e'); // sin descripciones de los ciudadanos
    await expect(page.getByTestId('confirmacion')).toContainText('Se exportaron');
  });
});

test('una transición inválida muestra el error de la base', async ({ page }) => {
  const { incidenteId } = await reportesCercanos(1);
  // Sin tiempo real en esta prueba, para que la pantalla quede desactualizada a propósito.
  await page.routeWebSocket(/\/realtime\//, (ws) => ws.close());
  await entrar(page, USUARIOS.a1);
  await page.goto(`/incidentes/${incidenteId}`);
  await expect(page.getByTestId('estado')).toHaveText('Recibido');

  // Otro operador lo cierra mientras A1 sigue viendo "Recibido".
  const a2 = await clienteDe(USUARIOS.a2);
  const { error } = await a2.rpc('cambiar_estado_incidente', { p_incidente_id: incidenteId, p_estado: 'cerrado' });
  expect(error).toBeNull();

  await page.getByTestId('nuevo-estado').selectOption({ label: 'En atención' });
  await page.getByRole('button', { name: 'Cambiar estado' }).click();
  await expect(page.getByTestId('error')).toContainText('Transición no permitida');
  await expect(page.getByTestId('error')).toContainText('Desde cerrado');
});

test('tiempo real: un cambio hecho por otro operador aparece sin recargar', async ({ page }) => {
  const { incidenteId } = await reportesCercanos(1);
  await entrar(page, USUARIOS.a1);
  await page.goto(`/incidentes/${incidenteId}`);
  await expect(page.getByTestId('prioridad')).toHaveText('3');
  await expect(page.getByTestId('estado-tiempo-real')).toContainText('En vivo');

  const a2 = await clienteDe(USUARIOS.a2);
  const { error } = await a2.rpc('priorizar_incidente', { p_incidente_id: incidenteId, p_prioridad: 2 });
  expect(error).toBeNull();
  await expect(page.getByTestId('prioridad')).toHaveText('2', { timeout: 10_000 });
});

test('moderar una denuncia: rechazar exige motivo', async ({ page }) => {
  const id = await denunciaAnonima('Conexión ilegal en el poste de la esquina (prueba e2e)');
  await entrar(page, USUARIOS.a1);
  await page.goto('/moderacion');
  const tarjeta = page.locator(`article[data-id="${id}"]`);
  await expect(tarjeta).toBeVisible();

  await tarjeta.getByRole('button', { name: 'Rechazar' }).click();
  await expect(page.getByTestId('error')).toContainText('motivo');

  await tarjeta.getByTestId('comentario').fill('No se encontró la conexión en la visita');
  await tarjeta.getByRole('button', { name: 'Rechazar' }).click();
  await expect(page.getByTestId('confirmacion')).toContainText('Denuncia rechazada');
  await expect(tarjeta).toHaveCount(0);
});

test('responder visible a los ciudadanos', async ({ page }) => {
  const { incidenteId } = await reportesCercanos(2);
  await entrar(page, USUARIOS.a1);
  await page.goto(`/incidentes/${incidenteId}`);
  await page.getByTestId('mensaje').fill('Cuadrilla en camino, gracias por reportar');
  await page.getByRole('button', { name: 'Enviar respuesta' }).click();
  await expect(page.getByTestId('confirmacion')).toContainText('2 ciudadano(s)');
  await expect(page.getByTestId('linea-tiempo').locator('li[data-tipo="respuesta"]')).toHaveCount(1);
});

test('indicadores: sin tablero configurado se ofrece el enlace a Superset', async ({ page }) => {
  await entrar(page, USUARIOS.a1);
  await page.getByRole('link', { name: 'Indicadores' }).click();
  await expect(page.getByTestId('respaldo')).toContainText('Abrir Superset');
});
