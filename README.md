# Craftclans

Jeu en monde ouvert 2D (vue du dessus avec effet de profondeur), en ligne, PvPvE, fait avec **Godot 4.4.1**.
Le document de conception complet est dans les fichiers du projet Claude (`conception/`).

## Où en est le jeu

| Étape | Contenu | État |
|---|---|---|
| 0 | Fondations : serveur, connexion, déplacement, sauvegarde, programme de gestion, publication | ✅ v0.0.1 |
| 1 | Rôles et combat | à venir |
| 2 | La carte (monde infini, biomes, jour/nuit) | à venir |
| … | voir la feuille de route du document de conception | |

## Jouer

Les versions à télécharger sont dans les [Releases](../../releases) :

* `Craftclans-Windows-vX.zip` : le jeu pour PC ;
* `Craftclans-vX.apk` : le jeu pour Android ;
* `Craftclans-Serveur-Windows-vX.zip` : le serveur et son programme de gestion.

## Organisation du code

```
principal.tscn / scripts/principal.gd   point d'entrée : lance le jeu ou le serveur
scripts/commun/   partagé par le jeu et le serveur
  config.gd         constantes, version, protocole réseau, options de lancement
  reseau.gd         tous les messages réseau (WebSocket, port 8000)
  monde.gd          génération du terrain à partir d'une graine, collisions
  regles.gd         règles de déplacement (appliquées par le serveur, prédites par le jeu)
  donnees_boss.gd   liste des boss mondiaux
scripts/serveur/  serveur dédié
  serveur.gd        logique du serveur (il fait autorité sur tout)
  sauvegarde.gd     sauvegarde versionnée, migrations, archives, copies de secours
  commandes.gd      commandes admin, triches, boss (console et chat /aide)
  panneau_admin.gd  fenêtre de gestion du serveur
scripts/client/   le jeu
  menu.gd, jeu.gd, vue_monde.gd, joueur_visuel.gd, joystick.gd, theme_jeu.gd
assets/           images (générées par outils/generer_assets.py)
distribution/     fichiers ajoutés aux zips (lisez-moi, .bat du serveur)
outils/           générateur d'assets, script de version
```

**Le serveur fait autorité** : les joueurs n'envoient que leurs intentions (direction, chat), le serveur calcule
tout et renvoie l'état. Le jeu prédit le déplacement du joueur pour qu'il soit immédiat, puis se recale sur le serveur.

**Un seul projet pour le jeu et le serveur** : l'export « Serveur Windows » ajoute la fonctionnalité `serveur`,
qui fait démarrer le serveur au lieu du jeu. Depuis l'éditeur, on lance le serveur avec l'argument `--serveur`
(Projet > Paramètres > Exécuter > Arguments principaux, ou `godot --path . -- --serveur`).

## Sauvegarde du monde et mises à jour

La sauvegarde est dans `%APPDATA%\Craftclans\serveur`, hors du dossier du serveur. Elle porte un **numéro de format**
(`Sauvegarde.FORMAT` dans `scripts/serveur/sauvegarde.gd`) :

* **Mise à jour normale** qui ajoute des données : les nouveaux champs prennent leur valeur par défaut tout seuls.
  Si une donnée change de forme, augmenter `FORMAT` et ajouter une fonction dans `MIGRATIONS`.
* **Grosse mise à jour qui change tout** : mettre `FORMAT_MIN_COMPATIBLE` égal au nouveau `FORMAT`.
  Au démarrage, l'ancien monde est rangé dans `archives\` et un nouveau monde est créé.
* Une sauvegarde plus récente que le serveur n'est jamais écrasée : le serveur refuse de démarrer.

Si les messages réseau changent, augmenter `Config.PROTOCOLE` : un jeu et un serveur de protocoles différents
refusent de jouer ensemble et le joueur est invité à mettre à jour.

## Publier une version

```
publier.bat mineure "Ajout des rôles"
```

1. vérifie la branche `main` et fait `git pull` ;
2. augmente la version (`VERSION`, `project.godot`, `export_presets.cfg`, numéro de version Android) ;
3. exporte le jeu et le serveur Windows avec Godot pour vérifier que tout compile (sinon rien n'est envoyé) ;
4. `git commit`, `git tag`, `git push`.

La GitHub Action `.github/workflows/release.yml` construit ensuite le `.exe`, le `.apk` et le serveur,
et crée la release. Pour que `publier.bat` trouve Godot, mettre le chemin complet de
`Godot_v4.4.1-stable_win64_console.exe` dans `outils/godot_chemin.txt` (fichier ignoré par git).

**Signature Android** : sans les secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_ALIAS` et
`ANDROID_KEYSTORE_PASSWORD` (Settings > Secrets and variables > Actions), l'apk est signé avec une clé
temporaire différente à chaque release, et il faut désinstaller l'ancienne version avant d'installer la nouvelle.

## Régénérer les images

```
pip install pillow
python outils/generer_assets.py
```

## Options de test

`--auto-connexion=Pseudo@adresse`, `--auto-deplacement`, `--auto-commande="/heure 21;/devmode oui"`,
`--capture=fichier.png:secondes`, `--port=8001`.
