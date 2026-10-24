# Errata — limitations et problèmes connus

## Limitations par design

- **`read_file` tronque au-delà de 20 000 octets** ; utiliser `read_file_lines`
  pour les gros fichiers (limite 5 Mo).
- **Aucune gestion des fichiers binaires** : les extensions exécutables
  (`exe`, `dll`, `so`, `dylib`…) sont refusées par les outils de lecture.
- **`delete_file` ne supprime que les dossiers vides** ; pas de suppression
  récursive (voir la roadmap).
- **Un seul client à la fois** : le serveur traite les requêtes en séquence
  sur stdin/stdout, sans sessions ni annulation de requêtes.
- **Communication unidirectionnelle par ligne** : chaque message JSON-RPC doit
  tenir sur une seule ligne (protocole stdio délimité par `\n`).

## Problèmes connus

- La détection d'erreur (`isError`) repose sur une heuristique sur le texte de
  réponse (`Erreur`, `Impossible`, `Echec`, `introuvable`, `refusee`,
  `depasse`). Un message utilisateur contenant ces mots en début de ligne
  pourrait être mal classé.
- `change_root` avec un secret incorrect renvoie `isError: true` mais le
  texte reste en français non structuré ; les clients doivent tester le
  drapeau, pas le texte.
- Tests exécutés sous **Windows** et **Linux (WSL2 Ubuntu 26.04)** ; macOS
  n'est pas encore validé. Aucune CI automatisée (PureBasic sous licence).

## Résultats des tests

Dernière exécution de `run_all.bat` : **10/10 étapes** — tests unitaires
24 + 33 + 37 + 19 + 24 + 40 réussis (mcp_common, Memory, Database, Context7,
Git, GitHub), robustesse/performance **17/17**, tests d'intégration
**100/100** (8 serveurs ; PostgreSQL et Context7 live sont ignorés sans
configuration/réseau, GitHub utilise un mock local).

## Comportements documentés (Phase 6)

- **Deux instances Memory sur la même base** : SQLite autorise plusieurs
  connexions ; les écritures sont sérialisées (verrou d'écriture), les
  lectures voient l'état validé. Aucun mode WAL n'est activé : des écritures
  concurrentes longues peuvent produire une erreur `database is locked`
  remontée proprement par l'outil.
- **Ligne stdin > 64 Ko** : la ligne est tronquée par la couche stdio
  (buffer 64 Ko) et rejetée en `-32700` ; le serveur poursuit normalement.
  Ne pas envoyer plus de 64 Ko par message JSON.
- **En-têtes HTTP hors Windows** : assurés par **curl** (config file). Si curl
  est absent, `context7MCP`/`githubMCP` retournent une erreur explicite.
- **Compilation Linux** : nécessite `libssl-dev` et `libsqlite3-dev`
  (bibliothèques liées par PureBasic). Validé sous WSL2 Ubuntu 26.04 ;
  macOS non testé à ce jour.
