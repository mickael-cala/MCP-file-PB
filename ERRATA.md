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
- Tests exécutés sous Windows uniquement pour l'instant ; les chemins des
  scripts de build Linux/macOS sont validés statiquement (`bash -n`) mais
  non testés en CI.

## Résultats des tests

Dernière exécution de `run_all.bat` : **9/9 étapes** — tests unitaires
24 + 33 + 37 + 19 + 24 + 40 réussis (mcp_common, Memory, Database, Context7,
Git, GitHub), tests d'intégration **100/100** (8 serveurs ; PostgreSQL et
Context7 live sont ignorés sans configuration/réseau, GitHub utilise un mock
local).
