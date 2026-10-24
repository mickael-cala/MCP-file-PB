# Suivi du plan de développement

État des phases du plan (mise à jour : 2026-10-24).

| Phase | Sujet | Statut | Livrables |
|---|---|---|---|
| **0** | Infrastructure commune et harnais de test | ✅ Terminée | `mcp_common/` (stdio, logging, json_helpers, protocol, jsonrpc, http), `tests/mcp_client.py`, `tests/unit_test.pbi`, `run_all.bat/.sh`, serveur de démo `examples/minimal_server.pb` |
| **1** | Memory (SQLite) | ✅ Terminée | `memoryMCP` (9 outils), 33 tests unitaires, 18 tests d'intégration |
| **2** | Database (SQLite + PostgreSQL) | ✅ Terminée | `dbMCP` (5 outils, garde-fou lecture seule, PostgreSQL optionnel), 37 tests unitaires, 12 tests d'intégration |
| **3** | Context7 | ✅ Terminée | `context7MCP` (2 outils), WinHTTP + en-têtes, 19 tests unitaires, 7 tests d'intégration (live conditionnel) |
| **4** | Git | ✅ Terminée | `gitMCP` (7 outils, validation anti-injection), 24 tests unitaires, 12 tests d'intégration |
| **5** | GitHub | ✅ Terminée | `githubMCP` (10 outils, `confirm=true`, mock local), 40 tests unitaires, 25 tests d'intégration |
| **6** | Consolidation et tests transverses | ⏳ À faire | robustesse T6.1–T6.8, performances T6.9–T6.14, rapport final |

## Définition de « terminé » (état actuel)

| Critère | État |
|---|---|
| Tests unitaires des modules et serveurs | ✅ 24 + 33 + 37 + 19 + 24 + 40 = **177** |
| Tests d'intégration (8 serveurs) | ✅ **100/100** |
| `run_all.bat` / `run_all.sh` vert | ✅ **9/9 étapes** |
| Erreurs MCP en `isError: true` avec message clair | ✅ heuristique `DetectIsError` + refus explicites |
| Aucun secret loggé ni renvoyé | ✅ tokens/clés jamais inclus dans les réponses ; logs stderr |
| Documentation README complète | ✅ (outils, env, build, tests, config client) |
| Robustesse (10 000 requêtes, JSON 1 Mo, EOF brutal) | ⏳ Phase 6 |
| Performances cibles (T6.9–T6.14) | ⏳ Phase 6 |

## Détail des phases

### Phase 0 — Infrastructure (terminée)
- Modules partagés : `mcp_common/{stdio,logging,json_helpers,protocol,jsonrpc,http}.pbi`.
- Harnais Python `tests/mcp_client.py` (validation JSON-RPC 2.0, stdout/stderr, timeout).
- Framework de tests PureBasic `tests/unit_test.pbi` (asserts, rapport, code de sortie).
- `run_all` : compilation → tests unitaires → intégration → `tests/report.html`.
- Preuve : `examples/minimal_server.pb` (initialize + tools/list en ~100 lignes).

### Phase 1 — Memory (terminée)
- Schéma : `entities` / `observations` / `relations`, FK `ON DELETE CASCADE`.
- Outils : `create_entities`, `create_relations`, `add_observations`,
  `delete_entities`, `delete_observations`, `delete_relations`, `read_graph`,
  `search_nodes`, `open_nodes`.
- Tests : T1.1–T1.18 (création, doublons, cascade, recherche insensible à la
  casse, injection SQL, contenu 100 Ko). Bug corrigé : boucle infinie dans
  `BuildGraphJSON` (curseur `ForEach` partagé).

### Phase 2 — Database (terminée)
- Outils : `db_list_schemas`, `db_list_tables`, `db_describe_table`,
  `db_execute_query`, `db_explain` ; moteurs `sqlite` (défaut) et `postgres`.
- Garde-fou lecture seule `IsReadOnlyQuery` + `MCP_DB_ALLOW_WRITE`.
- Tests : T2.1–T2.8 (+ batterie de 19 cas sur le garde-fou) ; T2.9–T2.12
  PostgreSQL conditionnels (`MCP_DB_POSTGRES_TEST_DSN`).
- Écart documenté : driver PostgreSQL intégré à PureBasic (pas de
  `PQexecParams`), whitelist lecture seule en compensation.

### Phase 3 — Context7 (terminée)
- Outils : `resolve_library_id` (sans clé), `query_docs` (`MCP_CONTEXT7_API_KEY`).
- API réelle : GET (le POST renvoie 405) ; 400 trompeur sans clé intercepté.
- HTTP : WinHTTP sous Windows, HTTP intégré ailleurs (clé non supportée).
- Tests : T3.1–T3.2 live (skip hors ligne), T3.4/T3.5 (clé absente/invalide),
  T3.8 (`max_length`), plus 19 tests unitaires hors ligne.

### Phase 4 — Git (terminée)
- Outils : `git_is_repo`, `git_status`, `git_log`, `git_diff`, `git_show`,
  `git_branches`, `git_blame`.
- `GitRun()` : shell + `2>&1`, lecture jusqu'à fin de processus, sortie 40 Ko.
- Sécurité : `GitSafeParam` sur tous les paramètres (injection testée).
- Tests : T4.1–T4.18 (fixture réelle : 4 commits, 2 branches, espaces,
  injections, git absent).

### Phase 5 — GitHub (terminée)
- Outils : 10 outils repos/issues/PR/commits/recherches.
- `confirm=true` obligatoire pour les écritures ; mock local `tests/mock_github.py`.
- Tests : T5.1–T5.15 via mock + `T5.4` sans token ; 40 tests unitaires.

### Phase 6 — Consolidation (à faire)
- Robustesse : 10 000 `tools/list`, JSON 1 Mo, JSON malformé, fermeture stdin,
  `kill` pendant une requête, DB verrouillée, chemin invalide, réseau coupé.
- Performances : entités (100 < 500 ms), recherche 10 000 entités (< 200 ms),
  SELECT simple (< 50 ms), `git log` 1 000 commits (< 200 ms).
- Rapport HTML consolidé par serveur, `examples/mcp.json` complet.
