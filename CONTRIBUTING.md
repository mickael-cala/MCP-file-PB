# Contribuer au projet

Merci de votre intérêt ! Ce dépôt est un projet personnel, mais les
signalements de bugs et les suggestions sont les bienvenus.

## Signaler un bug ou proposer une fonctionnalité

Utilisez les [issues GitHub](https://github.com/mickael-cala/MCP-file-PB/issues)
avec les modèles fournis (bug, fonctionnalité). Incluez si possible :

- le système d'exploitation et la version de PureBasic ;
- le serveur concerné et la requête JSON-RPC envoyée / réponse obtenue ;
- le résultat de `python tests/test_mcp.py` (100 tests) et/ou
  `run_all.bat` / `./run_all.sh`.

## Soumettre une modification

1. Forkez le dépôt et créez une branche depuis `main`.
2. Modifiez le code source concerné dans `src/` (le cœur métier d'un serveur
   est dans `src/<serveur>_core.pbi`, le `.pb` ne contient que le `main`).
   Prérequis Linux : `sudo apt install libssl-dev libsqlite3-dev curl`.
3. Vérifiez que tout passe :
   ```bash
   build.bat            # ou ./build.sh : compile les 8 serveurs
   run_all.bat          # ou ./run_all.sh : unitaires + intégration + rapport
   ```
4. Ouvrez une pull request vers `main` en remplissant le modèle.

## Conventions de code

- **PureBasic** avec `EnableExplicit` obligatoire.
- Commentaires et messages d'erreur en **français**, comme le code existant.
- Sélection multi-OS par `CompilerIf #PB_Compiler_OS = #PB_OS_Windows`, jamais
  par hacks runtime. Ne pas mélanger les options de compilation : `build.bat`
  = options Windows (`/EXE`, `/CONSOLE`), `build.sh` = options POSIX
  (`-o`, `-cl`, `-t`).
- Fins de ligne : `.gitattributes` impose LF aux scripts et sources
  (un shebang en CRLF casse l'exécution sous Linux/WSL).
- **Ne jamais utiliser `Input()`** pour lire stdin : utiliser la couche
  `ReadStdinLine()` / `SendRawLine()` de `mcp_common/stdio.pbi`.
- **Architecture** : un serveur inclut `mcp_common/` (ordre : `stdio`,
  `logging`, `json_helpers`, `http` si besoin, `protocol`, `jsonrpc`),
  renseigne `G_ServerName`/`G_ServerVersion`, les hooks `*G_ToolHandler` et
  `*G_CatalogBuilder`, puis appelle `MCPMainLoop()`. Modèle :
  `examples/minimal_server.pb`.
- **Aucune duplication** de code stdio/JSON-RPC/HTTP dans un serveur.
- Tout nouvel outil MCP doit :
  - être ajouté au catalogue (`BuildToolsCatalog` / `XxxBuildCatalog`) ;
  - avoir son `Case` dans le dispatch ;
  - assainir ses entrées (chemins, refs, segments d'URL) avant usage ;
  - commencer ses messages d'échec par `Erreur` / `ERREUR` / `Impossible` /
    `Echec` ou contenir `introuvable` / `refusee` / `depasse` pour que
    `isError` soit positionné ;
  - être couvert par un test (unitaire `.pb` et/ou intégration Python).
- Les écritures destructrices ou externes (fichiers, SQL, API GitHub) doivent
  être explicitement protégées (confinement `MCP_ROOT`, `MCP_DB_ALLOW_WRITE`,
  `confirm=true`).

## Tests

- Unitaires PureBasic : `tests/test_<module>.pb` (framework `tests/unit_test.pbi`).
- Intégration : `tests/test_mcp.py` (harnais `tests/mcp_client.py` ; mock
  GitHub dans `tests/mock_github.py` ; PostgreSQL et Context7 live sont
  conditionnels).
- `run_all` doit être **vert (10/10)** avant toute pull request, y compris
  les tests de robustesse/performance (`tests/test_robustness.py`).

## Sécurité

Voir [SECURITY.md](SECURITY.md). Toute modification touchant au confinement
des chemins, aux garde-fous d'écriture ou à la gestion des secrets exige une
revue attentive.
