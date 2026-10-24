@echo off
setlocal
rem ============================================================================
rem  run_all.bat - Compile tout, lance les tests unitaires puis les tests
rem  d'integration Python, et genere un rapport tests/report.html.
rem  Code de sortie : 0 si tout passe, 1 sinon.
rem ============================================================================

set "ROOT=%~dp0"
cd /d "%ROOT%"

set "PBC="
if defined PBCOMPILER set "PBC=%PBCOMPILER%"
if not defined PBC if exist "C:\Program Files\PureBasic\Compilers\pbcompiler.exe" set "PBC=C:\Program Files\PureBasic\Compilers\pbcompiler.exe"
if not defined PBC if exist "C:\PureBasic\Compilers\pbcompiler.exe" set "PBC=C:\PureBasic\Compilers\pbcompiler.exe"
if not defined PBC where pbcompiler.exe >nul 2>nul && set "PBC=pbcompiler.exe"

if not defined PBC (
    echo [ERREUR] Compilateur PureBasic introuvable. Definissez PBCOMPILER.
    exit /b 1
)

set /a STEP_OK=0
set /a STEP_KO=0

echo.
echo === Compilation des serveurs ===
call build.bat || (call :ko "compilation serveurs" & goto :report)
call :ok "compilation serveurs"

echo.
echo === Compilation des tests unitaires ===
if not exist build mkdir build
"%PBC%" tests\test_common.pb /EXE build\test_common.exe /CONSOLE /UNICODE /THREAD || (call :ko "compilation tests communs" & goto :report)
"%PBC%" tests\test_memory.pb /EXE build\test_memory.exe /CONSOLE /UNICODE /THREAD || (call :ko "compilation tests memory" & goto :report)
"%PBC%" tests\test_database.pb /EXE build\test_database.exe /CONSOLE /UNICODE /THREAD || (call :ko "compilation tests database" & goto :report)
"%PBC%" tests\test_context7.pb /EXE build\test_context7.exe /CONSOLE /UNICODE /THREAD || (call :ko "compilation tests context7" & goto :report)
"%PBC%" tests\test_git.pb /EXE build\test_git.exe /CONSOLE /UNICODE /THREAD || (call :ko "compilation tests git" & goto :report)
"%PBC%" tests\test_github.pb /EXE build\test_github.exe /CONSOLE /UNICODE /THREAD || (call :ko "compilation tests github" & goto :report)
call :ok "compilation tests unitaires"

echo.
echo === Tests unitaires communs ===
build\test_common.exe 2>&1 || (call :ko "tests unitaires communs" & goto :report)
call :ok "tests unitaires communs"

echo.
echo === Tests unitaires Memory ===
build\test_memory.exe 2>&1 || (call :ko "tests unitaires memory" & goto :report)
call :ok "tests unitaires memory"

echo.
echo === Tests unitaires Database ===
build\test_database.exe 2>&1 || (call :ko "tests unitaires database" & goto :report)
call :ok "tests unitaires database"

echo.
echo === Tests unitaires Context7 ===
build\test_context7.exe 2>&1 || (call :ko "tests unitaires context7" & goto :report)
call :ok "tests unitaires context7"

echo.
echo === Tests unitaires Git ===
build\test_git.exe 2>&1 || (call :ko "tests unitaires git" & goto :report)
call :ok "tests unitaires git"

echo.
echo === Tests unitaires GitHub ===
build\test_github.exe 2>&1 || (call :ko "tests unitaires github" & goto :report)
call :ok "tests unitaires github"

echo.
echo === Tests d'integration Python ===
python tests\test_mcp.py || (call :ko "tests d'integration" & goto :report)
call :ok "tests d'integration"

goto :report

:ok
set /a STEP_OK+=1
exit /b 0

:ko
set /a STEP_KO+=1
echo [FAIL] %~1
exit /b 0

:report
echo.
echo === Rapport ===
echo Etapes reussies : %STEP_OK%, echouees : %STEP_KO%

rem Rapport HTML minimal
(
echo ^<!DOCTYPE html^>
echo ^<html^>^<head^>^<meta charset="utf-8"^>^<title^>Rapport de tests MCP-file-PB^</title^>^</head^>^<body^>
echo ^<h1^>Rapport de tests^</h1^>
echo ^<p^>Etapes reussies : %STEP_OK% - echouees : %STEP_KO%^</p^>
echo ^</body^>^</html^>
) > tests\report.html
echo Rapport genere : tests\report.html

if %STEP_KO% gtr 0 exit /b 1
exit /b 0
