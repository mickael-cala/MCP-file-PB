# AGENTS.md — Instructions pour les agents IA

Ce fichier guide les agents de codage (Claude Code, Kimi Code, Copilot…)
qui travaillent sur ce dépôt.

## Vue d'ensemble

Serveur MCP de gestion de fichiers écrit en **PureBasic**, un seul fichier
source : `src/fileMCP.pb` (~850 lignes). Transport **JSON-RPC 2.0 sur
stdin/stdout**, une ligne JSON par message. Exécutable **console**, 100 %
natif, multi-OS (Windows / Linux / macOS). Pas de dépendance externe.

## Commandes essentielles

```bash
build.bat              # Windows : compile -> build\fileMCP.exe
./build.sh             # Linux/macOS : compile -> build/fileMCP
python tests/test_mcp.py   # tests fonctionnels (17 tests, doit être 17/17)
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
5. Tout nouvel outil MCP doit :
   - être ajouté dans `BuildToolsCatalog()` (nom, description, schéma) ;
   - avoir son `Case` dans le dispatch `tools/call` ;
   - passer par `ValiderChemin()` (confinement à `MCP_ROOT`) ;
   - commencer ses messages d'échec par `Erreur` / `Impossible` / `Echec` /
     `introuvable` / `refusee` / `depasse` pour que `isError` soit positionné ;
   - être couvert par un test dans `tests/test_mcp.py`.
6. Ne jamais élargir le périmètre de sécurité sans demande explicite
   (suppression récursive, fichiers binaires, transport réseau…).
7. Les exécutables vont dans `build/` (gitignoré) — ne jamais committer de
   binaire.

## Protocole MCP (rappel)

- Requête : `{"jsonrpc":"2.0","id":N,"method":"tools/call","params":{"name":"...","arguments":{...}}}`
- Réponse outil : `result.content[0].text` + `result.isError`.
- `tools/list` retourne le catalogue ; `notifications/initialized` est ignoré ;
  EOF sur stdin = arrêt propre du serveur.
- Variables d'environnement : `MCP_ROOT` (racine autorisée), `MCP_ROOT_SECRET`
  (secret de `change_root`).

## Structure

```
src/fileMCP.pb       source unique (multi-OS)
src/*.pbi            fichiers projet IDE PureBasic par OS
build.bat/build.sh   compilation ; clean.bat/clean.sh : nettoyage
tests/test_mcp.py    harnais de tests stdio
```

Voir aussi : [README.md](README.md), [CONTRIBUTING.md](CONTRIBUTING.md),
[ROADMAP.md](ROADMAP.md), [ERRATA.md](ERRATA.md), [SECURITY.md](SECURITY.md).
