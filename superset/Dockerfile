FROM apache/superset:6.1.0

USER root
RUN . /app/.venv/bin/activate && uv pip install psycopg2-binary
USER superset

CMD ["/app/docker/entrypoints/run-server.sh"]