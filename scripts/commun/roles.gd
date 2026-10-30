class_name Roles
extends RefCounted
## Rôles de combat de l'étape 1 et leurs capacités de base.
## Le serveur s'en sert pour appliquer les règles, le jeu pour afficher la visée et les recharges.
##
## Genres d'attaque :
##  melee     coup en arc devant soi (portee, angle)
##  tir       projectile en ligne droite, chargé si "charge" > 0 (archer)
##  lancer    objet lancé au point visé, effet de zone à l'arrivée (potions)
##  zone_visee  effet de zone au point visé après un délai (pluie de flèches)
##  zone_soi  effet de zone autour de soi (tourbillon, bouclier)
##  buff      effet sur soi (sprint, ombre)

const ESQUIVE_FRAMES := 11 # durée de l'esquive (images à 60 par seconde)
const ESQUIVE_VITESSE := 520.0
const REAPPARITION := 5.0 # secondes

const LISTE := {
	"guerrier": {
		"nom": "Guerrier", "vie": 160, "vitesse": 1.0, "esquive": 2.5,
		"description": "Plus de vie et de dégâts. Frappe fort au corps à corps.",
		"attaque": {"nom": "Coup d'épée", "genre": "melee", "degats": 22, "portee": 46.0, "angle": 110.0, "recharge": 0.55},
		"competence": {"nom": "Tourbillon", "genre": "zone_soi", "degats": 32, "rayon": 68.0, "recharge": 6.0},
	},
	"archer": {
		"nom": "Archer", "vie": 100, "vitesse": 1.05, "esquive": 2.5,
		"description": "Plus on garde appuyé, plus la flèche va loin et fait mal.",
		"attaque": {"nom": "Tir chargé", "genre": "tir", "degats": 10, "degats_max": 42, "portee": 220.0, "portee_max": 540.0,
			"vitesse_proj": 520.0, "vitesse_proj_max": 900.0, "charge": 1.2, "recharge": 0.35},
		"competence": {"nom": "Pluie de flèches", "genre": "zone_visee", "degats": 14, "vagues": 3, "rayon": 72.0, "portee": 360.0, "delai": 0.6, "recharge": 8.0},
	},
	"mage": {
		"nom": "Mage de soutien", "vie": 90, "vitesse": 1.0, "esquive": 2.5,
		"description": "Lance des potions de dégâts ou de soin, avec une zone de visée au sol.",
		"attaque": {"nom": "Potion explosive", "genre": "lancer", "degats": 20, "rayon": 52.0, "portee": 320.0, "vol": 0.55, "recharge": 1.0},
		"competence": {"nom": "Potion de soin", "genre": "lancer", "soin": 38, "rayon": 64.0, "portee": 300.0, "vol": 0.55, "recharge": 7.0},
	},
	"explorateur": {
		"nom": "Explorateur", "vie": 110, "vitesse": 1.3, "esquive": 1.5,
		"description": "Plus rapide. Esquive plus souvent.",
		"attaque": {"nom": "Coup de dague", "genre": "melee", "degats": 13, "portee": 40.0, "angle": 90.0, "recharge": 0.35},
		"competence": {"nom": "Sprint", "genre": "buff", "effet": "sprint", "duree": 3.0, "bonus": 0.6, "recharge": 10.0},
	},
	"paladin": {
		"nom": "Paladin", "vie": 185, "vitesse": 0.9, "esquive": 3.0,
		"description": "Très résistant. Protège ses alliés.",
		"attaque": {"nom": "Coup de marteau", "genre": "melee", "degats": 26, "portee": 44.0, "angle": 100.0, "recharge": 0.8},
		"competence": {"nom": "Bouclier sacré", "genre": "zone_soi", "effet": "bouclier", "soin": 15, "rayon": 90.0, "duree": 4.0, "reduction": 0.6, "recharge": 12.0},
	},
	"assassin": {
		"nom": "Assassin", "vie": 85, "vitesse": 1.15, "esquive": 2.0,
		"description": "Dégâts doublés dans le dos. Peut se fondre dans l'ombre.",
		"attaque": {"nom": "Dagues", "genre": "melee", "degats": 17, "portee": 40.0, "angle": 90.0, "recharge": 0.4, "dos": 2.0},
		"competence": {"nom": "Ombre", "genre": "buff", "effet": "ombre", "duree": 3.5, "bonus": 1.0, "recharge": 12.0},
	},
	"mineur": {
		"nom": "Mineur", "vie": 125, "vitesse": 1.0, "esquive": 2.5, "minage": 2.5,
		"description": "Mine les rochers et les filons 2,5 fois plus vite.",
		"attaque": {"nom": "Coup de pioche", "genre": "melee", "degats": 18, "portee": 44.0, "angle": 100.0, "recharge": 0.6},
		"competence": {"nom": "Ruée minière", "genre": "buff", "effet": "ruee", "duree": 8.0, "bonus": 0.2, "recharge": 20.0,
			"description": "Pendant 8 s : récolte 2 fois plus rapide et +20 % de vitesse."},
	},
}

const ORDRE := ["guerrier", "archer", "mage", "explorateur", "paladin", "assassin", "mineur"]


static func donnees(role: String) -> Dictionary:
	return LISTE.get(role, LISTE.guerrier)


static func valide(role: String) -> bool:
	return LISTE.has(role)


## Portée de visée d'une capacité (pour la zone affichée au sol).
static func portee(capacite: Dictionary, charge := 1.0) -> float:
	if capacite.has("portee_max"):
		return lerpf(capacite.portee, capacite.portee_max, charge)
	return float(capacite.get("portee", capacite.get("rayon", 0.0)))
