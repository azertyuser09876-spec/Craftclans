class_name Objets
extends RefCounted
## Objets du jeu (étape 3 : ressources) et ce que donne chaque décor quand on le récolte.
## Le serveur s'en sert pour les règles, le jeu pour l'affichage (icônes, noms, durées).

const TAILLE_INVENTAIRE := 24
const PORTEE_RECOLTE := 46.0 # distance max (pixels) entre les pieds et le centre de la case
const PORTEE_RAMASSER := 44.0

## rarete : 0 commun, 1 peu commun, 2 rare, 3 très rare, 4 légendaire
## lie : l'objet reste avec son porteur à sa mort (aucun pour l'instant, prévu par les règles)
const LISTE := {
	"bois": {"nom": "Bois", "pile": 50, "rarete": 0, "description": "Coupé sur les arbres."},
	"fibre": {"nom": "Fibre", "pile": 50, "rarete": 0, "description": "Tirée des buissons, roseaux et cactus."},
	"herbe": {"nom": "Herbe médicinale", "pile": 50, "rarete": 0, "description": "Cueillie dans les fleurs."},
	"os": {"nom": "Os", "pile": 50, "rarete": 0, "description": "Trouvé dans le désert."},
	"pierre": {"nom": "Pierre", "pile": 50, "rarete": 0, "description": "Extraite des rochers."},
	"cuivre": {"nom": "Minerai de cuivre", "pile": 40, "rarete": 1, "description": "Filons partout, même près du départ."},
	"fer": {"nom": "Minerai de fer", "pile": 40, "rarete": 1, "description": "Filons à partir du danger 2."},
	"or": {"nom": "Minerai d'or", "pile": 30, "rarete": 2, "description": "Filons à partir du danger 4, surtout dans les déserts et les montagnes."},
	"obsidienne": {"nom": "Obsidienne", "pile": 30, "rarete": 2, "description": "Rochers noirs des terres brûlées."},
	"mithril": {"nom": "Mithril", "pile": 20, "rarete": 3, "description": "Filons à partir du danger 6, surtout dans les montagnes et la toundra."},
	"cristal": {"nom": "Cristal", "pile": 20, "rarete": 4, "description": "Très rare, à partir du danger 8."},
}

const COULEURS_RARETE := [Color(0.85, 0.85, 0.85), Color(0.45, 0.9, 0.45), Color(0.4, 0.65, 1.0),
	Color(0.75, 0.45, 1.0), Color(1.0, 0.65, 0.2)]

## Récolte par décor : objet obtenu, nombre de récoltes avant que le décor disparaisse,
## secondes par récolte (sans bonus), minerai (le mineur va plus vite), repousse (minutes).
const RECOLTE := {
	Monde.Deco.ARBRE: {"objet": "bois", "coups": 4, "temps": 1.0, "minerai": false, "repousse": 15, "verbe": "Couper"},
	Monde.Deco.SAPIN: {"objet": "bois", "coups": 4, "temps": 1.0, "minerai": false, "repousse": 15, "verbe": "Couper"},
	Monde.Deco.SAPIN_NEIGE: {"objet": "bois", "coups": 4, "temps": 1.1, "minerai": false, "repousse": 15, "verbe": "Couper"},
	Monde.Deco.ARBRE_MORT: {"objet": "bois", "coups": 2, "temps": 0.9, "minerai": false, "repousse": 20, "verbe": "Couper"},
	Monde.Deco.BUISSON: {"objet": "fibre", "coups": 2, "temps": 0.6, "minerai": false, "repousse": 8, "verbe": "Cueillir"},
	Monde.Deco.ROSEAUX: {"objet": "fibre", "coups": 2, "temps": 0.5, "minerai": false, "repousse": 8, "verbe": "Cueillir"},
	Monde.Deco.CACTUS: {"objet": "fibre", "coups": 2, "temps": 0.8, "minerai": false, "repousse": 12, "verbe": "Couper"},
	Monde.Deco.FLEURS: {"objet": "herbe", "coups": 1, "temps": 0.4, "minerai": false, "repousse": 6, "verbe": "Cueillir"},
	Monde.Deco.OS: {"objet": "os", "coups": 1, "temps": 0.4, "minerai": false, "repousse": 20, "verbe": "Ramasser"},
	Monde.Deco.ROCHER: {"objet": "pierre", "coups": 4, "temps": 1.4, "minerai": true, "repousse": 20, "verbe": "Miner"},
	Monde.Deco.ROCHER_NOIR: {"objet": "obsidienne", "coups": 2, "temps": 3.0, "minerai": true, "repousse": 30, "verbe": "Miner"},
	Monde.Deco.FILON_CUIVRE: {"objet": "cuivre", "coups": 3, "temps": 1.8, "minerai": true, "repousse": 25, "verbe": "Miner"},
	Monde.Deco.FILON_FER: {"objet": "fer", "coups": 3, "temps": 2.4, "minerai": true, "repousse": 30, "verbe": "Miner"},
	Monde.Deco.FILON_OR: {"objet": "or", "coups": 3, "temps": 3.0, "minerai": true, "repousse": 40, "verbe": "Miner"},
	Monde.Deco.FILON_MITHRIL: {"objet": "mithril", "coups": 2, "temps": 4.0, "minerai": true, "repousse": 60, "verbe": "Miner"},
	Monde.Deco.CRISTAL: {"objet": "cristal", "coups": 2, "temps": 5.0, "minerai": true, "repousse": 90, "verbe": "Miner"},
	# Étape 4 : stations posées par les joueurs (démontées, elles redonnent l'objet) et coffres anciens.
	Monde.Deco.ETABLI: {"objet": "etabli", "coups": 1, "temps": 1.0, "minerai": false, "repousse": 0, "verbe": "Démonter"},
	Monde.Deco.FOURNEAU: {"objet": "fourneau", "coups": 1, "temps": 1.5, "minerai": false, "repousse": 0, "verbe": "Démonter"},
	Monde.Deco.ENCLUME: {"objet": "enclume", "coups": 1, "temps": 1.5, "minerai": false, "repousse": 0, "verbe": "Démonter"},
	Monde.Deco.COFFRE: {"objet": "plan", "coups": 1, "temps": 1.5, "minerai": false, "repousse": 180, "verbe": "Ouvrir"},
}

## Décor posé par chaque station (et l'inverse).
const DECOS_STATIONS := {"etabli": Monde.Deco.ETABLI, "fourneau": Monde.Deco.FOURNEAU, "enclume": Monde.Deco.ENCLUME}


static func infos(id: String) -> Dictionary:
	if LISTE.has(id):
		return LISTE[id]
	return Equipement.objets().get(id, {"nom": id, "pile": 1, "rarete": 0, "description": ""})


static func existe(id: String) -> bool:
	return LISTE.has(id) or Equipement.objets().has(id)


static func icone(id: String) -> Texture2D:
	if id.begins_with("plan_"):
		id = "plan"
	var chemin := "res://assets/objets/%s.png" % id
	return load(chemin) if ResourceLoader.exists(chemin) else null


static func recoltable(deco: int) -> bool:
	return RECOLTE.has(deco)


## Durée d'une récolte selon le rôle (le mineur mine 2,5 fois plus vite, et encore plus en Ruée)
## et l'outil porté (bonus : +0,4 = 40 % plus vite).
static func duree_recolte(deco: int, role: String, ruee: bool, bonus := 0.0) -> float:
	var r: Dictionary = RECOLTE[deco]
	var vitesse := 1.0
	if r.minerai:
		vitesse = float(Roles.donnees(role).get("minage", 1.0))
	if ruee:
		vitesse *= 2.0
	if r.objet != "plan" and not DECOS_STATIONS.has(r.objet):
		vitesse *= 1.0 + bonus
	return float(r.temps) / vitesse


# ------------------------------------------------------------------ Inventaire
# Un inventaire est un Array de TAILLE_INVENTAIRE cases : {} (vide) ou {"id": String, "n": int}.

static func inventaire_vide() -> Array:
	var inv := []
	for i in TAILLE_INVENTAIRE:
		inv.append({})
	return inv


## Ajoute n objets ; renvoie le nombre qui n'a pas pu entrer.
static func ajouter(inv: Array, id: String, n: int) -> int:
	var pile := int(infos(id).pile)
	for c in inv:
		if n <= 0:
			break
		if not c.is_empty() and c.id == id and c.n < pile:
			var ajout := mini(n, pile - int(c.n))
			c.n += ajout
			n -= ajout
	for i in inv.size():
		if n <= 0:
			break
		if inv[i].is_empty():
			var ajout := mini(n, pile)
			inv[i] = {"id": id, "n": ajout}
			n -= ajout
	return n


## Ajoute une pile venue d'un sac ou de l'équipement (garde le niveau d'amélioration) ;
## renvoie le nombre qui n'a pas pu entrer.
static func ajouter_pile(inv: Array, o: Dictionary) -> int:
	if int(infos(o.id).pile) > 1:
		return ajouter(inv, o.id, int(o.n))
	for i in inv.size():
		if inv[i].is_empty():
			inv[i] = o.duplicate()
			return 0
	return int(o.n)


## Nombre d'objets de ce genre dans l'inventaire.
static func compter(inv: Array, id: String) -> int:
	var n := 0
	for c in inv:
		if not c.is_empty() and c.id == id:
			n += int(c.n)
	return n


## Retire n objets (suppose qu'il y en a assez).
static func retirer(inv: Array, id: String, n: int) -> void:
	for i in range(inv.size() - 1, -1, -1):
		if n <= 0:
			return
		var c: Dictionary = inv[i]
		if not c.is_empty() and c.id == id:
			var pris := mini(n, int(c.n))
			c.n -= pris
			n -= pris
			if c.n <= 0:
				inv[i] = {}


## Place possible pour cet objet (en nombre d'objets).
static func place_pour(inv: Array, id: String) -> int:
	var pile := int(infos(id).pile)
	var place := 0
	for c in inv:
		if c.is_empty():
			place += pile
		elif c.id == id:
			place += maxi(0, pile - int(c.n))
	return place


static func nombre_objets(inv: Array) -> int:
	var n := 0
	for c in inv:
		if not c.is_empty():
			n += int(c.n)
	return n


## Relit un inventaire venu de la sauvegarde (JSON : nombres en float) ou d'ailleurs.
static func nettoyer(brut) -> Array:
	var inv := inventaire_vide()
	if brut is Array:
		for i in mini(brut.size(), TAILLE_INVENTAIRE):
			var c = brut[i]
			var o := nettoyer_objet(c)
			if not o.is_empty():
				inv[i] = o
	return inv


static func nettoyer_objet(c) -> Dictionary:
	if not c is Dictionary or not existe(str(c.get("id", ""))) or int(c.get("n", 0)) <= 0:
		return {}
	var o := {"id": str(c.id), "n": int(c.n)}
	if int(c.get("niv", 0)) > 0:
		o["niv"] = clampi(int(c.niv), 0, Equipement.NIVEAU_MAX)
	return o
