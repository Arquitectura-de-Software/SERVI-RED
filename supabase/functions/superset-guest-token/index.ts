// SERVI-RED | Persona 4 | Edge Function: guest token de Superset para el portal.
// Lógica en handler.ts (probada en handler_test.ts); dependencias en dependencias.ts.
import { crearHandler } from './handler.ts';
import { dependenciasReales } from './dependencias.ts';

Deno.serve(crearHandler(dependenciasReales()));
