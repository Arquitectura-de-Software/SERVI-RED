#!/bin/bash
set -uo pipefail

cd "$(dirname "$0")/.."

LOG="p5_verificacion.log"
: > "$LOG"

ejecutar() {
  echo "" | tee -a "$LOG"
  echo "========== $1 ==========" | tee -a "$LOG"
  shift
  "$@" >> "$LOG" 2>&1
  resultado=$?
  if [ "$resultado" -eq 0 ]; then
    echo "OK: $1" | tee -a "$LOG"
  else
    echo "REVISAR: $1 (codigo $resultado)" | tee -a "$LOG"
  fi
}

echo "PERSONA 5 - VERIFICACION AUTOMATICA" | tee -a "$LOG"

ejecutar "Estado Git" git status --short
ejecutar "Migraciones P5" bash -c 'ls supabase/migrations/*p5*'
ejecutar "Funciones P5" bash -c 'find supabase/functions -maxdepth 2 -type f | grep p5'
ejecutar "Archivos Angular" bash -c 'find portal-operador/src -type f | grep -E "indicadores|publico|exportar|mapa"'
ejecutar "Archivos Superset" bash -c 'find superset -maxdepth 3 -type f | head -30'

if [ -f scripts/p5_generador_sintetico.py ]; then
  ejecutar "Sintaxis generador" python3 -m py_compile scripts/p5_generador_sintetico.py
fi

if [ -f scripts/p5_prueba_carga.py ]; then
  ejecutar "Sintaxis prueba de carga" python3 -m py_compile scripts/p5_prueba_carga.py
fi

if [ -f portal-operador/package.json ]; then
  ejecutar "Build Angular" bash -c 'cd portal-operador && npm run build'
fi

ejecutar "Proyecto Supabase" npx supabase projects list

echo ""
echo "VERIFICACION FINALIZADA"
echo "Reporte: $LOG"
echo "No se modifico la base de datos remota."
