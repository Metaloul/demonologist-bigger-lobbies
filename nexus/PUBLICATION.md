# Publier Big Lobbies sur Nexus Mods

Tout ce qu'il faut pour mettre en ligne Big Lobbies v1.6.0. C'est un dérivé du mod « 16-Player Lobbies » de YzzSlav (Demonologist, mod 13).

## Fichiers utilisés

| Fichier | Rôle |
| --- | --- |
| `BigLobbies-AllInOne-1.6.0.zip` | Fichier principal recommandé : installeur, mod et UE4SS décompressé (aucune archive imbriquée, rien n'est téléchargé) |
| `BigLobbies-1.6.0.zip` | Mod seul, à glisser dans le dossier du jeu, pour qui a déjà UE4SS |
| `nexus/description.bbcode.txt` | Description de la page, en anglais, à coller dans l'éditeur BBCode de Nexus |
| `nexus/message-to-YzzSlav.txt` | Demande d'autorisation à envoyer à l'auteur original, en anglais |

Les deux archives sont jointes à la release GitHub de la version, ou se reconstruisent dans `dist/` à la racine du dépôt : `pwsh -File scripts\get-ue4ss.ps1`, puis `pwsh -File scripts\build.ps1`.

## 1. Autorisation de l'auteur (avant toute mise en ligne)

Depuis le 3 novembre 2026, Nexus n'héberge un fork qu'avec l'accord explicite de l'auteur original. Le réglage par défaut est « Ask Me », y compris pour les anciens mods. La règle s'applique à partir du 2 janvier 2027.

1. Vérifier l'onglet *Description* > *Permissions and credits* du mod 13 : https://www.nexusmods.com/demonologist/mods/13
2. Envoyer `message-to-YzzSlav.txt` à YzzSlav en message privé Nexus.
3. Garder sa réponse : capture ou lien du message. Sans accord, ne pas publier ; lui proposer plutôt les fichiers.

## 2. Création de la page

- **Nom** : Big Lobbies - up to 16 players
- **Résumé** : Up to 16 players in Demonologist lobbies. Host only. Fork of 16-Player Lobbies by YzzSlav, updated for UE4SS's UE 5.6 build.
- **Version** : 1.6.0
- **Description** : coller `description.bbcode.txt`. La première phrase dit « published with the author's permission » : l'enlever si l'accord n'est pas encore là, et dans ce cas ne pas publier.
- **Prérequis** : UE4SS en lien externe, https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest, avec la note « Included in the All-in-one file ».
- **Crédits et permissions de la page** :
  - auteur original : YzzSlav ;
  - UE4SS sous licence MIT ;
  - régler soi-même modification, upload, conversion, fork et IA.
- **Déclaration IA** : « AI Assisted », ou « AI-Generated Content » si l'on considère que l'IA a écrit l'essentiel du code, ce qui est le cas ici. Outil : Claude (Anthropic). Ce qu'il a produit : le script Lua, l'installeur, la documentation. Nexus peut demander un historique du travail.

## 3. Fichiers à envoyer

| Archive | Catégorie Nexus | Nom affiché |
| --- | --- | --- |
| `BigLobbies-AllInOne-1.6.0.zip` | Main file | Big Lobbies - All-in-one (installer + UE4SS) |
| `BigLobbies-1.6.0.zip` | Main file ou Optional file | Big Lobbies - Mod only |

Nexus analyse chaque envoi à l'antivirus. Les .bat et .ps1 peuvent ralentir la validation : aucune règle ne les interdit, mais ils sont examinés de plus près.

## 4. Captures d'écran

- La planque avec le texte « 16-player mod active » en bas à droite.
- Un salon à plus de 4 joueurs. Il n'a pas encore été testé : à faire avant la publication.
- Éventuellement la fenêtre de l'installeur.

## Ce qui n'a pas été vérifié

- Le texte exact des permissions du mod 13 : la page est derrière Cloudflare.
- Un vrai salon à plus de 4 joueurs avec ce build.
- Les catégories proposées par Nexus pour Demonologist.
