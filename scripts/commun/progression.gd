class_name Progression
extends RefCounted
## Étape 5 : niveau du personnage, expérience, points de caractéristiques et arbres de compétences.
## Le serveur s'en sert pour les règles, le jeu pour la fenêtre « Personnage ».
##
## Une progression (sauvegardée dans la fiche du joueur) :
##  {"niveau": int, "xp": int (dans le niveau en cours), "caracs": {carac: points},
##   "arbres": {role: {noeud: rang}}, "secondaire": role ou ""}
## L'arbre principal est celui du rôle joué. L'arbre secondaire (un seul) coûte 2 points par rang
## et ne donne accès qu'aux nœuds sans modification de capacité.

const NIVEAU_MAX := 30
const POINTS_CARACS_PAR_NIVEAU := 3
const POINTS_COMPETENCE_PAR_NIVEAU := 1
const COUT_SECONDAIRE := 2
const CARAC_MAX := 40
const PALIERS := [0, 3, 7] # rangs déjà pris dans l'arbre pour débloquer chaque palier
const PLAFONDS := {"recharge": 0.4, "esquive": 0.5, "vol_vie": 0.2, "batiment": 1.5, "tourelle": 1.5}

## Points d'amélioration classique : bonus par point.
const CARACS := {
	"vie": {"nom": "Vitalité", "stats": {"vie": 3.0}},
	"force": {"nom": "Force", "stats": {"degats": 0.015}},
	"defense": {"nom": "Défense", "stats": {"armure": 1.5}},
	"agilite": {"nom": "Agilité", "stats": {"vitesse": 0.005}},
	"adresse": {"nom": "Adresse", "stats": {"recharge": 0.0075}},
	"savoir": {"nom": "Savoir-faire", "stats": {"recolte": 0.02}},
}
const ORDRE_CARACS := ["vie", "force", "defense", "agilite", "adresse", "savoir"]

## Conditions d'équipement des nœuds (« si »).
const CONDITIONS := {
	"arme": "avec une arme",
	"outil": "avec un outil",
	"ensemble": "avec une armure complète du même matériau",
	"legere": "sans armure de métal (tissu ou rien)",
	"lourde": "avec au moins 3 pièces d'armure en métal",
}

## Arbres : rôle -> nœud -> {nom, palier (0 à 2), rangs, stats (par rang), cap (par rang), si}.
## cap : "capacite.parametre" -> multiplicateur par rang (+0.1 = +10 %) ; "+capacite.parametre" ajoute.
const ARBRES := {
	"guerrier": {
		"robustesse": {"nom": "Robustesse", "palier": 0, "rangs": 3, "stats": {"vie": 10}},
		"lame_affutee": {"nom": "Lame affûtée", "palier": 0, "rangs": 3, "cap": {"attaque.degats": 0.08}},
		"garde": {"nom": "Garde de fer", "palier": 0, "rangs": 2, "stats": {"armure": 4}, "si": "lourde"},
		"tourbillon_large": {"nom": "Grand tourbillon", "palier": 1, "rangs": 2, "cap": {"competence.rayon": 0.12, "competence.degats": 0.1}},
		"maitre_armes": {"nom": "Maître d'armes", "palier": 1, "rangs": 3, "stats": {"degats": 0.05}, "si": "arme"},
		"rage": {"nom": "Rage", "palier": 1, "rangs": 2, "stats": {"vol_vie": 0.04}},
		"tourbillon_rapide": {"nom": "Tourbillon incessant", "palier": 2, "rangs": 2, "cap": {"competence.recharge": -0.15}},
		"colosse": {"nom": "Colosse", "palier": 2, "rangs": 1, "stats": {"vie": 40, "armure": 6}, "si": "ensemble"},
	},
	"archer": {
		"corde": {"nom": "Corde tendue", "palier": 0, "rangs": 3, "cap": {"attaque.degats_max": 0.08}},
		"tir_rapide": {"nom": "Tir rapide", "palier": 0, "rangs": 2, "cap": {"attaque.charge": -0.12}},
		"pas_leger": {"nom": "Pas léger", "palier": 0, "rangs": 2, "stats": {"vitesse": 0.03}, "si": "legere"},
		"longue_vue": {"nom": "Longue vue", "palier": 1, "rangs": 2, "cap": {"attaque.portee_max": 0.1}},
		"pluie_dense": {"nom": "Pluie dense", "palier": 1, "rangs": 2, "cap": {"+competence.vagues": 1}},
		"archer_ne": {"nom": "Archer né", "palier": 1, "rangs": 3, "stats": {"degats": 0.04}, "si": "arme"},
		"pluie_etendue": {"nom": "Pluie étendue", "palier": 2, "rangs": 2, "cap": {"competence.rayon": 0.12, "competence.recharge": -0.1}},
		"faucon": {"nom": "Œil de faucon", "palier": 2, "rangs": 1, "cap": {"attaque.vitesse_proj_max": 0.2, "attaque.degats_max": 0.1}},
	},
	"mage": {
		"potions_fortes": {"nom": "Potions puissantes", "palier": 0, "rangs": 3, "cap": {"attaque.degats": 0.08}},
		"herboriste": {"nom": "Herboriste", "palier": 0, "rangs": 3, "cap": {"competence.soin": 0.1}},
		"lancer_precis": {"nom": "Lancer précis", "palier": 0, "rangs": 2, "cap": {"attaque.portee": 0.1, "competence.portee": 0.1}},
		"grande_fiole": {"nom": "Grande fiole", "palier": 1, "rangs": 2, "cap": {"attaque.rayon": 0.12, "competence.rayon": 0.1}},
		"infusion": {"nom": "Infusion", "palier": 1, "rangs": 2, "stats": {"regen": 1.0}},
		"alchimie": {"nom": "Alchimie rapide", "palier": 1, "rangs": 2, "stats": {"recharge": 0.06}},
		"urgence": {"nom": "Soin d'urgence", "palier": 2, "rangs": 2, "cap": {"competence.recharge": -0.15}},
		"robe": {"nom": "Robe enchantée", "palier": 2, "rangs": 1, "stats": {"vie": 30, "recharge": 0.05}, "si": "legere"},
	},
	"explorateur": {
		"jambes": {"nom": "Jambes de feu", "palier": 0, "rangs": 3, "stats": {"vitesse": 0.03}},
		"dague_vive": {"nom": "Dague vive", "palier": 0, "rangs": 3, "cap": {"attaque.degats": 0.08}},
		"reflexes": {"nom": "Réflexes", "palier": 0, "rangs": 2, "stats": {"esquive": 0.12}},
		"souffle": {"nom": "Second souffle", "palier": 1, "rangs": 2, "cap": {"competence.duree": 0.25}},
		"pisteur": {"nom": "Pisteur", "palier": 1, "rangs": 2, "stats": {"recolte": 0.08}},
		"voyageur": {"nom": "Voyageur léger", "palier": 1, "rangs": 3, "stats": {"vitesse": 0.02, "armure": 2}, "si": "legere"},
		"sprint_feu": {"nom": "Sprint de feu", "palier": 2, "rangs": 2, "cap": {"competence.bonus": 0.15, "competence.recharge": -0.1}},
		"insaisissable": {"nom": "Insaisissable", "palier": 2, "rangs": 1, "stats": {"esquive": 0.2, "vitesse": 0.05}},
	},
	"paladin": {
		"foi": {"nom": "Foi", "palier": 0, "rangs": 3, "stats": {"vie": 12}},
		"marteau_beni": {"nom": "Marteau béni", "palier": 0, "rangs": 3, "cap": {"attaque.degats": 0.08}},
		"armure_sacree": {"nom": "Armure sacrée", "palier": 0, "rangs": 2, "stats": {"armure": 5}, "si": "lourde"},
		"bouclier_large": {"nom": "Bouclier étendu", "palier": 1, "rangs": 2, "cap": {"competence.rayon": 0.15}},
		"lumiere": {"nom": "Lumière", "palier": 1, "rangs": 2, "cap": {"competence.soin": 0.25}},
		"penitence": {"nom": "Pénitence", "palier": 1, "rangs": 2, "stats": {"vol_vie": 0.04}},
		"rempart": {"nom": "Rempart", "palier": 2, "rangs": 2, "cap": {"competence.duree": 0.2, "competence.recharge": -0.12}},
		"croise": {"nom": "Croisé", "palier": 2, "rangs": 1, "stats": {"vie": 40, "degats": 0.08}, "si": "ensemble"},
	},
	"assassin": {
		"poison": {"nom": "Lames empoisonnées", "palier": 0, "rangs": 3, "cap": {"attaque.degats": 0.08}},
		"dans_le_dos": {"nom": "Dans le dos", "palier": 0, "rangs": 2, "cap": {"attaque.dos": 0.15}},
		"pas_feutre": {"nom": "Pas feutré", "palier": 0, "rangs": 2, "stats": {"vitesse": 0.03}, "si": "legere"},
		"ombre_longue": {"nom": "Ombre longue", "palier": 1, "rangs": 2, "cap": {"competence.duree": 0.25}},
		"saignee": {"nom": "Saignée", "palier": 1, "rangs": 2, "stats": {"vol_vie": 0.05}},
		"esquive_ombre": {"nom": "Danse des ombres", "palier": 1, "rangs": 2, "stats": {"esquive": 0.12}},
		"frappe_ombre": {"nom": "Frappe de l'ombre", "palier": 2, "rangs": 2, "cap": {"competence.bonus": 0.25}},
		"lames_jumelles": {"nom": "Lames jumelles", "palier": 2, "rangs": 1, "cap": {"attaque.recharge": -0.15}, "stats": {"degats": 0.05}, "si": "arme"},
	},
	"mineur": {
		"bras": {"nom": "Bras de fer", "palier": 0, "rangs": 3, "stats": {"recolte": 0.08}},
		"pioche_lourde": {"nom": "Pioche lourde", "palier": 0, "rangs": 3, "cap": {"attaque.degats": 0.08}},
		"peau_pierre": {"nom": "Peau de pierre", "palier": 0, "rangs": 2, "stats": {"armure": 3}},
		"ruee_longue": {"nom": "Ruée prolongée", "palier": 1, "rangs": 2, "cap": {"competence.duree": 0.25}},
		"prospecteur": {"nom": "Prospecteur", "palier": 1, "rangs": 2, "stats": {"recolte": 0.1}, "si": "outil"},
		"endurance": {"nom": "Endurance", "palier": 1, "rangs": 2, "stats": {"vie": 15}},
		"ruee_frequente": {"nom": "Ruée fréquente", "palier": 2, "rangs": 2, "cap": {"competence.recharge": -0.15}},
		"maitre_mineur": {"nom": "Maître mineur", "palier": 2, "rangs": 1, "stats": {"recolte": 0.2, "vie": 20}, "si": "ensemble"},
	},
	"ingenieur": {
		"cle_lourde": {"nom": "Clé lourde", "palier": 0, "rangs": 3, "cap": {"attaque.degats": 0.08}},
		"bricoleur": {"nom": "Bricoleur", "palier": 0, "rangs": 2, "cap": {"attaque.repare": 0.25}},
		"batisseur": {"nom": "Bâtisseur", "palier": 0, "rangs": 3, "stats": {"batiment": 0.1}},
		"tourelle_solide": {"nom": "Tourelle endurante", "palier": 1, "rangs": 2, "cap": {"competence.duree": 0.25}},
		"canons": {"nom": "Canons rayés", "palier": 1, "rangs": 2, "stats": {"tourelle": 0.15}},
		"casque": {"nom": "Casque de chantier", "palier": 1, "rangs": 2, "stats": {"armure": 3, "vie": 8}},
		"deploiement": {"nom": "Déploiement rapide", "palier": 2, "rangs": 2, "cap": {"competence.recharge": -0.15, "competence.degats": 0.15}},
		"maitre_ingenieur": {"nom": "Maître ingénieur", "palier": 2, "rangs": 1, "stats": {"batiment": 0.2, "tourelle": 0.2}, "si": "outil"},
	},
}

const NOMS_PARAMETRES := {"degats": "dégâts", "degats_max": "dégâts max", "portee": "portée", "portee_max": "portée max",
	"rayon": "zone", "recharge": "recharge", "duree": "durée", "soin": "soin", "bonus": "bonus", "dos": "bonus dans le dos",
	"vagues": "vagues", "charge": "temps de charge", "vitesse_proj_max": "vitesse de la flèche", "repare": "réparation"}


# ------------------------------------------------------------------ Niveaux

## Expérience à gagner pour passer du niveau n au niveau n + 1.
static func xp_pour(n: int) -> int:
	return 60 + 40 * n + 4 * n * n


static func vierge() -> Dictionary:
	var caracs := {}
	for c in ORDRE_CARACS:
		caracs[c] = 0
	return {"niveau": 1, "xp": 0, "caracs": caracs, "arbres": {}, "secondaire": ""}


## Relit une progression venue de la sauvegarde (JSON : nombres en float).
static func nettoyer(brut) -> Dictionary:
	var p := vierge()
	if not brut is Dictionary:
		return p
	p.niveau = clampi(int(brut.get("niveau", 1)), 1, NIVEAU_MAX)
	p.xp = maxi(0, int(brut.get("xp", 0)))
	var caracs = brut.get("caracs", {})
	if caracs is Dictionary:
		for c in ORDRE_CARACS:
			p.caracs[c] = clampi(int(caracs.get(c, 0)), 0, CARAC_MAX)
	var arbres = brut.get("arbres", {})
	if arbres is Dictionary:
		for role in arbres:
			if not ARBRES.has(role) or not arbres[role] is Dictionary:
				continue
			var a := {}
			for noeud in arbres[role]:
				if ARBRES[role].has(noeud):
					var rang := clampi(int(arbres[role][noeud]), 0, int(ARBRES[role][noeud].rangs))
					if rang > 0:
						a[noeud] = rang
			if not a.is_empty():
				p.arbres[role] = a
	var sec := str(brut.get("secondaire", ""))
	p.secondaire = sec if ARBRES.has(sec) else ""
	# Points dépensés au-delà de ce que le niveau permet (sauvegarde modifiée) : tout est rendu.
	if points_caracs(p) < 0:
		for c in ORDRE_CARACS:
			p.caracs[c] = 0
	return p


static func points_caracs(p: Dictionary) -> int:
	var depenses := 0
	for c in p.caracs:
		depenses += int(p.caracs[c])
	return (int(p.niveau) - 1) * POINTS_CARACS_PAR_NIVEAU - depenses


## Points de compétence restants quand on joue ce rôle (arbre principal = rôle joué).
static func points_competence(p: Dictionary, role: String) -> int:
	var depenses := 0
	for arbre in p.arbres:
		var cout := 1 if arbre == role else COUT_SECONDAIRE
		for noeud in p.arbres[arbre]:
			depenses += int(p.arbres[arbre][noeud]) * cout
	return (int(p.niveau) - 1) * POINTS_COMPETENCE_PAR_NIVEAU - depenses


static func rangs_dans(p: Dictionary, arbre: String) -> int:
	var n := 0
	for noeud in p.arbres.get(arbre, {}):
		n += int(p.arbres[arbre][noeud])
	return n


static func rang(p: Dictionary, arbre: String, noeud: String) -> int:
	return int(p.arbres.get(arbre, {}).get(noeud, 0))


## Arbre utilisable par ce rôle : le sien (principal) ou le secondaire choisi.
static func arbre_actif(p: Dictionary, role: String, arbre: String) -> bool:
	return arbre == role or (arbre != "" and arbre == p.secondaire)


## Raison pour laquelle on ne peut pas prendre un rang de ce nœud, ou "".
static func empechement_noeud(p: Dictionary, role: String, arbre: String, noeud: String) -> String:
	if not ARBRES.has(arbre) or not ARBRES[arbre].has(noeud):
		return "Compétence inconnue."
	var n: Dictionary = ARBRES[arbre][noeud]
	var principal := arbre == role
	if not principal:
		if p.secondaire != "" and p.secondaire != arbre:
			return "Tu as déjà un arbre secondaire (%s)." % Roles.donnees(p.secondaire).nom
		if n.has("cap"):
			return "Seulement dans l'arbre principal : elle change une capacité de ce rôle."
	if rang(p, arbre, noeud) >= int(n.rangs):
		return "Rang maximum."
	if rangs_dans(p, arbre) < PALIERS[int(n.palier)]:
		return "Il faut %d rangs dans cet arbre pour ce palier." % PALIERS[int(n.palier)]
	if points_competence(p, role) < (1 if principal else COUT_SECONDAIRE):
		return "Pas assez de points de compétence%s." % ("" if principal else " (2 par rang dans l'arbre secondaire)")
	return ""


## Prend un rang (suppose qu'il n'y a pas d'empêchement).
static func prendre(p: Dictionary, role: String, arbre: String, noeud: String) -> void:
	if arbre != role:
		p.secondaire = arbre
	if not p.arbres.has(arbre):
		p.arbres[arbre] = {}
	p.arbres[arbre][noeud] = rang(p, arbre, noeud) + 1


## Changement de rôle : les points de compétence sont rendus (les caractéristiques restent).
static func oublier_competences(p: Dictionary) -> void:
	p.arbres = {}
	p.secondaire = ""


static func oublier_tout(p: Dictionary) -> void:
	oublier_competences(p)
	for c in ORDRE_CARACS:
		p.caracs[c] = 0


## Coût pour tout oublier (compétences et caractéristiques) : herbes médicinales.
static func cout_oubli(p: Dictionary) -> Dictionary:
	return {"herbe": 3 * int(p.niveau)}


# ------------------------------------------------------------------ Effets

## Condition d'équipement remplie ?
static func condition(si: String, equipement: Dictionary) -> bool:
	match si:
		"":
			return true
		"arme", "outil":
			return not equipement.get(si, {}).is_empty()
		"ensemble":
			return Equipement.ensemble_complet(equipement) != ""
		"legere", "lourde":
			var metal := 0
			for piece in Equipement.PIECES_ARMURE:
				var o: Dictionary = equipement.get(piece, {})
				if not o.is_empty() and Equipement.objets()[o.id].materiau != "tissu":
					metal += 1
			return metal == 0 if si == "legere" else metal >= 3
	return false


## Bonus de la progression (caractéristiques + nœuds des arbres actifs) avec cet équipement.
static func stats(p: Dictionary, role: String, equipement: Dictionary) -> Dictionary:
	var total := {}
	for c in p.caracs:
		for cle in CARACS[c].stats:
			total[cle] = total.get(cle, 0.0) + CARACS[c].stats[cle] * int(p.caracs[c])
	for arbre in p.arbres:
		if not arbre_actif(p, role, arbre):
			continue
		for noeud in p.arbres[arbre]:
			var n: Dictionary = ARBRES[arbre][noeud]
			if not condition(n.get("si", ""), equipement):
				continue
			for cle in n.get("stats", {}):
				total[cle] = total.get(cle, 0.0) + float(n.stats[cle]) * int(p.arbres[arbre][noeud])
	for cle in PLAFONDS:
		if total.has(cle):
			total[cle] = minf(total[cle], PLAFONDS[cle])
	return total


## Attaque et compétence du rôle, modifiées par l'arbre principal et la réduction de recharge.
static func capacites(p: Dictionary, role: String, recharge := 0.0) -> Dictionary:
	var d := Roles.donnees(role)
	var caps := {"attaque": d.attaque.duplicate(), "competence": d.competence.duplicate()}
	for noeud in p.arbres.get(role, {}):
		var n: Dictionary = ARBRES[role][noeud]
		var r := int(p.arbres[role][noeud])
		for cle in n.get("cap", {}):
			var ajout: bool = cle.begins_with("+")
			var morceaux: PackedStringArray = cle.trim_prefix("+").split(".")
			var cap: Dictionary = caps[morceaux[0]]
			if not cap.has(morceaux[1]):
				continue
			if ajout:
				cap[morceaux[1]] = cap[morceaux[1]] + n.cap[cle] * r
			else:
				cap[morceaux[1]] = cap[morceaux[1]] * (1.0 + float(n.cap[cle]) * r)
	for g in caps:
		caps[g].recharge = float(caps[g].recharge) * (1.0 - recharge)
	return caps


## Ajoute les bonus b à a (stats de l'équipement + progression).
static func cumuler(a: Dictionary, b: Dictionary) -> Dictionary:
	var r := a.duplicate()
	for cle in b:
		r[cle] = r.get(cle, 0.0) + b[cle]
	for cle in PLAFONDS:
		if r.has(cle):
			r[cle] = minf(r[cle], PLAFONDS[cle])
	return r


static func decrire_stats(stats: Dictionary) -> String:
	var parts := []
	var base := Equipement.decrire(stats)
	if base != "Aucun bonus":
		parts.append(base)
	if stats.get("recharge", 0.0) > 0.0: parts.append("Recharges -%d %%" % int(round(stats.recharge * 100)))
	if stats.get("esquive", 0.0) > 0.0: parts.append("Recharge de l'esquive -%d %%" % int(round(stats.esquive * 100)))
	if stats.get("vol_vie", 0.0) > 0.0: parts.append("Vol de vie %d %%" % int(round(stats.vol_vie * 100)))
	if stats.get("regen", 0.0) > 0.0: parts.append("Régénération %s vie/s hors combat" % str(snappedf(stats.regen, 0.1)))
	if stats.get("batiment", 0.0) > 0.0: parts.append("Vie des constructions posées +%d %%" % int(round(stats.batiment * 100)))
	if stats.get("tourelle", 0.0) > 0.0: parts.append("Dégâts des tourelles posées +%d %%" % int(round(stats.tourelle * 100)))
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "Aucun bonus"


## Description d'un nœud (effet par rang).
static func decrire_noeud(role: String, noeud: String) -> String:
	var n: Dictionary = ARBRES[role][noeud]
	var parts := []
	if n.has("stats"):
		parts.append(decrire_stats(n.stats))
	var d := Roles.donnees(role)
	for cle in n.get("cap", {}):
		var ajout: bool = cle.begins_with("+")
		var morceaux: PackedStringArray = cle.trim_prefix("+").split(".")
		var nom_cap: String = d[morceaux[0]].nom
		var param: String = NOMS_PARAMETRES.get(morceaux[1], morceaux[1])
		var v: float = n.cap[cle]
		if ajout:
			parts.append("%s : +%d %s" % [nom_cap, int(v), param])
		else:
			parts.append("%s : %s %+d %%" % [nom_cap, param, int(round(v * 100))])
	var texte := "Par rang : " + ", ".join(PackedStringArray(parts)) if int(n.rangs) > 1 else ", ".join(PackedStringArray(parts))
	if n.has("si"):
		texte += " (%s)" % CONDITIONS[n.si]
	return texte


# ------------------------------------------------------------------ Expérience

## Expérience d'une récolte selon la rareté de l'objet obtenu.
static func xp_recolte(objet: String) -> int:
	return [2, 5, 9, 15, 25][clampi(int(Objets.infos(objet).rarete), 0, 4)]


static func xp_fabrication(objet: String) -> int:
	var info := Objets.infos(objet)
	if objet.begins_with("lingot_"):
		return 2 + 2 * int(info.rarete)
	return 4 + 8 * int(info.rarete)


static func xp_coffre(danger: int) -> int:
	return 25 + 15 * danger


## Vaincre un joueur : plus il est haut niveau par rapport à soi, plus ça rapporte.
static func xp_victoire(niveau: int, niveau_victime: int) -> int:
	var base := 30 + 10 * niveau_victime
	return int(round(base * clampf(1.0 + 0.1 * (niveau_victime - niveau), 0.3, 2.5)))
