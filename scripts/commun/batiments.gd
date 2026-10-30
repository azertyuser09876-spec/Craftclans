class_name Batiments
extends RefCounted
## Étape 6 : constructions des bases. Murs, portes, sols et pièges se posent sur la grille
## (ce sont des décors du monde, qui bloquent ou non le passage) ; coffres, lits, cœurs de base
## et tourelles se posent sur la grille ou librement (au pixel près).
## Toutes les constructions ont de la vie et peuvent être détruites, même propriétaire hors ligne.

const PORTEE := 130.0 # distance max entre le joueur et ce qu'il pose
const RAYON_BASE := 10 # cases autour d'un cœur de base
const ECART_LIBRE := 18.0 # distance minimale entre deux constructions libres
const NIVEAU_MAX := 2 # renforcement (solidification)
const REDUCTION_NIVEAU := 0.25 # -25 % de dégâts subis par niveau de renforcement
const BONUS_VIE_NIVEAU := 0.5 # +50 % de vie par niveau de renforcement

## Dégâts reçus selon le matériau et le type de dégâts.
const TYPES_DEGATS := {"tranchant": "tranchants", "contondant": "contondants", "percant": "perçants",
	"explosif": "explosifs", "pioche": "de pioche"}
const MULTIPLICATEURS := {
	"bois": {"tranchant": 1.0, "contondant": 1.0, "percant": 0.4, "explosif": 1.6, "pioche": 0.8},
	"pierre": {"tranchant": 0.35, "contondant": 1.2, "percant": 0.2, "explosif": 1.3, "pioche": 1.8},
	"metal": {"tranchant": 0.2, "contondant": 0.7, "percant": 0.1, "explosif": 0.9, "pioche": 1.0},
}
const NOMS_MATERIAUX := {"bois": "bois", "pierre": "pierre", "metal": "métal"}

## mode : grille (décor du monde) ou libre (sur la grille ou au pixel près).
## deco : décor posé (grille) ; ouverte : décor de la porte ouverte.
const LISTE := {
	"mur_bois": {"nom": "Mur en bois", "mode": "grille", "deco": Monde.Deco.MUR_BOIS, "materiau": "bois", "vie": 300,
		"ingredients": {"bois": 4}, "station": "etabli"},
	"mur_pierre": {"nom": "Mur en pierre", "mode": "grille", "deco": Monde.Deco.MUR_PIERRE, "materiau": "pierre", "vie": 700,
		"ingredients": {"pierre": 6, "bois": 1}, "station": "etabli"},
	"mur_metal": {"nom": "Mur en métal", "mode": "grille", "deco": Monde.Deco.MUR_METAL, "materiau": "metal", "vie": 1400,
		"ingredients": {"lingot_fer": 3, "pierre": 2}, "station": "enclume", "rarete": 1},
	"porte_bois": {"nom": "Porte en bois", "mode": "grille", "deco": Monde.Deco.PORTE_BOIS, "ouverte": Monde.Deco.PORTE_BOIS_OUVERTE,
		"materiau": "bois", "vie": 250, "ingredients": {"bois": 6}, "station": "etabli"},
	"porte_metal": {"nom": "Porte en métal", "mode": "grille", "deco": Monde.Deco.PORTE_METAL, "ouverte": Monde.Deco.PORTE_METAL_OUVERTE,
		"materiau": "metal", "vie": 1100, "ingredients": {"lingot_fer": 4, "bois": 1}, "station": "enclume", "rarete": 1},
	"sol_bois": {"nom": "Plancher", "mode": "grille", "deco": Monde.Deco.SOL_BOIS, "materiau": "bois", "vie": 150,
		"ingredients": {"bois": 2}, "station": "etabli", "pile": 50},
	"sol_pierre": {"nom": "Dallage", "mode": "grille", "deco": Monde.Deco.SOL_PIERRE, "materiau": "pierre", "vie": 300,
		"ingredients": {"pierre": 3}, "station": "etabli", "pile": 50},
	"piege": {"nom": "Piège à pointes", "mode": "grille", "deco": Monde.Deco.PIEGE, "materiau": "bois", "vie": 120,
		"ingredients": {"bois": 3, "pierre": 2}, "station": "etabli", "degats": 10.0, "recharge": 0.8},
	"coffre_bois": {"nom": "Coffre", "mode": "libre", "materiau": "bois", "vie": 250, "cases": 16,
		"ingredients": {"bois": 10}, "station": "etabli"},
	"coffre_securise": {"nom": "Coffre sécurisé", "mode": "libre", "materiau": "metal", "vie": 1600, "cases": 12, "verrou": true,
		"ingredients": {"lingot_fer": 6, "bois": 4}, "station": "enclume", "rarete": 1},
	"lit": {"nom": "Lit", "mode": "libre", "materiau": "bois", "vie": 200,
		"ingredients": {"bois": 6, "fibre": 8}, "station": "etabli"},
	"coeur_base": {"nom": "Cœur de base", "mode": "libre", "materiau": "pierre", "vie": 1200,
		"ingredients": {"pierre": 20, "bois": 10}, "station": "etabli", "rarete": 1},
	"tourelle": {"nom": "Tourelle", "mode": "libre", "materiau": "metal", "vie": 600, "degats": 12.0, "portee": 260.0, "recharge": 1.2,
		"ingredients": {"lingot_cuivre": 4, "bois": 6}, "station": "enclume", "rarete": 1},
	# Stations de l'étape 4 : ce sont aussi des constructions (vie, propriétaire).
	"etabli": {"nom": "Établi", "mode": "grille", "deco": Monde.Deco.ETABLI, "materiau": "bois", "vie": 250, "station_objet": true},
	"fourneau": {"nom": "Fourneau", "mode": "grille", "deco": Monde.Deco.FOURNEAU, "materiau": "pierre", "vie": 500, "station_objet": true},
	"enclume": {"nom": "Enclume", "mode": "grille", "deco": Monde.Deco.ENCLUME, "materiau": "metal", "vie": 900, "station_objet": true},
}

const DESCRIPTIONS := {
	"mur_bois": "Bloque le passage et les tirs.",
	"mur_pierre": "Solide contre les lames et les flèches, sensible aux pioches.",
	"mur_metal": "Le plus solide. Les explosions et les pioches en viennent à bout.",
	"porte_bois": "S'ouvre toute seule devant toi et ton équipe, reste fermée aux autres.",
	"porte_metal": "S'ouvre toute seule devant toi et ton équipe, reste fermée aux autres.",
	"sol_bois": "Décoration au sol.",
	"sol_pierre": "Décoration au sol.",
	"piege": "Blesse les ennemis qui marchent dessus.",
	"coffre_bois": "16 cases. N'importe qui peut l'ouvrir : protège-le avec des murs.",
	"coffre_securise": "12 cases. Seuls toi et ton équipe pouvez l'ouvrir. Très solide.",
	"lit": "Près d'un cœur de base, permet d'y réapparaître.",
	"coeur_base": "Crée une base (10 cases autour). Avec un lit à côté, tu y réapparais.",
	"tourelle": "Tire sur les ennemis à portée, même quand tu n'es pas connecté.",
}

static var _objets := {}


## Objets « à poser » (pour Objets.infos) : id -> infos.
static func objets() -> Dictionary:
	if _objets.is_empty():
		for id in LISTE:
			var b: Dictionary = LISTE[id]
			if b.get("station_objet", false):
				continue
			_objets[id] = {"nom": b.nom, "pile": int(b.get("pile", 20)), "rarete": int(b.get("rarete", 0)),
				"construction": true, "description": "%s Vie %d (%s)." % [DESCRIPTIONS.get(id, ""), b.vie, NOMS_MATERIAUX[b.materiau]]}
	return _objets


static func existe(id: String) -> bool:
	return LISTE.has(id)


static func infos(id: String) -> Dictionary:
	return LISTE.get(id, {})


## Type de construction posé sur ce décor ("" si aucun).
static func type_de_deco(d: int) -> String:
	for id in LISTE:
		if LISTE[id].get("deco", -1) == d or LISTE[id].get("ouverte", -1) == d:
			return id
	return ""


static func grille_seulement(id: String) -> bool:
	return LISTE.get(id, {}).get("mode", "grille") == "grille"


## Vie maximale selon le renforcement et le bonus du constructeur (ingénieur, compétences).
static func vie_max(id: String, niv: int, bonus := 0.0) -> int:
	return int(round(float(LISTE[id].vie) * (1.0 + BONUS_VIE_NIVEAU * niv) * (1.0 + bonus)))


static func multiplicateur(id: String, type_degats: String, niv: int) -> float:
	var m: Dictionary = MULTIPLICATEURS[LISTE[id].materiau]
	return float(m.get(type_degats, 1.0)) * (1.0 - REDUCTION_NIVEAU * niv)


## Coût pour renforcer au niveau suivant ({} si impossible).
static func cout_renfort(id: String, niv: int) -> Dictionary:
	if niv >= NIVEAU_MAX:
		return {}
	var b: Dictionary = LISTE[id]
	var cout := {}
	match b.materiau:
		"bois": cout = {"bois": 4 * (niv + 1)}
		"pierre": cout = {"pierre": 6 * (niv + 1)}
		"metal": cout = {"lingot_fer": 2 * (niv + 1)}
	return cout


## Coût pour réparer (une ressource du matériau pour 50 points de vie manquants, au moins 1).
static func cout_reparation(id: String, manque: int) -> Dictionary:
	if manque <= 0:
		return {}
	var n := maxi(1, ceili(manque / 50.0))
	match LISTE[id].materiau:
		"bois": return {"bois": n}
		"pierre": return {"pierre": n}
	return {"lingot_fer": maxi(1, ceili(n / 3.0))}


## Ce que redonne le démontage : l'objet (les stations aussi).
static func objet_rendu(id: String) -> String:
	return id


static func description_degats() -> String:
	return "Les lames abîment surtout le bois ; les pioches et les marteaux la pierre ; les explosions tout ; les flèches presque rien."
