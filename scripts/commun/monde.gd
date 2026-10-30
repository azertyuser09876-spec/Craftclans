class_name Monde
extends RefCounted
## Monde infini découpé en morceaux de 32×32 cases.
##
## Le serveur génère chaque morceau à partir de la graine la première fois qu'un joueur
## s'en approche, le sauvegarde, puis l'envoie aux joueurs proches. Le jeu ne génère
## rien : il affiche les morceaux reçus. Un morceau déjà visité reste donc identique
## même si le générateur change dans une mise à jour.

enum Sol { EAU, SABLE, HERBE, HERBE_FONCEE, TERRE, PIERRE, NEIGE, BOUE, CENDRE, HERBE_CLAIRE, LAVE }
enum Deco { AUCUN, ARBRE, SAPIN, ROCHER, BUISSON, FLEURS, FEU, CACTUS, SAPIN_NEIGE, ARBRE_MORT, ROSEAUX, ROCHER_NOIR, OS }
enum Biome { PRAIRIE, FORET, DESERT, TOUNDRA, MARAIS, MONTAGNE, LAC, PLAGE, VALLEE, BRULEES }

const TAILLE_MORCEAU := 32
const CASES := TAILLE_MORCEAU * TAILLE_MORCEAU
const GENERATEUR := 1 # version du générateur, enregistrée avec chaque morceau
const DECOS_BLOQUANTES := [Deco.ARBRE, Deco.SAPIN, Deco.ROCHER, Deco.FEU, Deco.CACTUS, Deco.SAPIN_NEIGE, Deco.ARBRE_MORT, Deco.ROCHER_NOIR]
const SOLS_BLOQUANTS := [Sol.EAU, Sol.LAVE]
const NOMS_BIOMES := ["Prairie", "Forêt", "Désert", "Toundra", "Marais", "Montagnes", "Lac", "Plage", "Vallée paisible", "Terres brûlées"]
const DISTANCE_PAR_DANGER := 110.0 # cases à parcourir depuis le centre pour +1 de danger
const DANGER_MAX := 10
## Couleur de chaque sol sur les cartes (même ordre que Sol).
const COULEURS := [Color8(52, 112, 196), Color8(220, 198, 138), Color8(86, 158, 70), Color8(58, 124, 58),
	Color8(128, 92, 60), Color8(128, 128, 134), Color8(232, 238, 246), Color8(92, 84, 52),
	Color8(70, 64, 66), Color8(120, 186, 86), Color8(230, 100, 30)]

var graine: int
## Morceaux connus : Vector2i -> {sol, deco, biome} (PackedByteArray de CASES octets)
var morceaux := {}
## Côté serveur : génère les morceaux manquants à la demande.
var generer_auto := false
## Côté serveur : fonction (cle) -> Dictionary pour relire un morceau sauvegardé ({} si aucun).
var chargeur: Callable
## Côté serveur : appelée avec (cle, morceau) quand un morceau vient d'être créé.
var sur_creation: Callable

var _relief := FastNoiseLite.new()
var _humidite := FastNoiseLite.new()
var _temperature := FastNoiseLite.new()
var _foret := FastNoiseLite.new()
var _calme := FastNoiseLite.new()
var _brulure := FastNoiseLite.new()


func _init(p_graine: int, p_generer_auto := false) -> void:
	graine = p_graine
	generer_auto = p_generer_auto
	var bruits := [[_relief, 0.012, 5], [_humidite, 0.007, 3], [_temperature, 0.004, 3],
		[_foret, 0.06, 2], [_calme, 0.006, 2], [_brulure, 0.009, 3]]
	for i in bruits.size():
		var b: FastNoiseLite = bruits[i][0]
		b.seed = graine + i * 7919
		b.frequency = bruits[i][1]
		b.fractal_octaves = bruits[i][2]


# ------------------------------------------------------------------ Accès aux cases

static func cle_de_case(cx: int, cy: int) -> Vector2i:
	return Vector2i(floori(float(cx) / TAILLE_MORCEAU), floori(float(cy) / TAILLE_MORCEAU))


static func cle_de_position(pos: Vector2) -> Vector2i:
	return cle_de_case(floori(pos.x / Config.TAILLE_TUILE), floori(pos.y / Config.TAILLE_TUILE))


func morceau(cle: Vector2i) -> Dictionary:
	var m: Dictionary = morceaux.get(cle, {})
	if m.is_empty() and generer_auto:
		if chargeur.is_valid():
			m = chargeur.call(cle)
		if m.is_empty():
			m = generer_morceau(cle)
			if sur_creation.is_valid():
				sur_creation.call(cle, m)
		morceaux[cle] = m
	return m


func _indice(cx: int, cy: int) -> int:
	return posmod(cy, TAILLE_MORCEAU) * TAILLE_MORCEAU + posmod(cx, TAILLE_MORCEAU)


func sol_en(cx: int, cy: int) -> int:
	var m := morceau(cle_de_case(cx, cy))
	return m.sol[_indice(cx, cy)] if not m.is_empty() else Sol.HERBE


func deco_en(cx: int, cy: int) -> int:
	var m := morceau(cle_de_case(cx, cy))
	return m.deco[_indice(cx, cy)] if not m.is_empty() else Deco.AUCUN


func biome_en(cx: int, cy: int) -> int:
	var m := morceau(cle_de_case(cx, cy))
	return m.biome[_indice(cx, cy)] if not m.is_empty() else Biome.PRAIRIE


func case_bloquante(cx: int, cy: int) -> bool:
	return sol_en(cx, cy) in SOLS_BLOQUANTS or deco_en(cx, cy) in DECOS_BLOQUANTES


## Vitesse de marche sur le sol (boue et neige ralentissent).
func facteur_sol(pos: Vector2) -> float:
	match sol_en(floori(pos.x / Config.TAILLE_TUILE), floori(pos.y / Config.TAILLE_TUILE)):
		Sol.BOUE: return 0.7
		Sol.NEIGE: return 0.85
	return 1.0


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
			if not sol_en(cx, cy) in SOLS_BLOQUANTS:
				boite = boite.grow(-8.0) # tronc ou rocher : plus petit que la case
			var proche := pos.clamp(boite.position, boite.end)
			if proche.distance_squared_to(pos) < rayon * rayon:
				return true
	return false


## Danger d'une case : augmente avec la distance au centre, sauf dans les vallées paisibles.
func danger_en(cx: int, cy: int) -> int:
	var d := int(Vector2(cx, cy).length() / DISTANCE_PAR_DANGER)
	match biome_en(cx, cy):
		Biome.VALLEE: d -= 3
		Biome.BRULEES: d = maxi(d, 5)
	return clampi(d, 0, DANGER_MAX)


func centre() -> Vector2:
	return Vector2(0.5, 0.5) * Config.TAILLE_TUILE


## Point libre le plus proche de `souhait`, en cherchant en spirale autour.
func point_libre(souhait: Vector2) -> Vector2:
	if not collision(souhait, Config.RAYON_JOUEUR):
		return souhait
	for anneau in range(1, 60):
		for k in anneau * 8:
			var a := TAU * k / (anneau * 8)
			var p := souhait + Vector2(cos(a), sin(a)) * anneau * 16.0
			if not collision(p, Config.RAYON_JOUEUR):
				return p
	return souhait


func point_apparition(numero: int) -> Vector2:
	var a := numero * 1.7
	return point_libre(centre() + Vector2(cos(a), sin(a)) * 72.0)


# ------------------------------------------------------------------ Génération (serveur)

func generer_morceau(cle: Vector2i) -> Dictionary:
	var sol := PackedByteArray()
	var deco := PackedByteArray()
	var biome := PackedByteArray()
	sol.resize(CASES)
	deco.resize(CASES)
	biome.resize(CASES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([graine, cle.x, cle.y])
	for ly in TAILLE_MORCEAU:
		for lx in TAILLE_MORCEAU:
			var cx := cle.x * TAILLE_MORCEAU + lx
			var cy := cle.y * TAILLE_MORCEAU + ly
			var r := _case(cx, cy, rng.randf())
			var i := ly * TAILLE_MORCEAU + lx
			sol[i] = r[0]
			deco[i] = r[1]
			biome[i] = r[2]
	# Clairière d'apparition au centre du monde, avec un feu de camp.
	if cle == Vector2i(0, 0) or cle == Vector2i(-1, 0) or cle == Vector2i(0, -1) or cle == Vector2i(-1, -1):
		for ly in TAILLE_MORCEAU:
			for lx in TAILLE_MORCEAU:
				var cx := cle.x * TAILLE_MORCEAU + lx
				var cy := cle.y * TAILLE_MORCEAU + ly
				var dist := Vector2(cx, cy).length()
				var i := ly * TAILLE_MORCEAU + lx
				if dist < 7.0:
					sol[i] = Sol.HERBE
					deco[i] = Deco.AUCUN
				if cx == 0 and cy == 0:
					deco[i] = Deco.FEU
	return {"sol": sol, "deco": deco, "biome": biome, "generateur": GENERATEUR}


## Calcule une case : [sol, deco, biome]. `r` est un nombre au hasard (0 à 1) propre à la case.
func _case(cx: int, cy: int, r: float) -> Array:
	var dist := Vector2(cx, cy).length()
	var e := _relief.get_noise_2d(cx, cy)
	var h := _humidite.get_noise_2d(cx, cy)
	var t := _temperature.get_noise_2d(cx, cy)
	var f := _foret.get_noise_2d(cx, cy)
	# Près du centre : terrain plus doux (pas d'océan ni de montagne sur le point de départ).
	var douceur := clampf(1.0 - dist / 60.0, 0.0, 1.0)
	e = lerpf(e, 0.1, douceur)
	# Biome
	var b := Biome.PRAIRIE
	if e < -0.28:
		b = Biome.LAC
	elif e < -0.22:
		b = Biome.PLAGE
	elif e > 0.42:
		b = Biome.MONTAGNE
	elif dist > 350.0 and _brulure.get_noise_2d(cx, cy) > 0.62 - minf((dist - 350.0) / 3000.0, 0.3):
		b = Biome.BRULEES
	elif _calme.get_noise_2d(cx, cy) > 0.45 and dist > 120.0:
		b = Biome.VALLEE
	elif t < -0.22:
		b = Biome.TOUNDRA
	elif t > 0.25 and h < 0.0:
		b = Biome.DESERT
	elif h > 0.3:
		b = Biome.MARAIS
	elif h > 0.02:
		b = Biome.FORET
	# Sol et décor
	var s := Sol.HERBE
	var d := Deco.AUCUN
	match b:
		Biome.LAC:
			s = Sol.EAU
		Biome.PLAGE:
			s = Sol.SABLE
			if r < 0.01: d = Deco.ROCHER
		Biome.MONTAGNE:
			s = Sol.NEIGE if e > 0.58 else Sol.PIERRE
			if r < 0.14: d = Deco.ROCHER
			elif r < 0.17 and s == Sol.PIERRE: d = Deco.SAPIN
		Biome.BRULEES:
			s = Sol.LAVE if _brulure.get_noise_2d(cx * 3, cy * 3) > 0.55 else Sol.CENDRE
			if s == Sol.CENDRE:
				if r < 0.05: d = Deco.ARBRE_MORT
				elif r < 0.10: d = Deco.ROCHER_NOIR
		Biome.VALLEE:
			s = Sol.HERBE_CLAIRE
			if r < 0.015: d = Deco.ARBRE
			elif r < 0.12: d = Deco.FLEURS
			elif r < 0.14: d = Deco.BUISSON
		Biome.TOUNDRA:
			s = Sol.NEIGE
			if f > 0.1 and r < 0.2: d = Deco.SAPIN_NEIGE
			elif r < 0.02: d = Deco.ROCHER
		Biome.DESERT:
			s = Sol.SABLE
			if r < 0.012: d = Deco.CACTUS
			elif r < 0.016: d = Deco.OS
			elif r < 0.02: d = Deco.ROCHER
		Biome.MARAIS:
			s = Sol.EAU if f > 0.35 else Sol.BOUE
			if s == Sol.BOUE:
				if r < 0.12: d = Deco.ROSEAUX
				elif r < 0.16: d = Deco.ARBRE_MORT
		Biome.FORET:
			s = Sol.HERBE_FONCEE
			if f > -0.2 and r < 0.24: d = Deco.SAPIN if t < 0.0 else Deco.ARBRE
			elif r < 0.04: d = Deco.BUISSON
		_:
			s = Sol.TERRE if f < -0.55 else Sol.HERBE
			if r < 0.02: d = Deco.ARBRE
			elif r < 0.035: d = Deco.BUISSON
			elif r < 0.08: d = Deco.FLEURS
			elif r < 0.085: d = Deco.ROCHER
	return [s, d, b]


## Image de carte d'un morceau (1 pixel par case).
static func image_carte(m: Dictionary) -> Image:
	var img := Image.create(TAILLE_MORCEAU, TAILLE_MORCEAU, false, Image.FORMAT_RGB8)
	for i in CASES:
		var c: Color = COULEURS[m.sol[i]]
		if m.deco[i] in [Deco.ARBRE, Deco.SAPIN, Deco.SAPIN_NEIGE, Deco.CACTUS]:
			c = c.darkened(0.35)
		img.set_pixel(i % TAILLE_MORCEAU, i / TAILLE_MORCEAU, c)
	return img


# ------------------------------------------------------------------ Transport et sauvegarde

## Un morceau en un seul tableau d'octets compressé (pour le réseau et le disque).
static func emballer(m: Dictionary) -> PackedByteArray:
	var brut := PackedByteArray()
	brut.append_array(m.sol)
	brut.append_array(m.deco)
	brut.append_array(m.biome)
	return brut.compress(FileAccess.COMPRESSION_DEFLATE)


static func deballer(donnees: PackedByteArray) -> Dictionary:
	var brut := donnees.decompress(CASES * 3, FileAccess.COMPRESSION_DEFLATE)
	if brut.size() != CASES * 3:
		return {}
	return {"sol": brut.slice(0, CASES), "deco": brut.slice(CASES, CASES * 2), "biome": brut.slice(CASES * 2)}


func recevoir(cle: Vector2i, donnees: PackedByteArray) -> Dictionary:
	var m := deballer(donnees)
	if not m.is_empty():
		morceaux[cle] = m
	return m


func oublier(cle: Vector2i) -> void:
	morceaux.erase(cle)
