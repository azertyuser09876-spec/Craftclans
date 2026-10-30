class_name Commandes
extends RefCounted
## Commandes du serveur. Tapées dans la console du panneau de gestion (sans « / »),
## ou dans le chat du jeu par un joueur (avec « / »).
## La console du panneau a tous les droits. En jeu, il faut être admin, et les
## commandes de triche demandent en plus que les triches soient autorisées.

var serveur: Node

const PUBLIQUES := ["aide", "joueurs", "boss", "login", "moi", "equipe", "role", "roles", "objets"]
const TRICHES := ["tp", "vitesse", "vol", "dieu", "soigner", "donner", "vider"]

const AIDE := """Commandes :
  aide                      cette aide
  joueurs                   joueurs connectés
  moi                       ta position et tes droits
  login <mot de passe>      devenir admin (mot de passe dans le panneau du serveur)
  boss                      état des boss mondiaux
  role <rôle>               changer de rôle (hors combat) ; roles : la liste
  equipe <nom>              rejoindre ou créer une équipe (pas de tirs amis)
  equipe quitter            jouer seul
  objets                    liste des objets et ressources
Admin :
  annonce <texte>           message à tout le serveur
  expulser <joueur> [raison]
  bannir <joueur> [raison] / debannir <joueur>
  admin <joueur> oui|non
  heure <0-24> / temps <vitesse>
  devmode oui|non           mode développeur pour tous
  cheats oui|non            autoriser les triches des admins
  sauver                    sauvegarder maintenant
  pvp oui|non               autoriser les combats entre joueurs
  tuer <joueur>
  role <joueur> <rôle>      changer le rôle d'un joueur (même en combat)
  mannequin                 ajouter un mannequin d'entraînement à ta position
  mannequins retirer        retirer tous les mannequins
  monde                     infos sur le monde
  inventaire <joueur>       voir ce que porte un joueur
  sacs                      objets et corps au sol ; sacs retirer : tout enlever
  boss activer|endormir <id>
  boss programmer <id> <AAAA-MM-JJ> <HH:MM>
  boss hebdo <id> <jour> <HH:MM>    (jour : lundi, mardi…)
  boss deprogrammer <id>
Triche (admin, triches autorisées) :
  tp [joueur] <x> <y>  ou  tp [joueur] <autre joueur>   (x, y en cases)
  vitesse [joueur] <multiplicateur>
  vol [joueur]              traverser les obstacles et l'eau
  dieu [joueur]             invincible
  soigner [joueur]          remet la vie au maximum
  donner [joueur] <objet> [nombre]   (voir « objets »)
  vider [joueur]            vide l'inventaire"""


func _init(p_serveur: Node) -> void:
	serveur = p_serveur


## auteur : la session du joueur, ou un dictionnaire vide pour la console du serveur.
func executer(ligne: String, auteur: Dictionary = {}) -> String:
	var mots := ligne.strip_edges().split(" ", false)
	if mots.is_empty():
		return ""
	var nom: String = mots[0].to_lower()
	var args := Array(mots.slice(1))
	var console := auteur.is_empty()
	if not console:
		var publique: bool = nom in PUBLIQUES and not (nom == "boss" and not args.is_empty() and args[0] != "liste")
		if not publique and not serveur.est_admin(auteur.nom):
			return "Commande réservée aux admins. (/login <mot de passe> si tu l'es)"
		if nom in TRICHES and not serveur.donnees.reglages.cheats:
			return "Les triches sont désactivées sur ce serveur."
		serveur.journal("Commande de %s : /%s" % [auteur.nom, ligne])
	match nom:
		"aide", "help":
			return AIDE
		"joueurs":
			var noms := []
			for s in serveur.joueurs.values():
				noms.append(s.nom + (" (admin)" if serveur.est_admin(s.nom) else ""))
			return "%d connecté(s) : %s" % [noms.size(), _joindre(noms, ", ")]
		"moi":
			if console:
				return "La console du serveur a tous les droits."
			var c := Vector2i(auteur.pos / Config.TAILLE_TUILE)
			return "Position : %d %d. Admin : %s." % [c.x, c.y, "oui" if serveur.est_admin(auteur.nom) else "non"]
		"login":
			if console or args.is_empty():
				return "Utilisation : /login <mot de passe>"
			if args[0] == serveur.config.mot_de_passe_admin:
				serveur.definir_admin(auteur.nom, true)
				return "Mot de passe correct."
			serveur.journal("Mauvais mot de passe admin pour %s" % auteur.nom)
			return "Mauvais mot de passe."
		"annonce":
			if args.is_empty(): return "Utilisation : annonce <texte>"
			serveur.annonce(_joindre(args))
			return "Annonce envoyée."
		"expulser", "kick":
			if args.is_empty(): return "Utilisation : expulser <joueur> [raison]"
			return "Expulsé." if serveur.expulser(args[0], _joindre(args.slice(1))) else "Joueur introuvable."
		"bannir", "ban":
			if args.is_empty(): return "Utilisation : bannir <joueur> [raison]"
			serveur.bannir(_nom_exact(args[0]), _joindre(args.slice(1)))
			return "%s est banni." % args[0]
		"debannir", "unban":
			if args.is_empty(): return "Utilisation : debannir <joueur>"
			return "Débanni." if serveur.debannir(_nom_exact(args[0])) else "Ce joueur n'est pas banni."
		"admin":
			if args.size() < 2: return "Utilisation : admin <joueur> oui|non"
			return "Fait." if serveur.definir_admin(_nom_exact(args[0]), _oui(args[1])) else "Joueur inconnu."
		"heure":
			if args.is_empty(): return "Il est %.1f h." % serveur.donnees.heure
			serveur.definir_heure(float(args[0]))
			return "Il est maintenant %.1f h." % serveur.donnees.heure
		"temps":
			if args.is_empty(): return "Vitesse du temps : %s" % serveur.donnees.reglages.vitesse_temps
			serveur.definir_reglage("vitesse_temps", clampf(float(args[0]), 0.0, 100.0))
			return "Vitesse du temps : %s" % serveur.donnees.reglages.vitesse_temps
		"devmode":
			var v := args.is_empty() or _oui(args[0])
			serveur.definir_reglage("mode_dev", v)
			return "Mode développeur %s." % ("activé" if v else "désactivé")
		"cheats":
			var v := args.is_empty() or _oui(args[0])
			serveur.definir_reglage("cheats", v)
			return "Triches %s." % ("autorisées" if v else "interdites")
		"sauver", "save":
			serveur.sauver()
			return "Monde sauvegardé."
		"monde":
			var d: Dictionary = serveur.donnees
			return "Graine %d, créé le %s, format de sauvegarde %d, %d joueurs connus, %.1f h." % [
				int(d.graine), d.get("cree_le", "?"), Sauvegarde.FORMAT, d.joueurs.size(), d.heure]
		"boss":
			return _boss(args)
		"roles":
			var lignes := []
			for r in Roles.ORDRE:
				lignes.append("  %s : %s" % [r, Roles.LISTE[r].description])
			return "Rôles :\n" + _joindre(lignes, "\n")
		"role":
			if args.is_empty():
				return "Utilisation : role <rôle>. Rôles : " + _joindre(Roles.ORDRE, ", ")
			if args.size() >= 2 and (console or serveur.est_admin(auteur.nom)):
				var cible_r: Dictionary = serveur.session_par_nom(args[0])
				if cible_r.is_empty(): return "Joueur introuvable."
				return serveur.combat.changer_role(cible_r, args[1].to_lower(), true)
			if console: return "Utilisation : role <joueur> <rôle>"
			return serveur.combat.changer_role(auteur, args[0].to_lower())
		"equipe":
			if console: return "Commande pour les joueurs."
			if args.is_empty():
				return "Ton équipe : %s" % (auteur.equipe if auteur.equipe != "" else "aucune (tu joues seul)")
			var nom_eq: String = "" if args[0] == "quitter" else _joindre(args).left(20)
			auteur.equipe = nom_eq
			serveur.donnees.joueurs[auteur.nom]["equipe"] = nom_eq
			serveur.annoncer_joueur(auteur)
			serveur.envoyer_reglages(auteur.id)
			return "Tu joues seul." if nom_eq == "" else "Tu es dans l'équipe %s." % nom_eq
		"pvp":
			var v := args.is_empty() or _oui(args[0])
			serveur.definir_reglage("pvp", v)
			return "Combats entre joueurs %s." % ("activés" if v else "désactivés")
		"tuer":
			if args.is_empty(): return "Utilisation : tuer <joueur>"
			var cible_t: Dictionary = serveur.session_par_nom(args[0])
			if cible_t.is_empty(): return "Joueur introuvable."
			if not cible_t.mort:
				serveur.combat.mourir(cible_t, "l'admin")
			return "%s est mort." % cible_t.nom
		"soigner":
			var cible_s := _cible(args, auteur)
			if cible_s.s.is_empty(): return "Utilisation : soigner [joueur]"
			serveur.combat.soigner(cible_s.s, 9999)
			return "%s est soigné." % cible_s.s.nom
		"mannequin":
			var pos: Vector2 = serveur.monde.centre() if console else auteur.pos + Vector2(0, 40)
			serveur.combat.ajouter_mannequin(pos)
			return "Mannequin ajouté."
		"mannequins":
			serveur.combat.retirer_mannequins()
			return "Mannequins retirés."
		"tp":
			return _tp(args, auteur)
		"objets":
			var lignes := ["Objets :"]
			for id in Objets.LISTE:
				lignes.append("  %s : %s" % [id, Objets.LISTE[id].nom])
			for id in Equipement.AUTRES:
				lignes.append("  %s : %s" % [id, Equipement.AUTRES[id].nom])
			lignes.append("Équipement : tete_, torse_, jambes_, pieds_ + %s ;" % _joindre(Equipement.MATERIAUX.keys(), ", "))
			lignes.append("  arme_ + %s ; outil_ + %s" % [_joindre(Equipement.ARMES.keys(), ", "), _joindre(Equipement.OUTILS.keys(), ", ")])
			return _joindre(lignes, "\n")
		"donner":
			var cible_d := _cible(args, auteur)
			if cible_d.s.is_empty() or cible_d.args.is_empty():
				return "Utilisation : donner [joueur] <objet> [nombre]"
			var id_objet: String = cible_d.args[0].to_lower()
			if not Objets.existe(id_objet):
				return "Objet inconnu : %s. Tape objets." % id_objet
			var n := 1 if cible_d.args.size() < 2 else clampi(int(cible_d.args[1]), 1, 999)
			if int(Objets.infos(id_objet).pile) == 1:
				n = mini(n, 10)
			var donnes: int = serveur.recolte.donner(cible_d.s, id_objet, n)
			return "%d %s donné(s) à %s." % [donnes, Objets.infos(id_objet).nom, cible_d.s.nom]
		"vider":
			var cible_v := _cible(args, auteur)
			if cible_v.s.is_empty(): return "Utilisation : vider [joueur]"
			serveur.recolte.vider(cible_v.s)
			return "Inventaire de %s vidé." % cible_v.s.nom
		"inventaire":
			if args.is_empty(): return "Utilisation : inventaire <joueur>"
			var cible_i: Dictionary = serveur.session_par_nom(args[0])
			if cible_i.is_empty(): return "Joueur introuvable."
			var contenu := []
			for o in cible_i.inventaire:
				if not o.is_empty():
					contenu.append("%d %s" % [o.n, Objets.infos(o.id).nom])
			return "%s porte : %s" % [cible_i.nom, "rien" if contenu.is_empty() else _joindre(contenu, ", ")]
		"sacs":
			if not args.is_empty() and args[0] == "retirer":
				return "%d sac(s) retiré(s)." % serveur.recolte.retirer_tous_les_sacs()
			var lignes_s := ["%d sac(s) au sol :" % serveur.recolte.sacs.size()]
			for sac in serveur.recolte.sacs.values():
				lignes_s.append("  %s de %s en %d, %d (%d min restantes)" % ["Corps" if sac.genre == "corps" else "Sac",
					sac.nom, int(sac.pos.x / Config.TAILLE_TUILE), int(sac.pos.y / Config.TAILLE_TUILE), int(sac.reste / 60.0)])
			return _joindre(lignes_s, "\n")
		"vitesse":
			var cible := _cible(args, auteur)
			if cible.s.is_empty(): return "Utilisation : vitesse [joueur] <multiplicateur>"
			if cible.args.is_empty(): return "Utilisation : vitesse [joueur] <multiplicateur>"
			serveur.definir_cheat(cible.s, "vitesse", clampf(float(cible.args[0]), 0.1, 10.0))
			return "Vitesse de %s : x%s" % [cible.s.nom, cible.s.vitesse]
		"vol", "dieu":
			var cible := _cible(args, auteur)
			if cible.s.is_empty(): return "Utilisation : %s [joueur]" % nom
			serveur.definir_cheat(cible.s, nom, not cible.s[nom])
			return "%s pour %s : %s" % [nom.capitalize(), cible.s.nom, "oui" if cible.s[nom] else "non"]
	return "Commande inconnue : %s. Tape aide." % nom


func _joindre(a: Array, sep := " ") -> String:
	return sep.join(PackedStringArray(a))


func _oui(mot: String) -> bool:
	return mot.to_lower() in ["oui", "on", "1", "vrai", "true", "o", "yes"]


## Retrouve l'écriture exacte d'un pseudo connu (insensible à la casse).
func _nom_exact(nom: String) -> String:
	for connu in serveur.donnees.joueurs:
		if connu.to_lower() == nom.to_lower():
			return connu
	return nom


## Si le premier argument est un joueur connecté, il est la cible ; sinon c'est l'auteur.
func _cible(args: Array, auteur: Dictionary) -> Dictionary:
	if not args.is_empty():
		var s: Dictionary = serveur.session_par_nom(args[0])
		if not s.is_empty():
			return {"s": s, "args": args.slice(1)}
	return {"s": auteur, "args": args}


func _tp(args: Array, auteur: Dictionary) -> String:
	var cible := _cible(args, auteur)
	var s: Dictionary = cible.s
	var reste: Array = cible.args
	if s.is_empty() or reste.is_empty():
		return "Utilisation : tp [joueur] <x> <y>  ou  tp [joueur] <autre joueur>"
	var dest: Vector2
	if reste.size() >= 2 and reste[0].is_valid_float() and reste[1].is_valid_float():
		dest = (Vector2(float(reste[0]), float(reste[1])) + Vector2(0.5, 0.5)) * Config.TAILLE_TUILE
	else:
		var autre: Dictionary = serveur.session_par_nom(reste[0])
		if autre.is_empty():
			return "Joueur introuvable : %s" % reste[0]
		dest = autre.pos + Vector2(20, 0)
	serveur.teleporter(s, dest)
	return "%s téléporté." % s.nom


func _boss(args: Array) -> String:
	if args.is_empty() or args[0] == "liste":
		var lignes := ["Boss mondiaux :"]
		for b in DonneesBoss.LISTE:
			var e: Dictionary = serveur.etat_boss(b.id)
			lignes.append("  %s (%s) : %s %s" % [b.nom, b.id, e.etat,
				"" if e.programmes.is_empty() else "- programmé : " + _joindre(e.programmes, ", ")])
		return _joindre(lignes, "\n")
	if args.size() < 2:
		return "Utilisation : boss activer|endormir|programmer|hebdo|deprogrammer <id> …"
	var id: String = args[1]
	if DonneesBoss.par_id(id).is_empty():
		return "Boss inconnu : %s. Tape boss liste." % id
	match args[0]:
		"activer":
			serveur.activer_boss(id)
			return "Boss activé."
		"endormir":
			serveur.endormir_boss(id)
			return "Boss endormi."
		"programmer":
			if args.size() < 4: return "Utilisation : boss programmer <id> <AAAA-MM-JJ> <HH:MM>"
			return "Programmé." if serveur.programmer_boss(id, "%s %s" % [args[2], args[3]]) else "Date invalide."
		"hebdo":
			if args.size() < 4: return "Utilisation : boss hebdo <id> <jour> <HH:MM>"
			var jour := DonneesBoss.JOURS.find(args[2].to_lower())
			if jour < 0: return "Jour inconnu : %s" % args[2]
			return "Programmé chaque %s." % args[2] if serveur.programmer_boss(id, "hebdo %d %s" % [jour, args[3]]) else "Heure invalide."
		"deprogrammer":
			serveur.deprogrammer_boss(id)
			return "Programmes effacés."
	return "Action inconnue : %s" % args[0]
