# Contribuer au projet

Merci de votre intérêt ! Ce dépôt est un projet personnel, mais les
signalements de bugs et les suggestions sont les bienvenus.

## Signaler un bug ou proposer une fonctionnalité

Utilisez les [issues GitHub](https://github.com/mickael-cala/MCP-file-PB/issues)
avec les modèles fournis (bug, fonctionnalité). Incluez si possible :

- le système d'exploitation et la version de PureBasic ;
- la requête JSON-RPC envoyée et la réponse obtenue ;
- le résultat de `python tests/test_mcp.py`.

## Soumettre une modification

1. Forkez le dépôt et créez une branche depuis `main`.
2. Modifiez le code dans `src/fileMCP.pb`.
3. Vérifiez que la compilation et les tests passent :
   ```bash
   build.bat            # ou ./build.sh
   python tests/test_mcp.py
   ```
4. Ouvrez une pull request vers `main` en remplissant le modèle.

## Conventions de code

- **PureBasic** avec `EnableExplicit` obligatoire (déjà en tête de fichier).
- Commentaires et messages d'erreur en **français**, comme le code existant.
- Sélection multi-OS par `CompilerIf #PB_Compiler_OS = #PB_OS_Windows`, jamais
  par hacks runtime.
- **Ne jamais utiliser `Input()`** pour lire stdin : utiliser la couche
  `ReadStdinLine()` / `SendRawLine()` existante (fiable en mode pipe).
- Tout nouvel outil MCP doit : être ajouté au catalogue (`BuildToolsCatalog`),
  avoir son `Case` dans le dispatch `tools/call`, être confiné par
  `ValiderChemin()`, et être couvert par un test dans `tests/test_mcp.py`.
- Un message d'échec d'outil doit commencer par un mot détecté comme erreur
  (`Erreur`, `Impossible`, `Echec`, `introuvable`, `refusee`, `depasse`)
  pour que le drapeau `isError` MCP soit positionné correctement.

## Sécurité

Voir [SECURITY.md](SECURITY.md). Toute modification touchant au confinement
des chemins (`ValiderChemin`) ou à `change_root` exige une revue attentive.
