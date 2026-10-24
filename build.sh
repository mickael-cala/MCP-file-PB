#!/usr/bin/env bash
# ============================================================================
#  build.sh - Compile les 3 serveurs MCP (PureBasic) pour Linux / macOS
#  Le compilateur est cherche dans l'ordre :
#    1. variable d'environnement PBCOMPILER
#    2. pbcompiler dans le PATH
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")"

PBC="${PBCOMPILER:-}"
if [ -z "$PBC" ]; then
    PBC="$(command -v pbcompiler || true)"
fi

if [ -z "$PBC" ]; then
    echo "[ERREUR] Compilateur PureBasic introuvable." >&2
    echo "         Definissez la variable PBCOMPILER ou ajoutez pbcompiler au PATH." >&2
    exit 1
fi

mkdir -p build

for SRC in fileMCP MCP-Fetch-PB MCP-SequentialThinking-PB memoryMCP; do
    echo "Compilation de src/$SRC.pb ..."
    "$PBC" "src/$SRC.pb" /EXE "build/$SRC" /CONSOLE /UNICODE /THREAD
done

echo "[OK] Executables generes dans build/"
