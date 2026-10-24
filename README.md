# MCP-servers-PB — Serveurs MCP en PureBasic

Trois serveurs [MCP](https://modelcontextprotocol.io) (Model Context Protocol) écrits en **PureBasic**, 100 % natifs, qui exposent des outils à un client IA (Claude Desktop, Kimi Code, etc.) via **JSON-RPC 2.0 sur stdin/stdout** :

| Serveur | Source | Outil(s) | Description |
|---|---|---|---|
| **fileMCP** | `src/fileMCP.pb` | 10 outils | Gestion de fichiers confinée à une racine (`MCP_ROOT`) |
| **MCP-Fetch-PB** | `src/MCP-Fetch-PB.pb` | `fetch` | Récupération de pages web, conversion HTML → Markdown |
| **MCP-SequentialThinking-PB** | `src/MCP-SequentialThinking-PB.pb` | `sequential_thinking` | Raisonnement séquentiel structuré (étapes, révisions, branches) |
| **memoryMCP** | `src/memoryMCP.pb` + `src/memory_core.pbi` | 9 outils | Graphe d'entites persistant en SQLite (`MCP_MEMORY_DB`) : entites, observations, relations |
| **dbMCP** | `src/dbMCP.pb` + `src/db_core.pbi` | 5 outils | Exploration SQL en lecture seule : SQLite (`MCP_DB_PATH`) + PostgreSQL optionnel (`MCP_DB_POSTGRES_DSN`) |
| **context7MCP** | `src/context7MCP.pb` + `src/context7_core.pbi` | 2 outils | Résolution de bibliothèques et documentation via l'API [Context7](https://context7.com) |
| **gitMCP** | `src/gitMCP.pb` + `src/git_core.pbi` | 7 outils | Exploration de dépôts git locaux (status, log, diff, show, branches, blame) |
| **githubMCP** | `src/githubMCP.pb` + `src/github_core.pbi` | 10 outils | API REST GitHub : repos, issues, pull requests, commits, recherches |

Caractéristiques communes :

- **Multi-plateforme** : Windows, Linux, macOS (sélection E/S stdio par directives `CompilerIf`).
- **Transport stdio** : chaque message JSON-RPC est émis sur une seule ligne, délimité par `\n`.
- **Zéro dépendance** : compilables avec PureBasic seul, aucune DLL/API externe.

## Outils MCP exposés

### fileMCP — gestion de fichiers

| Outil | Description | Paramètres |
|---|---|---|
| `list_files` | Lister le contenu d'un répertoire (confiné à la racine autorisée) | `path` |
| `read_file` | Lire un fichier texte (tronqué au-delà de 20 000 octets) | `path` |
| `read_file_lines` | Lire une plage de lignes (fichier limité à 5 Mo) | `path`, `startLine` (défaut 1), `maxLines` (défaut 50) |
| `write_file` | Écrire/créer un fichier texte | `path`, `content` |
| `create_directory` | Créer un répertoire | `path` |
| `delete_file` | Supprimer un fichier ou dossier vide ⚠️ | `path` |
| `move_file` | Déplacer ou renommer un fichier ⚠️ | `oldPath`, `newPath` |
| `get_file_info` | Infos détaillées fichier/dossier | `path` |
| `search_files` | Rechercher du texte (récursif) | `path`, `pattern` |
| `change_root` | Changer la zone autorisée ⚠️ | `newRoot`, `secret` |

### MCP-Fetch-PB — récupération web

| Outil | Description | Paramètres |
|---|---|---|
| `fetch` | Récupère une URL et retourne son contenu en Markdown (ou HTML brut si `raw=true`) | `url`, `max_length` (défaut 5000), `start_index` (défaut 0), `raw` (défaut false) |

Les URLs non HTTP/HTTPS et les IPs littérales sont refusées (SSRF) ; un timeout plafonne la durée de chaque requête.

### MCP-SequentialThinking-PB — raisonnement séquentiel

| Outil | Description | Paramètres |
|---|---|---|
| `sequential_thinking` | Enregistre une étape de raisonnement et retourne l'état courant (numéro, total, historique, branches) | `thought`, `thoughtNumber`, `totalThoughts`, `nextThoughtNeeded`, `isRevision` (défaut false), `revisesThought` (défaut 0), `branchFromThought` (défaut 0), `branchId` |

### memoryMCP — mémoire persistante (SQLite)

| Outil | Description | Paramètres |
|---|---|---|
| `create_entities` | Crée des entités avec leurs observations (doublons ignorés) | `entities[]` : `{name, entityType, observations[]}` |
| `create_relations` | Crée des relations entre entités existantes | `relations[]` : `{from, to, relationType}` |
| `add_observations` | Ajoute des observations à des entités existantes | `observations[]` : `{entityName, contents[]}` |
| `delete_entities` | Supprime des entités (cascade observations + relations) | `entityNames[]` |
| `delete_observations` | Supprime des observations précises | `observations[]` : `{entityName, contents[]}` |
| `delete_relations` | Supprime des relations précises | `relations[]` : `{from, to, relationType}` |
| `read_graph` | Retourne tout le graphe en JSON | — |
| `search_nodes` | Recherche insensible à la casse (nom, type, observations) | `query` |
| `open_nodes` | Retourne des entités par nom avec relations internes | `names[]` |

La base est un fichier SQLite créé automatiquement (chemin : `MCP_MEMORY_DB`, défaut `memory.db`). Les noms sont échappés (pas d'injection SQL) et les suppressions d'entités cascadent via les clés étrangères.

### dbMCP — exploration SQL (SQLite + PostgreSQL)

| Outil | Description | Paramètres |
|---|---|---|
| `db_list_schemas` | Liste les schémas (`["main"]` pour SQLite, `information_schema.schemata` pour PostgreSQL) | `engine` (défaut `sqlite`) |
| `db_list_tables` | Liste les tables de la base / du schéma | `engine`, `schema` (PostgreSQL, défaut `public`) |
| `db_describe_table` | Décrit les colonnes (`PRAGMA table_info` / `information_schema.columns`) | `table`, `engine`, `schema` |
| `db_execute_query` | Exécute une requête — **lecture seule par défaut**, résultat JSON limité à 1000 lignes | `query`, `engine` |
| `db_explain` | Plan d'exécution (`EXPLAIN QUERY PLAN` / `EXPLAIN`) | `query`, `engine` |

Garde-fou lecture seule : seuls `SELECT`/`WITH` (sans verbe d'écriture)/`SHOW`/`EXPLAIN`/`DESCRIBE` passent ; toute écriture exige `MCP_DB_ALLOW_WRITE=1` et est journalisée sur stderr en cas de refus. La connexion PostgreSQL impose `statement_timeout=30s`. Les résultats JSON préservent les NULL (`CheckDatabaseNull`) et typent entiers/flottants.

### context7MCP — documentation de bibliothèques (Context7)

| Outil | Description | Paramètres |
|---|---|---|
| `resolve_library_id` | Recherche une bibliothèque, retourne les identifiants `/owner/repo` (fonctionne sans clé) | `query`, `libraryType` (défaut `oss`) |
| `query_docs` | Retourne la documentation d'une bibliothèque (**clé API requise** : `MCP_CONTEXT7_API_KEY`, préfixe `ctx7sk`) | `libraryId`, `query`, `tokens` (défaut 5000), `topic` (optionnel), `max_length` (troncature locale, défaut 10000) |

HTTP : couche WinHTTP native sous Windows (en-têtes `Authorization` supportées) ; HTTP intégré PureBasic sous Linux/macOS (clé non supportée → message explicite). Erreurs mappées proprement : 401 clé, 429 quota, 5xx indisponible, échec réseau. Les tests live sont ignorés hors ligne.

### gitMCP — dépôts git locaux

| Outil | Description | Paramètres |
|---|---|---|
| `git_is_repo` | Vérifie qu'un répertoire est un dépôt git | `repoPath` |
| `git_status` | État du working tree (format porcelain) | `repoPath` |
| `git_log` | Historique oneline (N derniers commits) | `repoPath`, `count` (défaut 10, max 1000) |
| `git_diff` | Différences entre deux refs, filtre de chemin optionnel | `repoPath`, `refA`, `refB`, `path` |
| `git_show` | Contenu d'un fichier à une ref | `repoPath`, `ref`, `path` |
| `git_branches` | Branches locales ou distantes | `repoPath`, `remote` |
| `git_blame` | Annotations de lignes | `repoPath`, `path`, `startLine`, `endLine` |

Sécurité : tous les paramètres (chemins, refs) sont validés avant exécution — les métacaractères shell (`;` `&` `|` `<` `>` `` ` `` `$` `(` `)` guillemets, retours ligne) sont rejetés. `MCP_GIT_EXE` permet de pointer un `git.exe` hors PATH ; le serveur refuse de démarrer si git est introuvable.

### githubMCP — API REST GitHub

| Outil | Description | Paramètres |
|---|---|---|
| `gh_get_repo` | Métadonnées d'un dépôt | `owner`, `repo` |
| `gh_list_issues` | Liste paginée des issues | `owner`, `repo`, `state`, `page`, `per_page` |
| `gh_get_issue` | Détail d'une issue | `owner`, `repo`, `number` |
| `gh_create_issue` | Crée une issue — **`confirm=true` requis** | `owner`, `repo`, `title`, `body`, `confirm` |
| `gh_list_pull_requests` | Liste paginée des PR | `owner`, `repo`, `state`, `page`, `per_page` |
| `gh_get_pull_request` | Détail d'une PR | `owner`, `repo`, `number` |
| `gh_create_pull_request` | Crée une PR — **`confirm=true` requis** | `owner`, `repo`, `title`, `head`, `base`, `body`, `confirm` |
| `gh_list_commits` | Commits paginés (filtre `sha`) | `owner`, `repo`, `sha`, `page`, `per_page` |
| `gh_search_code` | Recherche de code | `query`, `page`, `per_page` |
| `gh_search_repositories` | Recherche de dépôts | `query`, `page`, `per_page` |

Sécurité : token jamais renvoyé dans les messages ; écritures refusées sans `confirm=true` ; pagination bornée (`per_page` max 100) ; erreurs mappées (401 token, 403 quota, 404 introuvable, 422 validation, 5xx). Les tests d'intégration utilisent un **serveur GitHub mock local** (`tests/mock_github.py`), sans réseau.

⚠️ **Attention** : `write_file`, `delete_file`, `move_file` et `change_root` sont des opérations destructrices ou sensibles. Ne connectez ce serveur qu'à un répertoire dont la perte de contenu serait acceptable.

## Sécurité

| Variable d'environnement | Rôle | Serveur |
|---|---|---|
| `MCP_ROOT` | Répertoire racine autorisé pour toutes les opérations. Si absent, le répertoire courant du serveur est utilisé. | fileMCP |
| `MCP_ROOT_SECRET` | Mot de passe requis par l'outil `change_root` pour modifier la racine autorisée à chaud. | fileMCP |
| `MCP_MEMORY_DB` | Chemin du fichier SQLite de la mémoire (créé automatiquement si absent). Défaut : `memory.db`. | memoryMCP |
| `MCP_DB_PATH` | Fichier SQLite exploré par dbMCP (créé si absent). Défaut : `database.db`. | dbMCP |
| `MCP_DB_POSTGRES_DSN` | Chaîne de connexion PostgreSQL (ex. `host=localhost dbname=test`). Si absente, l'engine `postgres` retourne une erreur claire. | dbMCP |
| `MCP_DB_ALLOW_WRITE` | `1` = autorise les requêtes d'écriture (INSERT/UPDATE/DELETE/DDL). Défaut : lecture seule. | dbMCP |
| `MCP_CONTEXT7_API_KEY` | Clé API Context7 (préfixe `ctx7sk`, https://context7.com). Requise par `query_docs` ; `resolve_library_id` fonctionne sans. | context7MCP |
| `MCP_GIT_EXE` | Chemin de l'exécutable git si absent du PATH. | gitMCP |
| `MCP_GITHUB_TOKEN` | Token GitHub (PAT). Requis par tous les outils githubMCP. | githubMCP |
| `MCP_GITHUB_API_BASE` | Base de l'API (défaut `https://api.github.com`) ; sert aux tests avec un mock. | githubMCP |

Tous les chemins passés aux outils fileMCP sont normalisés et bloqués s'ils tentent de sortir de la racine autorisée. Voir [SECURITY.md](SECURITY.md).

## Compilation

Requiert [PureBasic](https://www.purebasic.com) et un format d'exécutable **Console**.

### Avec les scripts de build (recommandé)

```bash
build.bat      # Windows   -> genere build\fileMCP.exe, build\MCP-Fetch-PB.exe, build\MCP-SequentialThinking-PB.exe
./build.sh     # Linux/macOS -> memes noms sans extension
```

Les scripts compilent les 8 serveurs. Le compilateur est cherché dans la variable d'environnement `PBCOMPILER`, puis dans les chemins par défaut (`C:\Program Files\PureBasic\Compilers`, `C:\PureBasic\Compilers`), puis dans le `PATH`. Les exécutables sont générés dans `build/` (non versionné).

Pour nettoyer : `clean.bat` / `./clean.sh`.

### Via l'IDE PureBasic

Ouvrez le `.pb` du serveur voulu (ex. `src/fileMCP.pb`), puis :

1. **Options du compilateur** → Format d'exécutable : **Console**
2. Nom de l'exécutable : `build/<nom>.exe` (ou ce que vous préférez)
3. **Compilation → Compiler** (`F5`)

Aucun fichier `.pbp` n'est fourni : les scripts `build.bat`/`build.sh` couvrent la compilation reproductible (mêmes options), et l'IDE fait foi pour les options. Les fichiers `.pbi` du dépôt sont uniquement les **modules d'inclusion** (`mcp_common/`, `tests/unit_test.pbi`), pas des projets.

Les exécutables compilés ne sont pas versionnés : publiez-les via [GitHub Releases](https://docs.github.com/fr/repositories/releasing-projects-on-github) si besoin.

## Tests

Trois niveaux de tests, lances d'un coup par `run_all.bat` / `./run_all.sh`
(compilation + tests unitaires + robustesse/performance + intégration +
`tests/report.html` avec le détail par serveur) :

```bash
run_all.bat        # ou ./run_all.sh : tout verifier
```

- **Unitaires (PureBasic)** : `tests/unit_test.pbi` (micro-framework) +
  `tests/test_common.pb` (24 tests sur `mcp_common/`) et
  `tests/test_memory.pb` (33 tests sur le serveur Memory). Chaque futur module
  ajoute un `tests/test_<module>.pb`.
- **Integration (Python)** : `tests/mcp_client.py` (harnais client MCP avec
  validation de conformite JSON-RPC 2.0) + `tests/test_mcp.py` (100 tests qui
  exercent les outils et les cas de securite de chaque serveur) :

```bash
python tests/test_mcp.py                          # les 8 serveurs
python tests/test_mcp.py memoryMCP                  # un seul serveur
```

100 tests au total (PostgreSQL conditionnel, Context7 live hors ligne).

- **Robustesse et performances (Phase 6)** : `tests/test_robustness.py` —
  17 vérifications (charge stdio, JSON 1 Mo, JSON malformé, EOF brutal,
  kill pendant une requête, DB partagée/invalide, coupure réseau, cibles de
  performance T6.9–T6.14) :

```bash
python tests/test_robustness.py
MCP_STRESS_REQUESTS=10000 python tests/test_robustness.py   # charge complète
```

Le binaire de chaque serveur est cherché dans `build/`, puis `src/` ; la variable `<NOM>_BIN` (ex. `FILEMCP_BIN`, `MEMORYMCP_BIN`) force un chemin.

## Configuration d'un client MCP

Exemple générique (les trois serveurs) :

```json
{
  "mcpServers": {
    "file-pb": {
      "command": "/chemin/vers/build/fileMCP",
      "env": {
        "MCP_ROOT": "/chemin/vers/la/zone/autorisee",
        "MCP_ROOT_SECRET": "mot-de-passe-fort"
      }
    },
    "fetch-pb": {
      "command": "/chemin/vers/build/MCP-Fetch-PB"
    },
    "sequential-thinking-pb": {
      "command": "/chemin/vers/build/MCP-SequentialThinking-PB"
    },
    "memory-pb": {
      "command": "/chemin/vers/build/memoryMCP",
      "env": {
        "MCP_MEMORY_DB": "/chemin/vers/memory.db"
      }
    },
    "db-pb": {
      "command": "/chemin/vers/build/dbMCP",
      "env": {
        "MCP_DB_PATH": "/chemin/vers/database.db"
      }
    },
    "git-pb": {
      "command": "/chemin/vers/build/gitMCP"
    },
    "github-pb": {
      "command": "/chemin/vers/build/githubMCP",
      "env": {
        "MCP_GITHUB_TOKEN": "ghp_..."
      }
    }
  }
}
```

Sous Windows, les commandes pointent vers les `.exe` de `build\`, par ex. `C:\\chemin\\vers\\build\\fileMCP.exe`.

Chaque serveur démarre, attend les requêtes JSON-RPC sur stdin, et se termine proprement à l'EOF de stdin.

## Structure du dépôt

```
mcp_common/               Modules partages par tous les serveurs MCP
├── stdio.pbi             Couche E/S stdio multi-OS (stdin bufferise, stdout/stderr)
├── logging.pbi           LogDebug/LogError sur stderr (jamais sur stdout)
├── json_helpers.pbi      Lecture d'arguments + construction de schemas d'outils
├── protocol.pbi          Identite serveur + reponse initialize
└── jsonrpc.pbi           Noyau JSON-RPC 2.0 generique (hooks + MCPMainLoop)

src/
├── fileMCP.pb                    # Serveur gestion de fichiers (multi-OS)
├── MCP-Fetch-PB.pb               # Serveur fetch web (HTML -> Markdown)
├── MCP-SequentialThinking-PB.pb  # Serveur raisonnement sequentiel
├── memoryMCP.pb                  # Serveur memoire (main)
├── memory_core.pbi               # Coeur metier Memory (SQLite, testable)
├── dbMCP.pb                      # Serveur Database (main)
├── db_core.pbi                   # Coeur metier Database (SQLite/PostgreSQL)
├── context7MCP.pb                # Serveur Context7 (main)
├── context7_core.pbi             # Coeur metier Context7 (WinHTTP/Linux)
├── gitMCP.pb                     # Serveur Git (main)
├── git_core.pbi                  # Coeur metier Git (sous-processus git)
├── githubMCP.pb                  # Serveur GitHub (main)
├── github_core.pbi               # Coeur metier GitHub (API REST)

examples/minimal_server.pb  # Serveur MCP minimal de demo (validation Phase 0)
examples/mcp.json           # Configuration client MCP complete (8 serveurs)
build.bat / build.sh        # Compilation des 8 serveurs (sortie dans build/)
clean.bat / clean.sh        # Suppression des artefacts de compilation
run_all.bat / run_all.sh    # Compilation + tests unitaires + integration + rapport
tests/
├── mcp_client.py           # Harnais de test externe (client MCP Python)
├── mock_github.py          # Mock local de l'API GitHub (integration)
├── test_mcp.py             # Tests fonctionnels des 8 serveurs (100 tests)
├── unit_test.pbi           # Micro-framework de tests unitaires PureBasic
├── test_common.pb          # Tests unitaires des modules mcp_common (24 tests)
├── test_memory.pb          # Tests unitaires du serveur Memory (33 tests)
├── test_database.pb        # Tests unitaires du serveur Database (37 tests)
├── test_context7.pb        # Tests unitaires du serveur Context7 (19 tests)
├── test_git.pb             # Tests unitaires du serveur Git (24 tests)
└── test_github.pb          # Tests unitaires du serveur GitHub (40 tests)
```

Nouveau serveur ? Incluez `mcp_common/` (voir `examples/minimal_server.pb`), renseignez les hooks `*G_ToolHandler` / `*G_CatalogBuilder` et appelez `MCPMainLoop()`.

## Documentation

- [PLAN.md](PLAN.md) — suivi des phases du plan (état, livrables)
- [CHANGELOG.md](CHANGELOG.md) — journal des versions
- [ROADMAP.md](ROADMAP.md) — feuille de route
- [ERRATA.md](ERRATA.md) — limitations et problèmes connus
- [CONTRIBUTING.md](CONTRIBUTING.md) — contribuer (conventions, tests)
- [SECURITY.md](SECURITY.md) — signalement de vulnérabilités, modèle de sécurité
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — code de conduite
- [AGENTS.md](AGENTS.md) — reprise du développement, checklist de mise à jour des `.md` avant commit, pièges PureBasic

## Licence

[MIT](LICENSE)
