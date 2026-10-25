import os
from urllib.parse import quote_plus

# Todo secreto viene del entorno (archivo .env, que no se sube al repositorio).
SECRET_KEY = os.environ["SUPERSET_SECRET_KEY"]

# Base de metadatos de Superset: es un Postgres propio, NO es Supabase.
SQLALCHEMY_DATABASE_URI = "postgresql+psycopg2://superset:{}@superset-db:5432/superset".format(
    quote_plus(os.environ["METADATA_DB_PASSWORD"])
)

# Límites razonables para consultas manuales
ROW_LIMIT = 5000
SQLLAB_TIMEOUT = 60

# Bloquea conexiones inseguras (por ejemplo, SQLite) desde la interfaz
PREVENT_UNSAFE_DB_CONNECTIONS = True

# La Persona 5 activará aquí el embebido de dashboards cuando lo necesite:
# FEATURE_FLAGS = {"EMBEDDED_SUPERSET": True}