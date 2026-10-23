# Sécurité

## Signaler une vulnérabilité

**Ne publiez pas de vulnérabilité dans les issues publiques.**

Ouvrez plutôt un avis de sécurité privé via
[GitHub Security Advisories](https://github.com/mickael-cala/MCP-file-PB/security/advisories/new)
(contact : `mickael-cala`). Vous recevrez une réponse sous quelques jours ;
une correction sera publiée avant toute divulgation publique.

## Modèle de sécurité du serveur

Le serveur est conçu comme un **outil puissant volontairement confiné** :

- Toutes les opérations sont limitées à la racine `MCP_ROOT` (ou le répertoire
  courant si la variable est absente). Les chemins sont normalisés et les
  tentatives de sortie (`..`, chemins absolus hors racine) sont refusées.
- `change_root` exige le secret `MCP_ROOT_SECRET` ; s'il n'est pas configuré,
  la modification de racine est impossible.
- Les outils `write_file`, `delete_file`, `move_file` et `change_root` sont
  **destructeurs ou sensibles** : ne branchez ce serveur que sur un
  répertoire dont la perte de contenu serait acceptable, et ne l'exposez
  jamais à un réseau (transport stdio local uniquement).
- Le serveur n'a aucune authentification client : la sécurité repose entièrement
  sur le confinement du processus et de son environnement.

## Recommandations de déploiement

- Définissez toujours `MCP_ROOT` explicitement (ne reposez pas sur le
  répertoire courant).
- Définissez `MCP_ROOT_SECRET` avec un mot de passe fort si vous prévoyez
  d'utiliser `change_root`.
- Lancez le serveur avec les privilèges minimaux (utilisateur dédié si
  possible).
- Gardez le binaire à jour ; consultez les [errata](ERRATA.md) connus.

## Sécurité du code

Voir [CONTRIBUTING.md](CONTRIBUTING.md) : toute modification touchant à
`ValiderChemin()` ou à la couche E/S stdio exige une revue attentive et des
tests de sécurité (`tests/test_mcp.py` contient des cas de traversée).
