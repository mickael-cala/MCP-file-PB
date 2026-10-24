#!/usr/bin/env bash
# ============================================================================
#  run_all.sh - Compile tout, lance les tests unitaires puis les tests
#  d'integration Python, et genere un rapport tests/report.html.
#  Code de sortie : 0 si tout passe, 1 sinon.
# ============================================================================
set -u

cd "$(dirname "$0")"

PBC="${PBCOMPILER:-}"
if [ -z "$PBC" ]; then
    PBC="$(command -v pbcompiler || true)"
fi
if [ -z "$PBC" ]; then
    echo "[ERREUR] Compilateur PureBasic introuvable. Definissez PBCOMPILER." >&2
    exit 1
fi

STEP_OK=0
STEP_KO=0

ok()  { STEP_OK=$((STEP_OK + 1)); }
ko()  { STEP_KO=$((STEP_KO + 1)); echo "[FAIL] $1"; }

echo
echo "=== Compilation des serveurs ==="
if ./build.sh; then ok; else ko "compilation serveurs"; fi

echo
echo "=== Compilation des tests unitaires ==="
mkdir -p build
COMPILE_UT=1
"$PBC" tests/test_common.pb /EXE "build/test_common" /CONSOLE /UNICODE /THREAD || COMPILE_UT=0
"$PBC" tests/test_memory.pb /EXE "build/test_memory" /CONSOLE /UNICODE /THREAD || COMPILE_UT=0
"$PBC" tests/test_database.pb /EXE "build/test_database" /CONSOLE /UNICODE /THREAD || COMPILE_UT=0
"$PBC" tests/test_context7.pb /EXE "build/test_context7" /CONSOLE /UNICODE /THREAD || COMPILE_UT=0
"$PBC" tests/test_git.pb /EXE "build/test_git" /CONSOLE /UNICODE /THREAD || COMPILE_UT=0
"$PBC" tests/test_github.pb /EXE "build/test_github" /CONSOLE /UNICODE /THREAD || COMPILE_UT=0
if [ "$COMPILE_UT" -eq 1 ]; then
    ok
else
    ko "compilation tests unitaires"
fi

echo
echo "=== Tests unitaires communs ==="
if [ -x build/test_common ] && ./build/test_common; then
    ok
else
    ko "tests unitaires communs"
fi

echo
echo "=== Tests unitaires Memory ==="
if [ -x build/test_memory ] && ./build/test_memory; then
    ok
else
    ko "tests unitaires memory"
fi

echo
echo "=== Tests unitaires Database ==="
if [ -x build/test_database ] && ./build/test_database; then
    ok
else
    ko "tests unitaires database"
fi

echo
echo "=== Tests unitaires Context7 ==="
if [ -x build/test_context7 ] && ./build/test_context7; then
    ok
else
    ko "tests unitaires context7"
fi

echo
echo "=== Tests unitaires Git ==="
if [ -x build/test_git ] && ./build/test_git; then
    ok
else
    ko "tests unitaires git"
fi

echo
echo "=== Tests unitaires GitHub ==="
if [ -x build/test_github ] && ./build/test_github; then
    ok
else
    ko "tests unitaires github"
fi

echo
echo "=== Tests de robustesse et performance (Phase 6) ==="
if python3 tests/test_robustness.py || python tests/test_robustness.py; then
    ok
else
    ko "robustesse/perf"
fi

echo
echo "=== Tests d'integration Python ==="
if python3 tests/test_mcp.py || python tests/test_mcp.py; then
    ok
else
    ko "tests d'integration"
fi

echo
echo "=== Rapport ==="
echo "Etapes reussies : $STEP_OK, echouees : $STEP_KO"

python3 tests/make_report.py "$STEP_OK" "$STEP_KO" || python tests/make_report.py "$STEP_OK" "$STEP_KO"
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Rapport de tests MCP-file-PB</title></head><body>
<h1>Rapport de tests</h1>
<p>Etapes reussies : $STEP_OK - echouees : $STEP_KO</p>
</body></html>
EOF
echo "Rapport genere : tests/report.html"

[ "$STEP_KO" -eq 0 ]
