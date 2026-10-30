class_name Construction
extends RefCounted
## Étape 6 côté serveur : poser, gérer, endommager et détruire les constructions des bases ;
## portes qui s'ouvrent devant leur équipe, pièges, tourelles (même propriétaire hors ligne),
## coffres et réapparition en base (cœur de base + lit).
##
## Une construction : {id, type, case (Vector2i, grille) ou null, pos, proprio, vie, max, niv,
##  ouvert (portes), contenu (coffres), bonus (dégâts des tourelles), fin (tourelle temporaire)}.

const PAS_PORTES := 0.2
const PAS_PIEGES := 0.25
const ALERTE := 60.0 # secondes entre deux alertes « ta base est attaquée » pour un même joueur
const DISTANCE_PORTE := 44.0
const PORTEE_GERER := 64.0

var serveur: Node
var liste := {} # id -> construction
var par_case := {} # Vector2i -> id (constructions sur la grille)
var _prochain_id := 1
var _accu_portes := 0.0
var _accu_pieges := 0.0
var _pieges_prets := {} # "id>joueur" -> temps
var _alertes := {} # proprio -> temps
var _ouvert_par := {} # joueur (id réseau) -> construction ouverte (coffre, panneau)


func _init(p_serveur: Node) -> void:
	serveur = p_serveur


# ------------------------------------------------------------------ Sauvegarde

func charger(donnees: Dictionary) -> void:
	liste.clear()
	par_case.clear()
	for d in donnees.get("constructions", []):
		var type := str(d.get("type", ""))
		if not Batiments.existe(type):
			continue
		var id := int(d.id)
		var rec := {"id": id, "type": type, "case": null, "pos": Vector2(float(d.x), float(d.y)),
			"proprio": str(d.get("proprio", "")), "niv": clampi(int(d.get("niv", 0)), 0, Batiments.NIVEAU_MAX),
			"max": maxi(1, int(d.get("max", Batiments.vie_max(type, 0)))), "vie": 0, "ouvert": false,
			"bonus": float(d.get("bonus", 0.0)), "contenu": []}
		rec.vie = clampi(int(d.get("vie", rec.max)), 1, rec.max)
		if d.get("cx") != null:
			rec.case = Vector2i(int(d.cx), int(d.cy))
			par_case[rec.case] = id
		if Batiments.infos(type).has("cases"):
			var contenu := []
			for o in d.get("contenu", []):
				contenu.append(Objets.nettoyer_objet(o))
			contenu.resize(int(Batiments.infos(type).cases))
			for i in contenu.size():
				if contenu[i] == null:
					contenu[i] = {}
			rec.contenu = contenu
		liste[id] = rec
		_prochain_id = maxi(_prochain_id, id + 1)


func enregistrer(donnees: Dictionary) -> void:
	var l := []
	for rec in liste.values():
		if rec.has("fin"):
			continue # tourelles temporaires
		var d := {"id": rec.id, "type": rec.type, "x": rec.pos.x, "y": rec.pos.y, "proprio": rec.proprio,
			"vie": rec.vie, "max": rec.max, "niv": rec.niv, "bonus": rec.bonus}
		if rec.case != null:
			d["cx"] = rec.case.x
			d["cy"] = rec.case.y
		if not rec.contenu.is_empty():
			d["contenu"] = rec.contenu
		l.append(d)
	donnees["constructions"] = l


## Morceau relu du disque : les murs, portes… sans construction connue (sauvegarde du monde
## plus ancienne que celle des morceaux, après un arrêt brutal) deviennent sans propriétaire.
func adopter(cle: Vector2i, m: Dictionary) -> void:
	var base := cle * Monde.TAILLE_MORCEAU
	for i in Monde.CASES:
		var d: int = m.deco[i]
		if d < Monde.Deco.MUR_BOIS and not d in [Monde.Deco.ETABLI, Monde.Deco.FOURNEAU, Monde.Deco.ENCLUME]:
			continue
		var type := Batiments.type_de_deco(d)
		var c := base + Vector2i(i % Monde.TAILLE_MORCEAU, i / Monde.TAILLE_MORCEAU)
		if type == "" or par_case.has(c):
			continue
		var rec := {"id": _prochain_id, "type": type, "case": c, "pos": VueMonde.centre_case(c), "proprio": "", "niv": 0,
			"max": Batiments.vie_max(type, 0), "vie": Batiments.vie_max(type, 0), "ouvert": d == Batiments.infos(type).get("ouverte", -1),
			"contenu": [], "bonus": 0.0}
		_prochain_id += 1
		liste[rec.id] = rec
		par_case[c] = rec.id
		_annoncer(rec)


# ------------------------------------------------------------------ Envoi aux joueurs

static func infos(rec: Dictionary) -> Dictionary:
	return {"id": rec.id, "type": rec.type, "pos": rec.pos, "grille": rec.case != null, "proprio": rec.proprio,
		"vie": rec.vie, "max": rec.max, "niv": rec.niv, "temporaire": rec.has("fin")}


func accueillir(s: Dictionary) -> void:
	var l := []
	for rec in liste.values():
		l.append(infos(rec))
	Reseau.s_constructions.rpc_id(s.id, l)


func _annoncer(rec: Dictionary) -> void:
	var i := infos(rec)
	for id in serveur.joueurs:
		Reseau.s_construction.rpc_id(id, i)


func _envoyer_contenu(rec: Dictionary) -> void:
	for jid in _ouvert_par:
		if _ouvert_par[jid] == rec.id and serveur.joueurs.has(jid):
			Reseau.s_contenu.rpc_id(jid, rec.id, rec.contenu)


# ------------------------------------------------------------------ Propriétaires

func equipe_de(nom: String) -> String:
	var s: Dictionary = serveur.session_par_nom(nom)
	if not s.is_empty():
		return s.equipe
	return str(serveur.donnees.joueurs.get(nom, {}).get("equipe", ""))


## Le joueur (ou la source : tourelle, piège) est-il du côté du propriétaire ?
func allie(source: Dictionary, proprio: String) -> bool:
	if proprio == "":
		return true # constructions sans propriétaire (anciennes stations) : à tout le monde
	var nom: String = source.get("proprio", source.get("nom", ""))
	if nom == proprio:
		return true
	var eq: String = source.get("equipe", "")
	return eq != "" and eq == equipe_de(proprio)


func _dire(s: Dictionary, texte: String) -> void:
	Reseau.s_message.rpc_id(s.id, texte, "systeme")


# ------------------------------------------------------------------ Poser

## Pose l'objet de la case `case_inv` à `pos` (sur la grille si `grille` ou si l'objet l'exige).
func poser(s: Dictionary, case_inv: int, pos: Vector2, grille: bool) -> void:
	if s.mort or case_inv < 0 or case_inv >= s.inventaire.size() or s.inventaire[case_inv].is_empty() or not pos.is_finite():
		return
	var type: String = s.inventaire[case_inv].id
	if not Batiments.existe(type):
		return
	var b := Batiments.infos(type)
	if s.pos.distance_to(pos) > Batiments.PORTEE + 20.0:
		_dire(s, "Trop loin : rapproche-toi.")
		return
	var monde: Monde = serveur.monde
	var t := float(Config.TAILLE_TUILE)
	var c := Vector2i((pos / t).floor())
	if Batiments.grille_seulement(type) or grille:
		pos = VueMonde.centre_case(c)
	var raison := empechement(type, pos, Batiments.grille_seulement(type) or grille)
	if raison != "":
		_dire(s, raison)
		return
	Objets.retirer(s.inventaire, type, 1)
	serveur.recolte.envoyer_inventaire(s)
	var bonus_vie := float(s.stats.get("batiment", 0.0)) + float(Roles.donnees(s.role).get("batiment", 0.0))
	var rec := {"id": _prochain_id, "type": type, "case": null, "pos": pos, "proprio": s.nom, "niv": 0,
		"max": Batiments.vie_max(type, 0, bonus_vie), "vie": 0, "ouvert": false, "contenu": [],
		"bonus": float(s.stats.get("tourelle", 0.0)) + float(Roles.donnees(s.role).get("tourelle", 0.0)) if type == "tourelle" else bonus_vie}
	rec.vie = rec.max
	_prochain_id += 1
	if b.has("cases"):
		for i in int(b.cases):
			rec.contenu.append({})
	if b.mode == "grille":
		rec.case = c
		par_case[c] = rec.id
		liste[rec.id] = rec
		serveur.recolte.changer_case(c, int(b.deco))
	else:
		liste[rec.id] = rec
	_annoncer(rec)
	serveur.sauver_bientot()
	serveur.combat.evenement("construction", {"id": s.id, "pos": pos, "type": type})
	serveur.experience.gagner(s, 1)


## Raison pour laquelle on ne peut pas poser ici ("" si possible).
func empechement(type: String, pos: Vector2, sur_grille: bool) -> String:
	var b := Batiments.infos(type)
	var monde: Monde = serveur.monde
	var t := float(Config.TAILLE_TUILE)
	var c := Vector2i((pos / t).floor())
	if monde.sol_en(c.x, c.y) in Monde.SOLS_BLOQUANTS:
		return "Impossible de construire sur l'eau ou la lave."
	if b.mode == "grille":
		if monde.deco_en(c.x, c.y) != Monde.Deco.AUCUN or par_case.has(c):
			return "Cette case est déjà occupée."
		if b.deco in Monde.DECOS_BLOQUANTES:
			for autre in serveur.joueurs.values():
				var boite := Rect2(Vector2(c) * t, Vector2.ONE * t).grow(Config.RAYON_JOUEUR)
				if boite.has_point(autre.pos):
					return "Quelqu'un est sur cette case."
			for rec in liste.values():
				if rec.case == null and Rect2(Vector2(c) * t, Vector2.ONE * t).grow(4.0).has_point(rec.pos):
					return "Une construction est sur cette case."
		return ""
	# Construction libre : pas sur un obstacle, pas collée à une autre construction libre.
	var d := monde.deco_en(c.x, c.y)
	if d in Monde.DECOS_BLOQUANTES or monde.collision(pos, 6.0):
		return "Pas de place ici."
	if d != Monde.Deco.AUCUN and not d in [Monde.Deco.SOL_BOIS, Monde.Deco.SOL_PIERRE, Monde.Deco.FLEURS, Monde.Deco.OS]:
		return "Pas de place ici."
	for rec in liste.values():
		if rec.case == null and rec.pos.distance_to(pos) < Batiments.ECART_LIBRE:
			return "Trop près d'une autre construction."
	return ""


# ------------------------------------------------------------------ Gérer (panneau, coffre)

func _a_portee(s: Dictionary, rec: Dictionary) -> bool:
	return s.pos.distance_to(rec.pos) <= PORTEE_GERER


## genre : ouvrir, fermer, prendre (valeur = case du coffre), deposer (valeur = case de l'inventaire),
## renforcer, reparer, demonter.
func sur_action(s: Dictionary, genre: String, id: int, valeur: int) -> void:
	if genre == "fermer":
		_ouvert_par.erase(s.id)
		return
	var rec: Dictionary = liste.get(id, {})
	if rec.is_empty() or s.mort or not _a_portee(s, rec):
		return
	var b := Batiments.infos(rec.type)
	var a_moi := allie(s, rec.proprio)
	match genre:
		"ouvrir":
			if b.has("cases"):
				if b.get("verrou", false) and not a_moi:
					_dire(s, "Coffre sécurisé de %s : seule son équipe peut l'ouvrir. Détruis-le pour le piller." % rec.proprio)
					return
				_ouvert_par[s.id] = rec.id
				Reseau.s_contenu.rpc_id(s.id, rec.id, rec.contenu)
		"prendre", "deposer":
			if not b.has("cases") or _ouvert_par.get(s.id, -1) != rec.id:
				return
			if genre == "prendre":
				if valeur < 0 or valeur >= rec.contenu.size() or rec.contenu[valeur].is_empty():
					return
				var o: Dictionary = rec.contenu[valeur]
				var reste := Objets.ajouter_pile(s.inventaire, o)
				if reste == int(o.n):
					_dire(s, "Inventaire plein.")
					return
				if reste > 0:
					o.n = reste
				else:
					rec.contenu[valeur] = {}
				if not a_moi:
					_alerter(rec, "%s pille ton %s !" % [s.nom, Batiments.infos(rec.type).nom])
			else:
				if valeur < 0 or valeur >= s.inventaire.size() or s.inventaire[valeur].is_empty():
					return
				var reste := Objets.ajouter_pile(rec.contenu, s.inventaire[valeur])
				if reste == int(s.inventaire[valeur].n):
					_dire(s, "Le coffre est plein.")
					return
				if reste > 0:
					s.inventaire[valeur].n = reste
				else:
					s.inventaire[valeur] = {}
			serveur.recolte.envoyer_inventaire(s)
			_envoyer_contenu(rec)
		"renforcer":
			if not a_moi:
				return
			var cout := Batiments.cout_renfort(rec.type, rec.niv)
			if cout.is_empty() or not _payer(s, cout):
				return
			var part: float = float(rec.vie) / rec.max
			rec.niv += 1
			rec.max = Batiments.vie_max(rec.type, rec.niv, rec.bonus if rec.type != "tourelle" else 0.0)
			rec.vie = maxi(1, int(round(part * rec.max)))
			_annoncer(rec)
			_dire(s, "%s renforcé (niveau %d) : -%d %% de dégâts subis." % [b.nom, rec.niv, int(Batiments.REDUCTION_NIVEAU * 100 * rec.niv)])
		"reparer":
			if not a_moi:
				return
			var cout := Batiments.cout_reparation(rec.type, rec.max - rec.vie)
			if cout.is_empty() or not _payer(s, cout):
				return
			rec.vie = rec.max
			_annoncer(rec)
		"demonter":
			if not a_moi:
				return
			if not rec.contenu.is_empty() and Objets.nombre_objets(rec.contenu) > 0:
				_dire(s, "Vide le coffre avant de le démonter.")
				return
			if rec.has("fin"):
				return
			if Objets.ajouter(s.inventaire, Batiments.objet_rendu(rec.type), 1) > 0:
				_dire(s, "Inventaire plein.")
				return
			serveur.recolte.envoyer_inventaire(s)
			_retirer(rec)


func _payer(s: Dictionary, cout: Dictionary) -> bool:
	for id in cout:
		if Objets.compter(s.inventaire, id) < int(cout[id]):
			_dire(s, "Il manque : %d %s." % [cout[id], Objets.infos(id).nom])
			return false
	for id in cout:
		Objets.retirer(s.inventaire, id, int(cout[id]))
	serveur.recolte.envoyer_inventaire(s)
	return true


func _retirer(rec: Dictionary) -> void:
	liste.erase(rec.id)
	if not rec.has("fin"):
		serveur.sauver_bientot()
	if rec.case != null:
		par_case.erase(rec.case)
		serveur.recolte.changer_case(rec.case, Monde.Deco.AUCUN)
	for jid in _ouvert_par.keys():
		if _ouvert_par[jid] == rec.id:
			_ouvert_par.erase(jid)
	for id in serveur.joueurs:
		Reseau.s_construction_retiree.rpc_id(id, rec.id)


## Une station démontée par la récolte (F) : on oublie sa construction.
func case_videe(c: Vector2i) -> void:
	var id: int = par_case.get(c, -1)
	if id >= 0 and liste.has(id):
		par_case.erase(c)
		liste.erase(id)
		for jid in serveur.joueurs:
			Reseau.s_construction_retiree.rpc_id(jid, id)


## Propriétaire d'une case construite ("" si aucune ou sans propriétaire).
func proprio_case(c: Vector2i) -> String:
	var id: int = par_case.get(c, -1)
	return liste[id].proprio if id >= 0 and liste.has(id) else ""


# ------------------------------------------------------------------ Dégâts

## Constructions dans un cercle, pour les coups, projectiles et zones.
func cibles_dans_cercle(centre: Vector2, rayon: float) -> Array:
	var r := []
	var t := float(Config.TAILLE_TUILE)
	var mini := Vector2i(((centre - Vector2(rayon, rayon)) / t).floor())
	var maxi := Vector2i(((centre + Vector2(rayon, rayon)) / t).floor())
	if (maxi - mini).x * (maxi - mini).y < 400:
		for cy in range(mini.y, maxi.y + 1):
			for cx in range(mini.x, maxi.x + 1):
				var id: int = par_case.get(Vector2i(cx, cy), -1)
				if id >= 0 and liste[id].pos.distance_to(centre) <= rayon + t * 0.5:
					r.append({"genre": "c", "rec": liste[id], "pos": liste[id].pos})
	for rec in liste.values():
		if rec.case == null and rec.pos.distance_to(centre) <= rayon:
			r.append({"genre": "c", "rec": rec, "pos": rec.pos})
	return r


func a_la_case(c: Vector2i) -> Dictionary:
	var id: int = par_case.get(c, -1)
	return liste.get(id, {})


## Dégâts d'une source (joueur, tourelle) sur une construction. Rien sur celles de son équipe.
func subir(rec: Dictionary, source: Dictionary, montant: float, type_degats: String) -> void:
	if not liste.has(rec.id) or (rec.proprio != "" and allie(source, rec.proprio)):
		return
	var n := maxi(1, int(round(montant * Batiments.multiplicateur(rec.type, type_degats, rec.niv))))
	rec.vie = maxi(0, rec.vie - n)
	serveur.combat.evenement("degats", {"cle": "c%d" % rec.id, "montant": n, "pos": rec.pos + Vector2(0, -12)})
	_alerter(rec, "Ta base est attaquée : %s (%d, %d) par %s !" % [Batiments.infos(rec.type).nom,
		floori(rec.pos.x / Config.TAILLE_TUILE), floori(rec.pos.y / Config.TAILLE_TUILE), source.get("nom", "?")])
	if rec.vie > 0:
		_annoncer(rec)
		return
	_detruire(rec, source)


func _detruire(rec: Dictionary, source: Dictionary) -> void:
	var b := Batiments.infos(rec.type)
	if not rec.contenu.is_empty():
		var objets := []
		for o in rec.contenu:
			if not o.is_empty():
				objets.append(o)
		if not objets.is_empty():
			serveur.recolte.deposer_sac(rec.pos, objets, "sac", rec.proprio)
	serveur.combat.evenement("destruction", {"pos": rec.pos, "type": rec.type})
	if rec.proprio != "" and not rec.has("fin"):
		serveur.journal("%s de %s détruit par %s" % [b.nom, rec.proprio, source.get("nom", "?")])
		var p: Dictionary = serveur.session_par_nom(rec.proprio)
		if not p.is_empty():
			Reseau.s_message.rpc_id(p.id, "Ton %s a été détruit par %s." % [b.nom.to_lower(), source.get("nom", "?")], "combat")
	_retirer(rec)


## Clé de l'ingénieur : répare les constructions de son équipe.
func reparer_par(rec: Dictionary, montant: float) -> void:
	if rec.vie >= rec.max:
		return
	var avant: int = rec.vie
	rec.vie = mini(rec.max, rec.vie + int(round(montant)))
	serveur.combat.evenement("degats", {"cle": "c%d" % rec.id, "montant": rec.vie - avant, "pos": rec.pos + Vector2(0, -12), "soin": true})
	_annoncer(rec)


func _alerter(rec: Dictionary, texte: String) -> void:
	if rec.proprio == "" or rec.has("fin"):
		return
	var t: float = serveur.combat.temps
	if t - float(_alertes.get(rec.proprio, -1000.0)) < ALERTE:
		return
	_alertes[rec.proprio] = t
	var p: Dictionary = serveur.session_par_nom(rec.proprio)
	if not p.is_empty():
		Reseau.s_message.rpc_id(p.id, texte, "combat")


# ------------------------------------------------------------------ Bases et réapparition

## Point de réapparition dans une base de son équipe (cœur de base avec un lit à côté),
## la plus proche de l'endroit de la mort. Vector2.INF si aucune.
func point_reapparition(s: Dictionary) -> Vector2:
	var meilleur := Vector2.INF
	var d_min := INF
	var rayon := Batiments.RAYON_BASE * float(Config.TAILLE_TUILE)
	for coeur in liste.values():
		if coeur.type != "coeur_base" or not allie(s, coeur.proprio):
			continue
		for lit in liste.values():
			if lit.type == "lit" and allie(s, lit.proprio) and lit.pos.distance_to(coeur.pos) <= rayon:
				var d: float = coeur.pos.distance_to(s.pos)
				if d < d_min:
					d_min = d
					meilleur = lit.pos + Vector2(0, 18)
				break
	return meilleur


## Tourelle temporaire de l'ingénieur (compétence).
func tourelle_temporaire(s: Dictionary, pos: Vector2, cap: Dictionary) -> void:
	var c := Vector2i((pos / Config.TAILLE_TUILE).floor())
	if serveur.monde.case_bloquante(c.x, c.y):
		pos = serveur.monde.point_libre(pos)
	var rec := {"id": _prochain_id, "type": "tourelle", "case": null, "pos": pos, "proprio": s.nom, "niv": 0,
		"max": 150, "vie": 150, "ouvert": false, "contenu": [], "fin": serveur.combat.temps + float(cap.duree),
		"bonus": float(s.stats.get("degats", 0.0)), "degats": float(cap.degats)}
	_prochain_id += 1
	liste[rec.id] = rec
	_annoncer(rec)


# ------------------------------------------------------------------ Boucle

func tick(delta: float) -> void:
	var t: float = serveur.combat.temps
	_accu_portes += delta
	if _accu_portes >= PAS_PORTES:
		_accu_portes = 0.0
		_maj_portes()
	_accu_pieges += delta
	if _accu_pieges >= PAS_PIEGES:
		_accu_pieges = 0.0
		_pieges(t)
	for rec in liste.values():
		if rec.type != "tourelle":
			continue
		if rec.has("fin") and t >= rec.fin:
			serveur.combat.evenement("destruction", {"pos": rec.pos, "type": rec.type})
			_retirer(rec)
			continue
		if t >= float(rec.get("pret", 0.0)):
			_tirer(rec, t)
	# Coffres ouverts : on ferme si le joueur s'éloigne.
	for jid in _ouvert_par.keys():
		var s: Dictionary = serveur.joueurs.get(jid, {})
		var rec: Dictionary = liste.get(_ouvert_par[jid], {})
		if s.is_empty() or rec.is_empty() or not _a_portee(s, rec):
			_ouvert_par.erase(jid)


## Les portes s'ouvrent quand quelqu'un de l'équipe est tout près, et se referment quand
## la case est libre.
func _maj_portes() -> void:
	for rec in liste.values():
		var b := Batiments.infos(rec.type)
		if not b.has("ouverte"):
			continue
		var ouvrir := false
		var occupee := false
		var boite := Rect2(Vector2(rec.case) * Config.TAILLE_TUILE, Vector2.ONE * Config.TAILLE_TUILE).grow(Config.RAYON_JOUEUR + 1.0)
		for s in serveur.joueurs.values():
			if s.mort:
				continue
			if boite.has_point(s.pos):
				occupee = true
			if s.pos.distance_to(rec.pos) <= DISTANCE_PORTE and allie(s, rec.proprio):
				ouvrir = true
		if ouvrir != rec.ouvert and (ouvrir or not occupee):
			rec.ouvert = ouvrir
			serveur.recolte.changer_case(rec.case, int(b.ouverte if ouvrir else b.deco))


func _pieges(t: float) -> void:
	for s in serveur.joueurs.values():
		if s.mort:
			continue
		var c := Vector2i((s.pos / Config.TAILLE_TUILE).floor())
		var rec := a_la_case(c)
		if rec.is_empty() or rec.type != "piege" or allie(s, rec.proprio):
			continue
		var cle := "%d>%d" % [rec.id, s.id]
		if t < float(_pieges_prets.get(cle, 0.0)):
			continue
		var b := Batiments.infos(rec.type)
		_pieges_prets[cle] = t + float(b.recharge)
		serveur.combat.infliger(_source(rec, "le piège"), {"genre": "j", "s": s, "pos": s.pos}, float(b.degats))


## Source de dégâts « construction » pour Combat.infliger (comme un joueur sans bonus).
func _source(rec: Dictionary, nom: String) -> Dictionary:
	return {"id": -rec.id, "nom": "%s de %s" % [nom, rec.proprio], "proprio": rec.proprio, "equipe": equipe_de(rec.proprio),
		"stats": {"degats": 0.0}, "effets": {}, "caps": {"competence": {}}, "dernier_combat": 0.0, "pos": rec.pos}


func _tirer(rec: Dictionary, t: float) -> void:
	var b := Batiments.infos("tourelle")
	var portee := float(b.portee)
	var cible := {}
	var d_min := portee
	var depart: Vector2 = rec.pos + Vector2(0, -16)
	for s in serveur.joueurs.values():
		if s.mort or s.dieu or allie(s, rec.proprio) or serveur.combat.a_effet(s, "ombre"):
			continue
		var d: float = rec.pos.distance_to(s.pos)
		if d < d_min and not Regles.ligne_bloquee(serveur.monde, depart, s.pos + Vector2(0, -10)):
			d_min = d
			cible = s
	if cible.is_empty():
		rec["pret"] = t + 0.3
		return
	rec["pret"] = t + float(b.recharge)
	var degats := float(rec.get("degats", b.degats)) * (1.0 + float(rec.bonus))
	var source := _source(rec, "la tourelle")
	serveur.combat.tir_construction(source, depart, (cible.pos + Vector2(0, -10) - depart).normalized(), degats, portee + 40.0)
