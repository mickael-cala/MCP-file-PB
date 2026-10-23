#!/usr/bin/env bash
# ============================================================================
#  build.sh - Compile le serveur MCP (PureBasic) pour Linux / macOS
#  Le compilateur est cherche dans l'ordre :
#    1. variable d'environnement PBCOMPILER
#    2. pbcompiler dans le PATH
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")"

SRC="src/fileMCP.pb"
OUT="build/fileMCP"

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

echo "Compilation de $SRC ..."
"$PBC" "$SRC" /EXE "$OUT" /CONSOLE /UNICODE /THREAD

echo "[OK] Executable genere : $OUT"
