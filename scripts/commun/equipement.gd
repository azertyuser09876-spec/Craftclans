class_name Equipement
extends RefCounted
## Étape 4 : stations de craft, lingots, plans, armures par pièce avec bonus d'ensemble,
## armes, outils et amélioration. Tout est déterministe : aucune valeur tirée au hasard.
##
## Les objets d'équipement sont générés ici à partir des matériaux (OBJETS), ainsi que
## toutes les recettes (RECETTES). Objets.infos() les connaît comme les ressources.

const EMPLACEMENTS := ["tete", "torse", "jambes", "pieds", "arme", "outil"]
const PIECES_ARMURE := ["tete", "torse", "jambes", "pieds"]
const NOMS_EMPLACEMENTS := {"tete": "Tête", "torse": "Torse", "jambes": "Jambes", "pieds": "Pieds", "arme": "Arme", "outil": "Outil"}
const NOMS_PIECES := {"tete": "Coiffe", "torse": "Plastron", "jambes": "Jambières", "pieds": "Bottes", "arme": "Lame", "outil": "Pioche"}
const QUANTITES := {"tete": 3, "torse": 5, "jambes": 4, "pieds": 2, "arme": 3, "outil": 3}
const NIVEAU_MAX := 3
const BONUS_NIVEAU := 0.25 # +25 % des caractéristiques de l'objet par niveau d'amélioration
const DISTANCE_STATION := 96.0 # pixels : il faut être à côté de la station pour l'utiliser

## Matériaux d'armure. piece : bonus de chaque pièce ; ensemble : bonus en plus avec les 4 pièces.
## matiere : ressource principale ; extra : ingrédient en plus par objet.
const MATERIAUX := {
	"tissu": {"nom": "en tissu", "matiere": "fibre", "fois": 2, "station": "etabli", "plan": "", "rarete": 0,
		"couleur": Color8(200, 190, 150), "piece": {"armure": 1, "vitesse": 0.03}, "ensemble": {"vitesse": 0.05}},
	"cuivre": {"nom": "de cuivre", "matiere": "lingot_cuivre", "station": "enclume", "plan": "", "rarete": 1,
		"couleur": Color8(206, 118, 60), "piece": {"armure": 4}, "ensemble": {"vie": 15}},
	"fer": {"nom": "de fer", "matiere": "lingot_fer", "station": "enclume", "plan": "plan_fer", "rarete": 1,
		"couleur": Color8(176, 176, 186), "piece": {"armure": 7}, "ensemble": {"armure": 8, "vie": 20}},
	"or": {"nom": "d'or", "matiere": "lingot_or", "station": "enclume", "plan": "plan_or", "rarete": 2,
		"couleur": Color8(236, 190, 50), "piece": {"armure": 5, "degats": 0.05}, "ensemble": {"degats": 0.10}},
	"mithril": {"nom": "de mithril", "matiere": "lingot_mithril", "station": "enclume", "plan": "plan_mithril", "rarete": 3,
		"couleur": Color8(110, 200, 220), "piece": {"armure": 10, "vitesse": 0.03}, "ensemble": {"vitesse": 0.08, "armure": 10}},
	"obsidienne": {"nom": "d'obsidienne", "matiere": "obsidienne", "extra": "lingot_fer", "station": "enclume", "plan": "plan_obsidienne", "rarete": 3,
		"couleur": Color8(80, 50, 110), "piece": {"armure": 9, "degats": 0.07}, "ensemble": {"degats": 0.15}},
	"cristal": {"nom": "de cristal", "matiere": "cristal", "extra": "lingot_mithril", "station": "enclume", "plan": "plan_cristal", "rarete": 4,
		"couleur": Color8(200, 130, 255), "piece": {"armure": 12, "vie": 15}, "ensemble": {"vie": 60, "armure": 10}},
}

## Armes : bonus de dégâts de toutes les attaques et compétences du rôle.
const ARMES := {
	"bois": {"nom": "de bois", "matiere": "bois", "fois": 2, "station": "etabli", "plan": "", "rarete": 0, "couleur": Color8(150, 100, 56), "degats": 0.05},
	"cuivre": {"degats": 0.10}, "fer": {"degats": 0.18}, "or": {"degats": 0.24},
	"mithril": {"degats": 0.32}, "obsidienne": {"degats": 0.38}, "cristal": {"degats": 0.45},
}

## Outils : récolte plus rapide (bois, pierre, minerais…).
const OUTILS := {
	"pierre": {"nom": "de pierre", "matiere": "pierre", "station": "etabli", "plan": "", "rarete": 0, "couleur": Color8(140, 140, 150), "recolte": 0.20},
	"cuivre": {"recolte": 0.40}, "fer": {"recolte": 0.70}, "mithril": {"recolte": 1.20},
}

## Autres objets de l'étape 4 (s'ajoutent à Objets.LISTE).
const AUTRES := {
	"lingot_cuivre": {"nom": "Lingot de cuivre", "pile": 40, "rarete": 1, "description": "Fondu au fourneau."},
	"lingot_fer": {"nom": "Lingot de fer", "pile": 40, "rarete": 1, "description": "Fondu au fourneau."},
	"lingot_or": {"nom": "Lingot d'or", "pile": 30, "rarete": 2, "description": "Fondu au fourneau."},
	"lingot_mithril": {"nom": "Lingot de mithril", "pile": 20, "rarete": 3, "description": "Fondu au fourneau."},
	"etabli": {"nom": "Établi", "pile": 5, "rarete": 0, "station": true, "description": "À poser par terre. Bois, tissu, outils de pierre, fourneau, enclume."},
	"fourneau": {"nom": "Fourneau", "pile": 5, "rarete": 0, "station": true, "description": "À poser par terre. Fond les minerais en lingots."},
	"enclume": {"nom": "Enclume", "pile": 5, "rarete": 1, "station": true, "description": "À poser par terre. Forge les armures, armes et outils en métal, et les améliore."},
	"plan_fer": {"nom": "Plan : fer", "pile": 1, "rarete": 1, "plan": true, "description": "Permet de forger l'équipement en fer. Trouvé dans les coffres anciens près du départ."},
	"plan_or": {"nom": "Plan : or", "pile": 1, "rarete": 2, "plan": true, "description": "Permet de forger l'équipement en or. Coffres anciens, danger 2 à 3."},
	"plan_mithril": {"nom": "Plan : mithril", "pile": 1, "rarete": 3, "plan": true, "description": "Permet de forger l'équipement en mithril. Coffres anciens, danger 4 à 5."},
	"plan_obsidienne": {"nom": "Plan : obsidienne", "pile": 1, "rarete": 3, "plan": true, "description": "Permet de forger l'équipement en obsidienne. Coffres anciens, danger 6 à 7."},
	"plan_cristal": {"nom": "Plan : cristal", "pile": 1, "rarete": 4, "plan": true, "description": "Permet de forger l'équipement en cristal. Coffres anciens, danger 8 et plus."},
}

const STATIONS := {"etabli": "Établi", "fourneau": "Fourneau", "enclume": "Enclume"}

static var _objets := {}
static var _recettes := {}


## Tous les objets d'équipement et les objets ci-dessus : id -> infos.
static func objets() -> Dictionary:
	if _objets.is_empty():
		_construire()
	return _objets


## Toutes les recettes : id (= objet fabriqué) -> {objet, n, ingredients, station, plan, categorie}.
static func recettes() -> Dictionary:
	if _recettes.is_empty():
		_construire()
	return _recettes


static func _materiau(table: Dictionary, mat: String) -> Dictionary:
	# Les armes et outils en métal reprennent la matière, la station et le plan des armures.
	var m: Dictionary = MATERIAUX.get(mat, {}).duplicate()
	m.merge(table[mat], true)
	return m


static func _construire() -> void:
	for id in AUTRES:
		_objets[id] = AUTRES[id]
	for mat in MATERIAUX:
		var m: Dictionary = MATERIAUX[mat]
		for piece in PIECES_ARMURE:
			_ajouter_equipement("%s_%s" % [piece, mat], piece, mat, m, m.piece)
	for mat in ARMES:
		var m := _materiau(ARMES, mat)
		_ajouter_equipement("arme_" + mat, "arme", mat, m, {"degats": m.degats})
	for mat in OUTILS:
		var m := _materiau(OUTILS, mat)
		_ajouter_equipement("outil_" + mat, "outil", mat, m, {"recolte": m.recolte})
	# Stations et lingots
	_recette("etabli", 1, {"bois": 8}, "", "station")
	_recette("fourneau", 1, {"pierre": 12, "bois": 4}, "etabli", "station")
	_recette("enclume", 1, {"lingot_fer": 5, "pierre": 6}, "etabli", "station")
	_recette("lingot_cuivre", 1, {"cuivre": 2, "bois": 1}, "fourneau", "lingot")
	_recette("lingot_fer", 1, {"fer": 2, "bois": 1}, "fourneau", "lingot")
	_recette("lingot_or", 1, {"or": 2, "bois": 1}, "fourneau", "lingot")
	_recette("lingot_mithril", 1, {"mithril": 2, "bois": 2}, "fourneau", "lingot")
	# Étape 6 : constructions
	for id in Batiments.LISTE:
		var b: Dictionary = Batiments.LISTE[id]
		if b.has("ingredients"):
			_recette(id, 1, b.ingredients, b.station, "construction")


static func _ajouter_equipement(id: String, emplacement: String, mat: String, m: Dictionary, stats: Dictionary) -> void:
	_objets[id] = {"nom": "%s %s" % [NOMS_PIECES[emplacement], m.nom], "pile": 1, "rarete": int(m.rarete),
		"emplacement": emplacement, "materiau": mat, "stats": stats, "couleur": m.couleur,
		"description": "%s. %s" % [NOMS_EMPLACEMENTS[emplacement], decrire(stats)]}
	var ingredients := {m.matiere: int(QUANTITES[emplacement]) * int(m.get("fois", 1))}
	if m.has("extra"):
		ingredients[m.extra] = 1
	if emplacement in ["arme", "outil"] and m.matiere != "bois":
		ingredients["bois"] = ingredients.get("bois", 0) + 1
	_recette(id, 1, ingredients, m.station, emplacement, m.plan)


static func _recette(id: String, n: int, ingredients: Dictionary, station: String, categorie: String, plan := "") -> void:
	_recettes[id] = {"objet": id, "n": n, "ingredients": ingredients, "station": station, "plan": plan, "categorie": categorie}


# ------------------------------------------------------------------ Caractéristiques

static func decrire(stats: Dictionary) -> String:
	var parts := []
	if stats.get("armure", 0) != 0: parts.append("Armure +%d" % int(round(stats.armure)))
	if stats.get("vie", 0) != 0: parts.append("Vie +%d" % int(round(stats.vie)))
	if stats.get("degats", 0.0) != 0.0: parts.append("Dégâts +%d %%" % int(round(stats.degats * 100)))
	if stats.get("vitesse", 0.0) != 0.0: parts.append("Vitesse +%d %%" % int(round(stats.vitesse * 100)))
	if stats.get("recolte", 0.0) != 0.0: parts.append("Récolte +%d %%" % int(round(stats.recolte * 100)))
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "Aucun bonus"


## Caractéristiques d'un objet porté, avec son niveau d'amélioration.
static func stats_objet(o: Dictionary) -> Dictionary:
	var info: Dictionary = objets().get(o.get("id", ""), {})
	var r := {}
	var mult := 1.0 + BONUS_NIVEAU * int(o.get("niv", 0))
	for cle in info.get("stats", {}):
		r[cle] = info.stats[cle] * mult
	return r


## Total des bonus de l'équipement porté (emplacement -> objet), bonus d'ensemble compris.
static func stats(equipement: Dictionary) -> Dictionary:
	var total := {"armure": 0.0, "vie": 0.0, "degats": 0.0, "vitesse": 0.0, "recolte": 0.0}
	var materiaux := {}
	for emplacement in equipement:
		var o: Dictionary = equipement[emplacement]
		if o.is_empty():
			continue
		var s := stats_objet(o)
		for cle in s:
			total[cle] += s[cle]
		if emplacement in PIECES_ARMURE:
			var mat: String = objets()[o.id].materiau
			materiaux[mat] = materiaux.get(mat, 0) + 1
	for mat in materiaux:
		if materiaux[mat] == PIECES_ARMURE.size():
			for cle in MATERIAUX[mat].ensemble:
				total[cle] += MATERIAUX[mat].ensemble[cle]
	return total


## Ensemble complet porté (nom du matériau) ou "".
static func ensemble_complet(equipement: Dictionary) -> String:
	var mat := ""
	for piece in PIECES_ARMURE:
		var o: Dictionary = equipement.get(piece, {})
		if o.is_empty():
			return ""
		var m: String = objets()[o.id].materiau
		if mat != "" and m != mat:
			return ""
		mat = m
	return mat


static func equipement_vide() -> Dictionary:
	var e := {}
	for emplacement in EMPLACEMENTS:
		e[emplacement] = {}
	return e


# ------------------------------------------------------------------ Amélioration

## Coût pour passer un objet au niveau suivant (mélange de l'objet et de ressources), ou {} si impossible.
static func cout_amelioration(o: Dictionary) -> Dictionary:
	var info: Dictionary = objets().get(o.get("id", ""), {})
	var niv := int(o.get("niv", 0))
	if not info.has("emplacement") or niv >= NIVEAU_MAX:
		return {}
	var r: Dictionary = recettes()[o.id]
	var cout := {}
	for ing in r.ingredients:
		if ing != "bois" or r.ingredients.size() == 1:
			cout[ing] = int(r.ingredients[ing]) * (niv + 1)
	if niv + 1 == NIVEAU_MAX and int(info.rarete) >= 1:
		cout["cristal"] = cout.get("cristal", 0) + 1 # le dernier niveau demande un cristal
	return cout


static func station_amelioration(o: Dictionary) -> String:
	return recettes()[o.id].station


# ------------------------------------------------------------------ Plans

## Plan trouvé dans un coffre ancien selon le danger de l'endroit.
static func plan_pour_danger(danger: int) -> String:
	if danger >= 8: return "plan_cristal"
	if danger >= 6: return "plan_obsidienne"
	if danger >= 4: return "plan_mithril"
	if danger >= 2: return "plan_or"
	return "plan_fer"


## Nom affiché d'un objet, avec son niveau (« Plastron de fer +2 »).
static func nom_objet(o: Dictionary) -> String:
	var nom: String = Objets.infos(o.get("id", "")).nom
	var niv := int(o.get("niv", 0))
	return nom if niv == 0 else "%s +%d" % [nom, niv]
