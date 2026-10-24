# AGENTS.md — Instructions pour les agents IA

Ce fichier guide les agents de codage (Claude Code, Kimi Code, Copilot…)
qui travaillent sur ce dépôt.

## Vue d'ensemble

Serveurs MCP écrits en **PureBasic** (3 exécutables), sources dans `src/` :

- `fileMCP.pb` — gestion de fichiers confinée (`MCP_ROOT`/`MCP_ROOT_SECRET`)
- `MCP-Fetch-PB.pb` — fetch web (HTML → Markdown, protection SSRF)
- `MCP-SequentialThinking-PB.pb` — raisonnement séquentiel
- `memoryMCP.pb` + `memory_core.pbi` — mémoire SQLite (`MCP_MEMORY_DB`)
- `dbMCP.pb` + `db_core.pbi` — exploration SQL (SQLite + PostgreSQL optionnel, lecture seule par defaut)
- `context7MCP.pb` + `context7_core.pbi` — documentation Context7 (WinHTTP sous Windows)

Transport **JSON-RPC 2.0 sur stdin/stdout**, une ligne JSON par message.
Exécutables **console**, 100 % natifs, multi-OS (Windows / Linux / macOS).
Pas de dépendance externe. Le cœur métier d'un serveur va dans un
`src/<serveur>_core.pbi` (testable), le `.pb` ne contient que le `main`.

## Commandes essentielles

```bash
build.bat              # Windows : compile -> build\fileMCP.exe
./build.sh             # Linux/macOS : compile -> build/fileMCP
python tests/test_mcp.py   # tests fonctionnels (63 tests, doit être 63/63)
./clean.sh             # nettoie build/
```

Le compilateur est cherché via `PBCOMPILER`, `C:\Program Files\PureBasic\Compilers\pbcompiler.exe`,
`C:\PureBasic\Compilers\pbcompiler.exe`, puis le `PATH`.

## Règles à respecter impérativement

1. **`EnableExplicit` est activé** : toute variable doit être déclarée.
2. **Ne jamais utiliser `Input()`** : lire stdin via `ReadStdinLine()`
   (couche bufferisée fiable en mode pipe) ; écrire via `SendRawLine()`.
3. Sélection OS par `CompilerIf #PB_Compiler_OS = #PB_OS_Windows` /
   `CompilerElse` — le code compile sur les 3 plateformes.
4. Commentaires et messages d'erreur en **français**, style du fichier.
5. **Architecture** : tout serveur s'appuie sur `mcp_common/` (inclure dans
   l'ordre `stdio.pbi`, `logging.pbi`, `json_helpers.pbi`, `protocol.pbi`,
   `jsonrpc.pbi`), renseigne les hooks `*G_ToolHandler` / `*G_CatalogBuilder`,
   puis appelle `MCPMainLoop()`. Modèle : `examples/minimal_server.pb`.
   Ne jamais réintroduire de code stdio/JSON-RPC dupliqué dans un serveur.
6. Tout nouvel outil MCP doit :
   - être ajouté dans `BuildToolsCatalog()` (nom, description, schéma) ;
   - avoir son `Case` dans le dispatch `ToolDispatch` ;
   - (fileMCP) passer par `ValiderChemin()` (confinement à `MCP_ROOT`) ;
   - commencer ses messages d'échec par `Erreur` / `ERREUR` / `Impossible` /
     `Echec` ou contenir `introuvable` / `refusee` / `depasse` pour que
     `isError` soit positionné (heuristique `DetectIsError`) ;
   - être couvert par un test dans `tests/test_mcp.py`.
7. Ne jamais élargir le périmètre de sécurité sans demande explicite
   (suppression récursive, fichiers binaires, transport réseau…).
8. Les exécutables vont dans `build/` (gitignoré) — ne jamais committer de
   binaire. Logs uniquement sur **stderr** (`LogDebug`/`LogError`).
9. **Avant chaque commit** : `run_all.bat` / `./run_all.sh` doit être vert
   (4 étapes : compilation, tests unitaires, tests d'intégration).

## Protocole MCP (rappel)

- Requête : `{"jsonrpc":"2.0","id":N,"method":"tools/call","params":{"name":"...","arguments":{...}}}`
- Réponse outil : `result.content[0].text` + `result.isError`.
- `tools/list` retourne le catalogue ; `notifications/initialized` est ignoré ;
  EOF sur stdin = arrêt propre du serveur.
- Variables d'environnement : `MCP_ROOT` (racine autorisée), `MCP_ROOT_SECRET`
  (secret de `change_root`).

## Structure

```
mcp_common/                       modules partages (stdio, logging, json_helpers, protocol, jsonrpc)
src/fileMCP.pb                    gestion de fichiers
src/MCP-Fetch-PB.pb               fetch web
src/MCP-SequentialThinking-PB.pb  raisonnement sequentiel
src/memoryMCP.pb + memory_core.pbi  memoire SQLite
src/dbMCP.pb + db_core.pbi        exploration SQL (sqlite + postgres)
src/context7MCP.pb + context7_core.pbi  documentation Context7
src/*.pbi                         fichiers projet IDE PureBasic (fileMCP)
examples/minimal_server.pb        serveur MCP minimal de demo
build.bat/build.sh                compilation des 6 serveurs ; clean.* : nettoyage
run_all.bat/run_all.sh            compilation + tests unitaires + integration + rapport
tests/mcp_client.py               harnais de test externe (client MCP Python)
tests/test_mcp.py                 tests d'integration des 5 serveurs (56 tests)
tests/test_database.pb           tests unitaires Database (37 tests)
tests/test_context7.pb           tests unitaires Context7 (19 tests)
tests/unit_test.pbi + test_common.pb  framework + tests unitaires (24 tests)
tests/test_memory.pb              tests unitaires Memory (33 tests)
```

Voir aussi : [README.md](README.md), [CONTRIBUTING.md](CONTRIBUTING.md),
[ROADMAP.md](ROADMAP.md), [ERRATA.md](ERRATA.md), [SECURITY.md](SECURITY.md).
