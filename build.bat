@echo off
setlocal
rem ============================================================================
rem  build.bat - Compile les 3 serveurs MCP (PureBasic) pour Windows
rem  Le compilateur est cherche dans l'ordre :
rem    1. variable d'environnement PBCOMPILER
rem    2. C:\Program Files\PureBasic\Compilers\pbcompiler.exe (installation par defaut)
rem    3. C:\PureBasic\Compilers\pbcompiler.exe
rem    4. pbcompiler.exe dans le PATH
rem ============================================================================

set "PBC="
if defined PBCOMPILER set "PBC=%PBCOMPILER%"
if not defined PBC if exist "C:\Program Files\PureBasic\Compilers\pbcompiler.exe" set "PBC=C:\Program Files\PureBasic\Compilers\pbcompiler.exe"
if not defined PBC if exist "C:\PureBasic\Compilers\pbcompiler.exe" set "PBC=C:\PureBasic\Compilers\pbcompiler.exe"
if not defined PBC where pbcompiler.exe >nul 2>nul && set "PBC=pbcompiler.exe"

if not defined PBC (
    echo [ERREUR] Compilateur PureBasic introuvable.
    echo          Definissez la variable PBCOMPILER ou ajoutez pbcompiler.exe au PATH.
    exit /b 1
)

if not exist build mkdir build

for %%S in (fileMCP MCP-Fetch-PB MCP-SequentialThinking-PB memoryMCP) do (
    echo Compilation de src\%%S.pb ...
    "%PBC%" "src\%%S.pb" /EXE "build\%%S.exe" /CONSOLE /UNICODE /THREAD
    if errorlevel 1 (
        echo [ERREUR] Echec de la compilation de %%S.
        exit /b 1
    )
)

echo [OK] Executables generes dans build\
