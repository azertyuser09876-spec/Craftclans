class_name DonneesBoss
extends RefCounted
## Boss mondiaux. Le serveur gère leur activation dès maintenant ; leurs combats
## et leurs donjons arrivent à l'étape 11 de la feuille de route.

const LISTE := [
	{"id": "colosse", "nom": "Le Colosse de Cendres", "lieu": "Volcan du Nord", "niveau": 40},
	{"id": "reine", "nom": "La Reine des Abysses", "lieu": "Fosse océanique", "niveau": 55},
	{"id": "liche", "nom": "La Liche Éternelle", "lieu": "Nécropole oubliée", "niveau": 70},
	{"id": "dragon", "nom": "Vharkun, le Dragon Primordial", "lieu": "Pic des Tempêtes", "niveau": 90},
]

const JOURS := ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]


static func par_id(id: String) -> Dictionary:
	for b in LISTE:
		if b.id == id:
			return b
	return {}
