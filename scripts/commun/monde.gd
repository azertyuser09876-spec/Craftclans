class_name Monde
extends RefCounted
## Terrain généré à partir d'une graine. Le client et le serveur le génèrent
## chacun de leur côté avec la même graine : seul le numéro est envoyé sur le réseau.
##
## Étape 0 : une île d'essai de taille fixe. Le monde infini par morceaux arrive à l'étape 2.

enum Sol { EAU, SABLE, HERBE, HERBE_FONCEE, TERRE, PIERRE }
enum Deco { AUCUN, ARBRE, SAPIN, ROCHER, BUISSON, FLEURS, FEU }

const TAILLE := 112 # cases de côté
const DECOS_BLOQUANTES := [Deco.ARBRE, Deco.SAPIN, Deco.ROCHER, Deco.FEU]

var graine: int
var sol := PackedByteArray()
var deco := PackedByteArray()


func _init(p_graine: int) -> void:
	graine = p_graine
	_generer()


func _generer() -> void:
	sol.resize(TAILLE * TAILLE)
	deco.resize(TAILLE * TAILLE)
	var relief := FastNoiseLite.new()
	relief.seed = graine
	relief.frequency = 0.045
	relief.fractal_octaves = 4
	var foret := FastNoiseLite.new()
	foret.seed = graine + 1
	foret.frequency = 0.06
	var rng := RandomNumberGenerator.new()
	rng.seed = graine
	var centre := Vector2(TAILLE, TAILLE) * 0.5
	for y in TAILLE:
		for x in TAILLE:
			var i := y * TAILLE + x
			var dist := Vector2(x, y).distance_to(centre) / (TAILLE * 0.5)
			var h := relief.get_noise_2d(x, y) * 0.5 + 0.55 - pow(dist, 2.2)
			var f := foret.get_noise_2d(x, y)
			var s := Sol.HERBE
			if h < 0.0:
				s = Sol.EAU
			elif h < 0.07:
				s = Sol.SABLE
			elif h > 0.62:
				s = Sol.PIERRE
			elif f > 0.25:
				s = Sol.HERBE_FONCEE
			elif f < -0.45:
				s = Sol.TERRE
			sol[i] = s
			var d := Deco.AUCUN
			var r := rng.randf()
			match s:
				Sol.HERBE_FONCEE:
					if r < 0.22: d = Deco.SAPIN if f > 0.45 else Deco.ARBRE
					elif r < 0.27: d = Deco.BUISSON
				Sol.HERBE:
					if r < 0.025: d = Deco.ARBRE
					elif r < 0.04: d = Deco.BUISSON
					elif r < 0.09: d = Deco.FLEURS
				Sol.PIERRE:
					if r < 0.12: d = Deco.ROCHER
				Sol.TERRE:
					if r < 0.03: d = Deco.ROCHER
			deco[i] = d
	# Clairière d'apparition au centre, avec un feu de camp.
	var c := Vector2i(centre)
	for y in range(c.y - 5, c.y + 6):
		for x in range(c.x - 5, c.x + 6):
			if Vector2(x, y).distance_to(centre) < 5.5:
				sol[y * TAILLE + x] = Sol.HERBE
				deco[y * TAILLE + x] = Deco.AUCUN
	deco[c.y * TAILLE + c.x] = Deco.FEU


func dans_le_monde(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < TAILLE and cy < TAILLE


func sol_en(cx: int, cy: int) -> int:
	return sol[cy * TAILLE + cx] if dans_le_monde(cx, cy) else Sol.EAU


func deco_en(cx: int, cy: int) -> int:
	return deco[cy * TAILLE + cx] if dans_le_monde(cx, cy) else Deco.AUCUN


func case_bloquante(cx: int, cy: int) -> bool:
	if not dans_le_monde(cx, cy):
		return true
	return sol_en(cx, cy) == Sol.EAU or deco_en(cx, cy) in DECOS_BLOQUANTES


## Vrai si un cercle (les pieds d'un personnage) touche une case bloquante.
## Les obstacles occupent une zone réduite de leur case, pour pouvoir passer entre deux arbres.
func collision(pos: Vector2, rayon: float) -> bool:
	var t := float(Config.TAILLE_TUILE)
	var mini := Vector2i(((pos - Vector2(rayon, rayon)) / t).floor())
	var maxi := Vector2i(((pos + Vector2(rayon, rayon)) / t).floor())
	for cy in range(mini.y, maxi.y + 1):
		for cx in range(mini.x, maxi.x + 1):
			if not case_bloquante(cx, cy):
				continue
			var boite := Rect2(cx * t, cy * t, t, t)
			if sol_en(cx, cy) != Sol.EAU and dans_le_monde(cx, cy):
				boite = boite.grow(-8.0) # tronc ou rocher : plus petit que la case
			var proche := pos.clamp(boite.position, boite.end)
			if proche.distance_squared_to(pos) < rayon * rayon:
				return true
	return false


func centre() -> Vector2:
	return Vector2(TAILLE, TAILLE) * 0.5 * Config.TAILLE_TUILE


## Point libre le plus proche de `souhait`, en cherchant en spirale autour.
func point_libre(souhait: Vector2) -> Vector2:
	if not collision(souhait, Config.RAYON_JOUEUR):
		return souhait
	for anneau in range(1, 40):
		for k in anneau * 8:
			var a := TAU * k / (anneau * 8)
			var p := souhait + Vector2(cos(a), sin(a)) * anneau * 16.0
			if not collision(p, Config.RAYON_JOUEUR):
				return p
	return centre() + Vector2(48, 48)


func point_apparition(numero: int) -> Vector2:
	var a := numero * 1.7
	return point_libre(centre() + Vector2(cos(a), sin(a)) * 72.0)
