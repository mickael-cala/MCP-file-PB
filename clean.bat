@echo off
rem ============================================================================
rem  clean.bat - Supprime les artefacts de compilation (dossier build)
rem ============================================================================

if exist build rmdir /s /q build
echo [OK] Dossier build supprime.
