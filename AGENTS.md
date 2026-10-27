# AGENTS.md — Instructions pour les agents IA

Ce fichier guide les agents de codage (Kimi Code, Claude Code, Copilot…) qui
travaillent sur ce dépôt. **À lire en premier à chaque reprise.**

## Reprise du développement (bootstrap)

1. **Lire l'état du plan** : [PLAN.md](PLAN.md) (phases 0→6, statut et
   livrables) et [ROADMAP.md](ROADMAP.md) (suite).
2. **Vérifier l'environnement** :
   - PureBasic 6.x (testé avec 6.41) — `pbcompiler` cherché via `PBCOMPILER`,
     `C:\Program Files\PureBasic\Compilers\pbcompiler.exe`,
     `C:\PureBasic\Compilers\pbcompiler.exe`, puis le `PATH` ;
   - Python 3 (tests d'intégration uniquement, aucune dépendance externe) ;
   - `git` dans le PATH (serveur `gitMCP` et workflow de commit) ;
   - Linux : `libssl-dev`, `libsqlite3-dev`, `curl` ; macOS : `curl`.
3. **Synchroniser et vérifier la base** :
   ```bash
   git pull
   build.bat                  # ou ./build.sh : compile les 8 serveurs
   run_all.bat                # ou ./run_all.sh : unitaires + intégration + rapport
   ```
   Attendu : **10/10 étapes**, **200 tests unitaires** (42+33+42+19+24+40),
   **17/17 robustesse/performance** et **122/122 tests d'intégration**. Si ce n'est pas le cas, corriger avant
   toute nouvelle fonctionnalité.
4. **Choisir la suite** : voir [ROADMAP.md](ROADMAP.md). Ne jamais démarrer
   une phase sans avoir vert `run_all`.

### Validation Linux (WSL2)

```bash
# dans WSL : installer les dependances
sudo apt install -y libssl-dev libsqlite3-dev curl
# pointer PBCOMPILER vers le compilateur Linux (licence ou demo)
export PBCOMPILER=$HOME/purebasic-demo/purebasic_demo/compilers/pbcompiler
export PUREBASIC_HOME=$HOME/purebasic-demo/purebasic_demo
./build.sh && ./run_all.sh
```
Attendu : 10/10 étapes (200 unitaires, 17 robustesse/perf, 122 intégration).
Attention : `build/` est partagé avec Windows si le dépôt est sur `/mnt/c` —
relancer `build.bat` après une validation Linux.

## Règle absolue : documentation synchronisée AVANT chaque commit

Aucun commit ne doit partir sans que **tous les fichiers `.md` concernés**
soient à jour. Avant `git commit`, passer cette checklist :

| Fichier | À mettre à jour quand… |
|---|---|
| `README.md` | nouvel outil, nouvelle variable d'environnement, changement de build/tests, nouveau serveur, compteurs de tests |
| `PLAN.md` | début/fin de phase, changement de statut, nouvel écart au plan |
| `CHANGELOG.md` | **tout changement notable** (ajout/correction/sécurité) sous `## [Non publié]` avec le détail des fichiers |
| `ROADMAP.md` | ce qui est terminé et ce qui devient prioritaire |
| `ERRATA.md` | limitation, bug connu, résultat des tests de référence |
| `AGENTS.md` | changement d'architecture, de commandes, de conventions, de pièges |
| `CONTRIBUTING.md` | conventions, workflow de tests, périmètre des contributions |
| `SECURITY.md` | nouvelle surface d'attaque, nouveau secret, nouvelle protection |
| `docs`/`.github/*.md` | modèles d'issues/PR, compteurs cités |

Règle de cohérence : **tous les compteurs cités** (nombre de serveurs, de
tests, d'étapes) doivent correspondre à la réalité du moment. Vérifier avec :

```bash
grep -rnE "[0-9]+ tests|[0-9]+ serveurs|/9 étapes" README.md PLAN.md ERRATA.md AGENTS.md CONTRIBUTING.md
```

Les chiffres historiques du `CHANGELOG.md` sont la seule exception : ils
décrivent chaque version à sa date et ne se réécrivent pas.

## Workflow de commit

```bash
run_all.bat                    # obligatoire, doit être vert
git add -A
git commit -m "Phase N: resume court

- points cles du changement
- tests: X/Y, run_all N/N"
git push                       # uniquement si l'utilisateur le demande
```

- Un commit = un sujet cohérent (une phase ou une correction).
- **Ne jamais pousser sans demande explicite** de l'utilisateur.
- Ne jamais committer `build/`, `tests/report.html`, `tmp-test/` (gitignorés).

## Vue d'ensemble

**8 serveurs MCP** écrits en **PureBasic** (sources dans `src/`) :

- `fileMCP.pb` — gestion de fichiers confinée (`MCP_ROOT`/`MCP_ROOT_SECRET`)
- `MCP-Fetch-PB.pb` — fetch web (HTML → Markdown, protection SSRF)
- `MCP-SequentialThinking-PB.pb` — raisonnement séquentiel
- `memoryMCP.pb` + `memory_core.pbi` — mémoire SQLite (`MCP_MEMORY_DB`)
- `dbMCP.pb` + `db_core.pbi` — exploration SQL (SQLite + PostgreSQL optionnel, lecture seule par défaut)
- `context7MCP.pb` + `context7_core.pbi` — documentation Context7 (`MCP_CONTEXT7_API_KEY`)
- `gitMCP.pb` + `git_core.pbi` — exploration de dépôts git locaux (sous-processus git)
- `githubMCP.pb` + `github_core.pbi` — API REST GitHub (`MCP_GITHUB_TOKEN`, mock pour les tests)

Transport **JSON-RPC 2.0 sur stdin/stdout**, une ligne JSON par message.
Exécutables **console**, 100 % natifs, multi-OS (Windows / Linux / macOS).
Le cœur métier d'un serveur va dans `src/<serveur>_core.pbi` (testable), le
`.pb` ne contient que le `main` (lecture d'env + hooks + `MCPMainLoop()`).

## Commandes essentielles

```bash
build.bat              # Windows : compile les 8 serveurs -> build\*.exe
./build.sh             # Linux/macOS : compile les 8 serveurs -> build/
run_all.bat            # compilation + 6 suites unitaires + robustesse/perf + intégration + report.html
./run_all.sh           # idem sous Linux/macOS
python tests/test_mcp.py [serveur]   # intégration seule (122 tests)
./clean.sh             # nettoie build/
```

## Architecture (mcp_common/)

Ordre d'inclusion dans un serveur :

```purebasic
IncludeFile "../mcp_common/stdio.pbi"        ; E/S stdio, stderr, CheckStdio
IncludeFile "../mcp_common/logging.pbi"      ; LogDebug / LogError (stderr)
IncludeFile "../mcp_common/json_helpers.pbi" ; GetArg*, AddProp*, ToolDef, ToolOk/ToolFail
IncludeFile "../mcp_common/http.pbi"         ; HttpGetHeaders / HttpPostHeaders (API web)
IncludeFile "../mcp_common/net_guard.pbi"    ; anti-SSRF (serveurs qui fetchent une URL)
IncludeFile "../mcp_common/protocol.pbi"     ; identité + initialize
IncludeFile "../mcp_common/jsonrpc.pbi"      ; noyau JSON-RPC + MCPMainLoop
```

Puis : renseigner `G_ServerName`/`G_ServerVersion`, affecter
`*G_ToolHandler` et `*G_CatalogBuilder`, vérifier `CheckStdio()`, appeler
`MCPMainLoop()`. Modèle complet : `examples/minimal_server.pb`.

## Règles à respecter impérativement

1. **`EnableExplicit`** : toute variable doit être déclarée.
2. **Ne jamais utiliser `Input()`** : `ReadStdinLine()` / `SendRawLine()`
   (fiables en mode pipe). Logs uniquement sur **stderr**.
3. Sélection OS par `CompilerIf #PB_Compiler_OS = #PB_OS_Windows` /
   `CompilerElse` — le code doit compiler sur les 3 plateformes.
4. **`isError` explicite** : tout retour d'erreur d'un outil passe par
   `ToolFail(...)`, tout payload de données (JSON, listing, contenu) par
   `ToolOk(...)`. L'heuristique `DetectIsError` n'est qu'un filet de sécurité
   sur la première ligne ; elle ne doit jamais voir un payload.
5. **Anti-SSRF** : toute URL distante passe par `NetGuardValidateUrl()`
   (résolution de **toutes** les adresses) ; les redirections sont suivies
   manuellement, bornées et revalidées.
6. Commentaires et messages d'erreur en **français**, style du fichier.
7. Aucune duplication de code stdio/JSON-RPC/HTTP dans un serveur : tout va
   dans `mcp_common/`.
8. Tout nouvel outil MCP doit :
   - être ajouté au catalogue (`BuildToolsCatalog` / `XxxBuildCatalog`) ;
   - avoir son `Case` dans le dispatch ;
   - assainir ses entrées (chemins, refs, segments d'URL) avant usage ;
   - retourner ses **erreurs** via `ToolFail(...)` et ses **payloads** via
     `ToolOk(...)` (l'heuristique `DetectIsError` n'est qu'un filet) ;
   - être couvert par un test unitaire (`tests/test_<serveur>.pb`) et/ou
     d'intégration (`tests/test_mcp.py`).
9. Protections obligatoires : confinement `MCP_ROOT` (fileMCP), écritures SQL
   derrière `MCP_DB_ALLOW_WRITE`, écritures GitHub derrière `confirm=true`,
   validation anti-injection (`GitSafeParam`, `GhSafeSegment`), validation
   réseau `NetGuardValidateUrl()` (fetch).
10. Ne jamais élargir le périmètre de sécurité sans demande explicite.
11. Les exécutables vont dans `build/` (gitignoré) — jamais de binaire commité.

## Pièges PureBasic rencontrés (ne pas les réintroduire)

- **Mots réservés** : `Args`, `To`, `Result`, `Read` ne peuvent pas être des
  noms de variables/paramètres. Renommer (`GitArgs`, `Dest`, `R`, `BytesRead`).
- **`ReadString()` s'arrête à la fin de ligne** : même avec une longueur
  explicite (`ReadString(f, #PB_UTF8, Lof(f))`), il faut **plusieurs** lignes ?
  Non : une seule ligne est lue. Pour lire un fichier entier, passer par
  `ReadData` + `PeekS` (voir `HttpReadWholeFile()` dans `http.pbi`).
- **Paramètres structure** : passage **par pointeur uniquement** —
  `Procedure Foo(*P.MaStructure)` + appel `Foo(@MaVar)`. `Procedure Foo(P.MaStructure)`
  est une erreur de syntaxe.
- **Piège `Protected Status.Integer`** : `Integer` est une *structure* ;
  l'utiliser comme scalaire (`Str(Status)`, comparaisons) donne l'adresse de la
  structure. Déclarer `Status.i` et passer `@Status` au pointeur typé
  `*Status.Integer`.
- **Curseur `ForEach`** : un `ForEach` imbriqué déplace le curseur du `ForEach`
  externe → boucle infinie. Utiliser une map de membership ou un index.
- **`Trim()` PureBasic** ne retire pas `#CR$`/`#LF$` (seulement espaces/tabs) :
  utiliser `TrimOut()` (git_core) ou `ReplaceString`.
- **Chaînes JSON en PureBasic** : `~"{\"cle\":\"valeur\"}"` (préfixe `~`) ;
  un `\"` dans une chaîne normale est une erreur de compilation.
- **`OpenDatabase`** (SQLite) exige un fichier existant : créer le fichier vide
  avant ouverture.
- **PRAGMA / EXPLAIN** : colonnes sans type déclaré ; utiliser
  `CheckDatabaseNull` pour distinguer un vrai NULL.
- **Sous-processus (RunProgram)** : `ReadProgramString` doit être lu dans une
  boucle jusqu'à `ProgramRunning() = 0` (sinon sortie vide). stderr n'est pas
  lisible de façon fiable → passer par le shell avec `2>&1`
  (`cmd.exe /c ""exe" args 2>&1"`) après validation stricte des entrées.
- **HTTP avec en-têtes** : WinHTTP sous Windows ; sous Linux/macOS, le HTTP
  intégré n'offre pas d'en-têtes → `mcp_common/http.pbi` passe par **curl**
  (fichier de configuration, pas de quoting shell).
- **RunProgram sous Linux** ne gère pas les guillemets dans les arguments :
  écrire un script temporaire (`git_core.pbi` le fait) ou passer par curl -K.
- **Multi-moteurs Database** : un seul `Use*Database()` par processus de
  fiable. `UsePostgreSQLDatabase()` doit etre appele au CHARGEMENT de dbMCP
  (et non dans une procedure apres une ouverture SQLite) ; sinon
  `OpenDatabase` PG echoue silencieusement (handle 0, erreur vide).
  `DbOpenSQLite` rapelle `UseSQLiteDatabase()` avant son open : le dernier
  Use* defini le driver actif.
- **Fins de ligne** : `.gitattributes` impose LF aux `.sh/.py/.pb/.pbi/.md`
  (un shebang en CRLF casse l'exécution sous WSL) ; `.bat` en CRLF.
- **IDE/projets** : `.pbi` = module d'inclusion ; un projet IDE est un `.pbp`
  (non fourni, voir README). Ne pas inventer de format de projet.

## Protocole MCP (rappel)

- Requête : `{"jsonrpc":"2.0","id":N,"method":"tools/call","params":{"name":"...","arguments":{...}}}`
- Réponse outil : `result.content[0].text` + `result.isError`.
- `tools/list` retourne le catalogue ; **toute notification (requête sans
  `id`) est ignorée sans réponse** ; EOF sur stdin = arrêt propre du serveur.
- Codes d'erreur normalisés : `-32601` méthode inconnue, `-32602` paramètres
  invalides (`tools/call` sans nom d'outil).
- Variables d'environnement par serveur : voir README et SECURITY.md.

## Structure

```
mcp_common/                       modules partages (stdio, logging, json_helpers, http, protocol, jsonrpc)
src/fileMCP.pb                    gestion de fichiers
src/MCP-Fetch-PB.pb               fetch web
src/MCP-SequentialThinking-PB.pb  raisonnement sequentiel
src/memoryMCP.pb + memory_core.pbi      memoire SQLite
src/dbMCP.pb + db_core.pbi              exploration SQL (sqlite + postgres)
src/context7MCP.pb + context7_core.pbi  documentation Context7
src/gitMCP.pb + git_core.pbi            exploration git locale
src/githubMCP.pb + github_core.pbi      API REST GitHub
examples/minimal_server.pb        serveur MCP minimal de demo
examples/mcp.json                 configuration client complete (8 serveurs)
.gitattributes                    fins de ligne (LF scripts/sources, CRLF .bat)
build.bat/build.sh                compilation des 8 serveurs ; clean.* : nettoyage
run_all.bat/run_all.sh            compilation + tests unitaires + integration + rapport
tests/mcp_client.py               harnais de test externe (client MCP Python)
tests/mock_github.py              mock local de l'API GitHub
tests/test_mcp.py                 tests d'integration des 8 serveurs (122 tests)
tests/unit_test.pbi               framework de tests unitaires PureBasic
tests/test_common.pb              tests unitaires mcp_common (24 tests)
tests/test_memory.pb              tests unitaires Memory (33 tests)
tests/test_database.pb            tests unitaires Database (37 tests)
tests/test_context7.pb            tests unitaires Context7 (19 tests)
tests/test_git.pb                 tests unitaires Git (24 tests)
tests/test_github.pb              tests unitaires GitHub (40 tests)
tests/test_robustness.py          robustesse T6.1-T6.8 + perf T6.9-T6.14
tests/make_report.py              rapport HTML depuis report.json
```

Voir aussi : [PLAN.md](PLAN.md), [README.md](README.md),
[CONTRIBUTING.md](CONTRIBUTING.md), [ROADMAP.md](ROADMAP.md),
[ERRATA.md](ERRATA.md), [SECURITY.md](SECURITY.md).
