class_name Atelier
extends RefCounted
## Étape 4 côté serveur : fabriquer (près des stations, avec les plans), poser les stations,
## s'équiper, retirer son équipement et l'améliorer en le mélangeant avec des ressources.

var serveur: Node


func _init(p_serveur: Node) -> void:
	serveur = p_serveur


## Stations posées près du joueur : nom -> vrai.
func stations_proches(pos: Vector2) -> Dictionary:
	return stations_autour(serveur.monde, pos)


static func stations_autour(monde: Monde, pos: Vector2) -> Dictionary:
	var r := {}
	var c0 := Vector2i((pos / Config.TAILLE_TUILE).floor())
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c := c0 + Vector2i(dx, dy)
			var d := monde.deco_en(c.x, c.y)
			for nom in Objets.DECOS_STATIONS:
				if Objets.DECOS_STATIONS[nom] == d and pos.distance_to(VueMonde.centre_case(c)) <= Equipement.DISTANCE_STATION:
					r[nom] = true
	return r


## Pourquoi on ne peut pas fabriquer cette recette ("" si c'est possible).
static func empechement(recette: Dictionary, inv: Array, stations: Dictionary) -> String:
	if recette.station != "" and not stations.has(recette.station):
		return "Il faut être près d'un(e) %s." % Equipement.STATIONS[recette.station]
	if recette.plan != "" and Objets.compter(inv, recette.plan) == 0:
		return "Il faut avoir le %s sur soi." % Objets.infos(recette.plan).nom
	for ing in recette.ingredients:
		if Objets.compter(inv, ing) < int(recette.ingredients[ing]):
			return "Il manque : %s." % Objets.infos(ing).nom
	return ""


func _dire(s: Dictionary, texte: String) -> void:
	Reseau.s_message.rpc_id(s.id, texte, "systeme")


func sur_fabriquer(s: Dictionary, id: String) -> void:
	var recette: Dictionary = Equipement.recettes().get(id, {})
	if recette.is_empty() or s.mort:
		return
	var raison := empechement(recette, s.inventaire, stations_proches(s.pos))
	if raison != "":
		_dire(s, raison)
		return
	var essai: Array = s.inventaire.duplicate(true)
	for ing in recette.ingredients:
		Objets.retirer(essai, ing, int(recette.ingredients[ing]))
	if Objets.ajouter(essai, recette.objet, int(recette.n)) > 0:
		_dire(s, "Inventaire plein.")
		return
	s.inventaire = essai
	serveur.recolte.envoyer_inventaire(s)
	serveur.combat.evenement("fabrication", {"id": s.id, "pos": s.pos, "objet": recette.objet})


func sur_equiper(s: Dictionary, case: int) -> void:
	if s.mort or case < 0 or case >= s.inventaire.size() or s.inventaire[case].is_empty():
		return
	var o: Dictionary = s.inventaire[case]
	var emplacement: String = Objets.infos(o.id).get("emplacement", "")
	if emplacement == "":
		return
	# Échange avec ce qui était porté à cet emplacement.
	var avant := Equipement.ensemble_complet(s.equipement)
	s.inventaire[case] = s.equipement[emplacement]
	s.equipement[emplacement] = o
	_apres_changement(s, avant)


func sur_retirer(s: Dictionary, emplacement: String) -> void:
	if s.mort or not s.equipement.has(emplacement) or s.equipement[emplacement].is_empty():
		return
	if Objets.ajouter_pile(s.inventaire, s.equipement[emplacement]) > 0:
		_dire(s, "Inventaire plein.")
		return
	s.equipement[emplacement] = {}
	_apres_changement(s, "")


func _apres_changement(s: Dictionary, ensemble_avant: String) -> void:
	serveur.combat.recalculer(s)
	serveur.recolte.envoyer_inventaire(s)
	serveur.annoncer_joueur(s) # l'apparence de l'arme change pour tout le monde
	var mat := Equipement.ensemble_complet(s.equipement)
	if mat != "" and mat != ensemble_avant:
		_dire(s, "Ensemble complet %s : %s" % [Equipement.MATERIAUX[mat].nom, Equipement.decrire(Equipement.MATERIAUX[mat].ensemble)])


## Pose une station sur la case libre devant le joueur.
func sur_poser(s: Dictionary, case: int) -> void:
	if s.mort or case < 0 or case >= s.inventaire.size() or s.inventaire[case].is_empty():
		return
	var id: String = s.inventaire[case].id
	if not Objets.DECOS_STATIONS.has(id):
		return
	var c := case_devant(s.pos, s.mvt.regard)
	var monde: Monde = serveur.monde
	if monde.deco_en(c.x, c.y) != Monde.Deco.AUCUN or monde.sol_en(c.x, c.y) in Monde.SOLS_BLOQUANTS:
		_dire(s, "Pas de place ici : mets-toi face à une case libre.")
		return
	for autre in serveur.joueurs.values():
		var boite := Rect2(Vector2(c) * Config.TAILLE_TUILE, Vector2.ONE * Config.TAILLE_TUILE).grow(Config.RAYON_JOUEUR)
		if boite.has_point(autre.pos):
			_dire(s, "Quelqu'un est sur cette case.")
			return
	Objets.retirer(s.inventaire, id, 1)
	serveur.recolte.changer_case(c, Objets.DECOS_STATIONS[id])
	serveur.recolte.envoyer_inventaire(s)


static func case_devant(pos: Vector2, regard: Vector2) -> Vector2i:
	var dir := regard
	if absf(dir.x) > absf(dir.y):
		dir = Vector2(signf(dir.x), 0)
	else:
		dir = Vector2(0, signf(dir.y) if dir.y != 0 else 1.0)
	return Vector2i(((pos + dir * Config.TAILLE_TUILE) / Config.TAILLE_TUILE).floor())


## Améliore un objet porté : il est mélangé avec des ressources pour donner un objet meilleur.
func sur_ameliorer(s: Dictionary, emplacement: String) -> void:
	var o: Dictionary = s.equipement.get(emplacement, {})
	if s.mort or o.is_empty():
		return
	var cout := Equipement.cout_amelioration(o)
	if cout.is_empty():
		_dire(s, "Cet objet est déjà au niveau maximum.")
		return
	var recette := {"station": Equipement.station_amelioration(o), "plan": Equipement.recettes()[o.id].plan, "ingredients": cout}
	var raison := empechement(recette, s.inventaire, stations_proches(s.pos))
	if raison != "":
		_dire(s, raison)
		return
	for ing in cout:
		Objets.retirer(s.inventaire, ing, int(cout[ing]))
	o["niv"] = int(o.get("niv", 0)) + 1
	_apres_changement(s, Equipement.ensemble_complet(s.equipement))
	_dire(s, "%s ! %s" % [Equipement.nom_objet(o), Equipement.decrire(Equipement.stats_objet(o))])
	serveur.combat.evenement("fabrication", {"id": s.id, "pos": s.pos, "objet": o.id})
