Superset de SERVI-RED (Persona 1)

Qué es: la capa de dashboards. Corre en Docker con su propia base de
metadatos. Se conecta a Supabase SOLO con roles de solo lectura
(metrics_reader y open_data_reader). Nunca con postgres ni service_role.

Primera vez
1. Copiar .env.example a .env y cambiar todos los valores.
   SUPERSET_SECRET_KEY: una clave aleatoria larga.
   METADATA_DB_PASSWORD: solo letras y números.
2. docker compose up -d --build
3. Abrir http://localhost:8088 e iniciar sesión con ADMIN_USER y ADMIN_PASSWORD.

Comandos útiles
- Ver estado: docker compose ps
- Ver registros: docker compose logs superset --tail 50
- Apagar: docker compose down
- Apagar y borrar todos los datos de Superset: docker compose down -v

El archivo .env nunca se sube al repositorio.