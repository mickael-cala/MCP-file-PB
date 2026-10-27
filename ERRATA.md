# Errata — limitations et problèmes connus

## Couverture par serveur

| Serveur | Limitations connues |
|---|---|
| `fileMCP` | `read_file` tronqué à 20 Ko, `read_file_lines` ≤ 5 Mo, binaires refusés en lecture, suppression récursive sur opt-in (`recursive=true`) |
| `MCP-Fetch-PB` | conversion HTML→Markdown basique ; pas de JS ; hôtes privés refusés après résolution DNS ; `curl` requis hors Windows ; 3 redirections maximum |
| `MCP-SequentialThinking-PB` | état en mémoire (perdu à l'arrêt) ; pas de persistance |
| `memoryMCP` | une instance écrit à la fois (SQLite, pas de WAL) ; pas de FTS |
| `dbMCP` | lecture seule par défaut ; PostgreSQL sans binding de paramètres ; un seul moteur par processus (SQLite **ou** PostgreSQL, choisi au démarrage par `MCP_DB_POSTGRES_DSN`) ; requêtes multi-instructions refusées |
| `context7MCP` | `query_docs` exige une clé ; hors ligne → erreur explicite |
| `gitMCP` | sous-processus git requis ; sortie plafonnée à 40 Ko |
| `githubMCP` | token requis ; écritures via `confirm=true` ; pagination manuelle |

## Limitations par design

- **`read_file` tronque au-delà de 20 000 octets** ; utiliser `read_file_lines`
  pour les gros fichiers (limite 5 Mo).
- **Fichiers binaires** : les extensions exécutables (`exe`, `dll`, `so`,
  `dylib`, `o`, `obj`, `bin`, `a`, `lib`, `ppu`) sont refusées par `read_file`
  et `read_file_lines`, et ignorées par `search_files`.
- **`delete_file` est non récursif par défaut** : un dossier non vide est
  refusé avec un message explicite ; `recursive=true` active la suppression
  récursive (opération destructive).
- **Un seul client à la fois** : le serveur traite les requêtes en séquence
  sur stdin/stdout, sans sessions ni annulation de requêtes.
- **Communication unidirectionnelle par ligne** : chaque message JSON-RPC doit
  tenir sur une seule ligne (protocole stdio délimité par `\n`).

## Problèmes connus

- `isError` est piloté par l'outil (`ToolOk`/`ToolFail`). L'heuristique de
  texte (`Erreur`, `Impossible`, `Echec`, `introuvable`, `refusee`, `depasse`)
  ne sert plus que de dernier recours pour un outil non instrumenté, et
  uniquement sur la **première ligne** du message : les payloads (JSON,
  listings, contenu de fichier) ne sont plus jamais inspectés.
- `change_root` avec un secret incorrect renvoie `isError: true` mais le
  texte reste en français non structuré ; les clients doivent tester le
  drapeau, pas le texte.
- Tests exécutés sous **Windows** et **Linux (WSL2 Ubuntu 26.04)** ; macOS
  n'est pas encore validé. Aucune CI automatisée (PureBasic sous licence).

## Résultats des tests

Dernière exécution de `run_all.bat` (Windows) et `./run_all.sh`
(WSL2 Ubuntu 26.04, PureBasic 6.41 Linux x64) : **10/10 étapes** — tests unitaires
42 + 33 + 42 + 19 + 24 + 40 réussis (mcp_common, Memory, Database, Context7,
Git, GitHub), robustesse/performance **17/17**, tests d'intégration
**122/122** (8 serveurs ; PostgreSQL et Context7 live sont ignorés sans
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
