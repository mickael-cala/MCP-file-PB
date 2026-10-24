# Journal des versions

Ce projet suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le [versionnage sémantique](https://semver.org/lang/fr/).

## [Non publié]

### Ajouté (Phase 0 — infrastructure commune et harnais de test)
- **`mcp_common/`** : modules partages par tous les serveurs —
  `stdio.pbi` (E/S stdio multi-OS), `logging.pbi` (logs sur stderr),
  `json_helpers.pbi` (arguments + schémas d'outils), `protocol.pbi`
  (identité + réponse `initialize`), `jsonrpc.pbi` (noyau JSON-RPC 2.0
  générique : dispatch par hooks `*G_ToolHandler`/`*G_CatalogBuilder`,
  boucle `MCPMainLoop()`).
- **`examples/minimal_server.pb`** : serveur MCP minimal de démo
  (validation de la Phase 0, < 200 lignes).
- **`tests/mcp_client.py`** : harnais de test externe (client MCP Python
  avec validation de conformité JSON-RPC 2.0).
- **`tests/unit_test.pbi` + `tests/test_common.pb`** : micro-framework de
  tests unitaires PureBasic + 24 tests sur les modules communs.
- **`run_all.bat` / `run_all.sh`** : compilation + tests unitaires +
  tests d'intégration + rapport `tests/report.html`.

### Modifié
- Refactor des 3 serveurs (`fileMCP`, `MCP-Fetch-PB`,
  `MCP-SequentialThinking-PB`) sur `mcp_common/` : suppression de toute
  la duplication (couche stdio, JSON-RPC, helpers JSON). Comportement
  inchangé, validé par les 26 tests d'intégration.

### Ajouté (serveurs)
- **MCP-Fetch-PB** : serveur MCP de récupération web (`src/MCP-Fetch-PB.pb`) —
  outil `fetch` (URL → Markdown, HTML brut en option), protection SSRF
  (HTTP/HTTPS uniquement, IPs littérales refusées), timeout.
- **MCP-SequentialThinking-PB** : serveur MCP de raisonnement séquentiel
  (`src/MCP-SequentialThinking-PB.pb`) — outil `sequential_thinking`
  (étapes, révisions, branches, état courant en JSON).
- `build.bat` / `build.sh` compilent désormais les 3 serveurs.
- Tests étendus à 26 (catalogues et outils des 3 serveurs, cas d'erreur
  fetch hors ligne).

### Corrigé
- Compilation PureBasic 6.41 des nouveaux serveurs : retrait d'`InitNetwork()`
  (réseau auto-initialisé), remplacement de `RepeatString()` inexistant,
  déclarations anticipées (`Declare`) pour `GetArgString`/`GetArgInt`/`GetArgBool`.

## [1.0.0] - 2026-10-23

### Ajouté
- Serveur MCP (Model Context Protocol) de gestion de fichiers en PureBasic :
  transport JSON-RPC 2.0 sur stdin/stdout, 100 % natif, multi-plateforme
  (Windows, Linux, macOS).
- 10 outils MCP : `list_files`, `read_file`, `read_file_lines`, `write_file`,
  `create_directory`, `delete_file`, `move_file`, `get_file_info`,
  `search_files`, `change_root`.
- Sécurité par confinement : toutes les opérations limitées à la racine
  `MCP_ROOT`, avec normalisation des chemins (protection contre les
  traversées `..`) ; `change_root` protégé par `MCP_ROOT_SECRET`.
- Réponse `initialize` conforme au protocole (protocolVersion 2024-11-05).
- Scripts de build : `build.bat` / `build.sh` (sortie dans `build/`),
  `clean.bat` / `clean.sh`.
- Harnais de tests fonctionnels `tests/test_mcp.py` (17 tests : outils +
  cas de sécurité).

### Corrigé
- Compilation Windows : couche E/S stdio via kernel32
  (`ReadFile` / `WriteFile` / `FlushFileBuffers` chargés dynamiquement).
- `isError` MCP fiable : détection étendue (`introuvable`, `refusee`,
  `depasse`).

[1.0.0]: https://github.com/mickael-cala/MCP-file-PB/releases/tag/v1.0.0
