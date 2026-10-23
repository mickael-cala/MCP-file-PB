# Journal des versions

Ce projet suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le [versionnage sémantique](https://semver.org/lang/fr/).

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
