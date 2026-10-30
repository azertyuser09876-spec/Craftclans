# Craftclans

Jeu en monde ouvert 2D (vue du dessus avec effet de profondeur), en ligne, PvPvE, fait avec **Godot 4.4.1**.
Le document de conception complet est dans les fichiers du projet Claude (`conception/`).

## Où en est le jeu

| Étape | Contenu | État |
|---|---|---|
| 0 | Fondations : serveur, connexion, déplacement, sauvegarde, programme de gestion, publication | ✅ v0.0.1 |
| 1 | Rôles et combat : 6 rôles, visée au sol, tir chargé, esquive, équipes, mannequins | ✅ v0.1.0 |
| 2 | La carte : monde infini par morceaux, 10 biomes, danger selon la distance, minicarte et grande carte | ✅ v0.2.0 |
| 2.1 | Correctif réseau : IPv6, essai IPv6 puis IPv4, adresses à donner dans le panneau, pare-feu | ✅ v0.2.1 |
| 2.2 | Test de connexion et réparation du pare-feu dans le panneau, minicarte qui ne déborde plus | ✅ v0.2.2 |
| 3 | Ressources, inventaire, mort | à venir |
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
  monde.gd          monde infini : morceaux de 32×32 cases générés depuis la graine, biomes, danger, collisions
  regles.gd         règles de déplacement (appliquées par le serveur, prédites par le jeu)
  roles.gd          les rôles et leurs capacités (vie, dégâts, portées, recharges)
  donnees_boss.gd   liste des boss mondiaux
scripts/serveur/  serveur dédié
  serveur.gd        logique du serveur (il fait autorité sur tout)
  sauvegarde.gd     sauvegarde versionnée, migrations, archives, copies de secours
  combat.gd         vie, dégâts, projectiles, zones, effets, mort et réapparition
  commandes.gd      commandes admin, triches, boss (console et chat /aide)
  panneau_admin.gd  fenêtre de gestion du serveur
scripts/client/   le jeu
  menu.gd, jeu.gd, vue_monde.gd, carte_vue.gd (minicarte et grande carte), joueur_visuel.gd, joystick.gd, theme_jeu.gd,
  effets.gd, barre_combat.gd, mannequin_visuel.gd
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

## Le monde

Le monde est infini et découpé en morceaux de 32×32 cases. **Seul le serveur génère le terrain** (à partir de la graine)
et envoie au jeu les morceaux autour de chaque joueur. Chaque morceau visité est enregistré dans
`monde\morceaux\x_y.bin` : il ne change plus, même si le générateur change dans une future version.
Le danger (0 à 10) augmente avec la distance au feu de camp de départ ; les vallées paisibles sont plus calmes,
les terres brûlées toujours dangereuses.

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
`--capture=fichier.png:secondes`, `--port=8001`, `--tactile` (interface téléphone sur PC),
`--onglet=N` (serveur : ouvre un onglet du panneau).
