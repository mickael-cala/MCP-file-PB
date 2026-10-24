# Feuille de route

Les phases 0 à 6 du plan de développement sont terminées (voir [PLAN.md](PLAN.md)).
Cette feuille de route couvre la suite.

## Prochaines étapes

- **v1.0.0 publiée** (tag + [GitHub Release](https://github.com/mickael-cala/MCP-file-PB/releases/tag/v1.0.0),
  binaires Windows + SHA256SUMS).
- Valider la compilation et les tests sur **Linux et macOS**, puis publier
  les binaires correspondants dans la release ou en v1.0.1.

## Court terme

- Publier les exécutables Windows/Linux/macOS en [GitHub Releases](https://github.com/mickael-cala/MCP-file-PB/releases)
  et créer le tag `v1.0.0`.
- Exécuter la suite sur Linux et macOS (aujourd'hui validée sous Windows).
- Ajouter un `CHANGELOG` de version au moment du tag.

## Moyen terme

- **FileMCP** : `copy_file`, suppression récursive optionnelle, pagination de
  `list_files`/`search_files`, lecture binaire base64.
- **Memory** : recherche plein texte (FTS5), export/import JSON du graphe.
- **Database** : PostgreSQL avec binding de paramètres, `db_explain` formaté.
- **Git** : `git_log` avec plage de dates, `git_diff --stat`, `--no-color`.
- **GitHub** : commentaires d'issues, review de PR, pagination automatique.
- **Context7** : cache local des réponses par bibliothèque.
- Fichier de configuration JSON commun en alternative aux variables
  d'environnement.

## Non prévu

- Transport autre que stdio (SSE, HTTP) : le périmètre reste des serveurs MCP
  locaux simples, sans dépendance.
