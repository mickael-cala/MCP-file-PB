## Description

<!-- Que fait cette pull request ? Référence l'issue : Fixes #123 -->

## Vérifications effectuées

- [ ] Compilation : `build.bat` / `./build.sh` OK
- [ ] Tests : `python tests/test_mcp.py` → 26/26 (ou justifié)
- [ ] Nouvel outil MCP éventuel : ajouté au catalogue, au dispatch, confiné par `ValiderChemin()`, testé
- [ ] Messages d'échec détectés comme erreurs (`Erreur` / `Impossible` / `Echec` / `introuvable` / `refusee` / `depasse`)

## Sécurité

<!-- Toute modification de ValiderChemin, change_root ou de la couche stdio
     a-t-elle été revue avec attention ? -->
