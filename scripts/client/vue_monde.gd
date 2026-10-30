class_name VueMonde
extends Node2D
## Affichage du terrain par morceaux : sol en tuiles, décors triés par profondeur (plus un
## objet est bas à l'écran, plus il passe devant), cycle jour/nuit, et images pour les cartes.

const TEX_SOLS := preload("res://assets/tuiles/sols.png")
const TEX_DECOS := {
	Monde.Deco.ARBRE: preload("res://assets/decors/arbre.png"),
	Monde.Deco.SAPIN: preload("res://assets/decors/sapin.png"),
	Monde.Deco.ROCHER: preload("res://assets/decors/rocher.png"),
	Monde.Deco.BUISSON: preload("res://assets/decors/buisson.png"),
	Monde.Deco.FLEURS: preload("res://assets/decors/fleurs.png"),
	Monde.Deco.CACTUS: preload("res://assets/decors/cactus.png"),
	Monde.Deco.SAPIN_NEIGE: preload("res://assets/decors/sapin_neige.png"),
	Monde.Deco.ARBRE_MORT: preload("res://assets/decors/arbre_mort.png"),
	Monde.Deco.ROSEAUX: preload("res://assets/decors/roseaux.png"),
	Monde.Deco.ROCHER_NOIR: preload("res://assets/decors/rocher_noir.png"),
	Monde.Deco.OS: preload("res://assets/decors/os.png"),
	Monde.Deco.FILON_CUIVRE: preload("res://assets/decors/filon_cuivre.png"),
	Monde.Deco.FILON_FER: preload("res://assets/decors/filon_fer.png"),
	Monde.Deco.FILON_OR: preload("res://assets/decors/filon_or.png"),
	Monde.Deco.FILON_MITHRIL: preload("res://assets/decors/filon_mithril.png"),
	Monde.Deco.CRISTAL: preload("res://assets/decors/cristal.png"),
}
const DECOS_AU_SOL := [Monde.Deco.FLEURS, Monde.Deco.OS, Monde.Deco.ROSEAUX]
const DECOS_HAUTES := [Monde.Deco.ARBRE, Monde.Deco.SAPIN, Monde.Deco.SAPIN_NEIGE, Monde.Deco.ARBRE_MORT]
const TEX_FEU := preload("res://assets/decors/feu_de_camp.png")
const TEX_LUMIERE := preload("res://assets/ui/lumiere.png")
const ATLAS_LAVE := Vector2i(0, 10)

var monde: Monde
var sol: TileMapLayer
## Les personnages s'ajoutent ici pour être triés avec les arbres et les rochers.
var objets: Node2D
var nuit: CanvasModulate
## Images de carte des morceaux vus pendant la partie : Vector2i -> ImageTexture
var cartes := {}
var _conteneurs := {} # Vector2i -> Node2D (décors du morceau)
var _arbres := {} # case -> Sprite2D (rendus transparents quand on passe derrière)
var _decos := {} # case -> nœud du décor (pour le retirer quand il est récolté)
var _transparents: Array = []
var _lumieres: Array[PointLight2D] = []


func _init(p_monde: Monde) -> void:
	monde = p_monde


func _ready() -> void:
	sol = TileMapLayer.new()
	sol.tile_set = _creer_tileset()
	add_child(sol)
	objets = Node2D.new()
	objets.y_sort_enabled = true
	add_child(objets)
	nuit = CanvasModulate.new()
	add_child(nuit)


func _creer_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	var src := TileSetAtlasSource.new()
	src.texture = TEX_SOLS
	src.texture_region_size = Vector2i(32, 32)
	# Eau et lave : tuiles animées sur 4 images.
	for anim in [Vector2i(0, 0), ATLAS_LAVE]:
		src.create_tile(anim)
		src.set_tile_animation_columns(anim, 4)
		src.set_tile_animation_frames_count(anim, 4)
		for f in 4:
			src.set_tile_animation_frame_duration(anim, f, 0.35 if anim.y == 0 else 0.5)
	for ligne in range(1, 10):
		for v in 4:
			src.create_tile(Vector2i(v, ligne))
	ts.add_source(src, 0)
	return ts


func a_morceau(cle: Vector2i) -> bool:
	return _conteneurs.has(cle)


func afficher_morceau(cle: Vector2i) -> void:
	if _conteneurs.has(cle):
		retirer_morceau(cle)
	var m := monde.morceau(cle)
	if m.is_empty():
		return
	var base := cle * Monde.TAILLE_MORCEAU
	var conteneur := Node2D.new()
	conteneur.y_sort_enabled = true
	objets.add_child(conteneur)
	_conteneurs[cle] = conteneur
	for i in Monde.CASES:
		var c := base + Vector2i(i % Monde.TAILLE_MORCEAU, i / Monde.TAILLE_MORCEAU)
		var s: int = m.sol[i]
		var hasard := _hasard(c)
		if s == Monde.Sol.EAU:
			sol.set_cell(c, 0, Vector2i(0, 0))
		elif s == Monde.Sol.LAVE:
			sol.set_cell(c, 0, ATLAS_LAVE)
		else:
			sol.set_cell(c, 0, Vector2i(3 if hasard < 0.08 else int(hasard * 37) % 3, s))
		_creer_deco(conteneur, c, m.deco[i])
	cartes[cle] = ImageTexture.create_from_image(Monde.image_carte(m))


static func _hasard(c: Vector2i) -> float:
	return float(posmod(hash(c), 10007)) / 10007.0


func _creer_deco(conteneur: Node2D, c: Vector2i, d: int) -> void:
	if d == Monde.Deco.AUCUN:
		return
	var t := Config.TAILLE_TUILE
	var hasard := _hasard(c)
	var pied := Vector2((c.x + 0.5) * t, (c.y + 0.7) * t)
	if d == Monde.Deco.FEU:
		_decos[c] = _ajouter_feu(conteneur, pied)
		return
	var spr := Sprite2D.new()
	spr.texture = TEX_DECOS[d]
	spr.offset = Vector2(0, -spr.texture.get_height() / 2.0 + 4)
	spr.position = pied + Vector2(int(hasard * 1000) % 7 - 3, 0)
	spr.flip_h = int(hasard * 10000) % 2 == 0
	if d in DECOS_AU_SOL:
		spr.z_index = -1 # au ras du sol
	if d in DECOS_HAUTES:
		_arbres[c] = spr
	conteneur.add_child(spr)
	_decos[c] = spr


## Une case a changé (récolte, repousse) : remplace son décor et met la carte à jour.
func changer_case(c: Vector2i) -> void:
	var cle := Monde.cle_de_case(c.x, c.y)
	if not _conteneurs.has(cle):
		return
	if _decos.has(c):
		var ancien: Node = _decos[c]
		_transparents.erase(ancien)
		_decos.erase(c)
		_arbres.erase(c)
		ancien.queue_free()
	_creer_deco(_conteneurs[cle], c, monde.deco_en(c.x, c.y))
	var m := monde.morceau(cle)
	if not m.is_empty():
		cartes[cle] = ImageTexture.create_from_image(Monde.image_carte(m))


## Position du centre d'une case (pour viser un décor).
static func centre_case(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * Config.TAILLE_TUILE


func retirer_morceau(cle: Vector2i) -> void:
	if not _conteneurs.has(cle):
		return
	var base := cle * Monde.TAILLE_MORCEAU
	for i in Monde.CASES:
		var c := base + Vector2i(i % Monde.TAILLE_MORCEAU, i / Monde.TAILLE_MORCEAU)
		sol.erase_cell(c)
		_arbres.erase(c)
		_decos.erase(c)
	for l in _conteneurs[cle].find_children("*", "PointLight2D", true, false):
		_lumieres.erase(l)
	_transparents.clear()
	_conteneurs[cle].queue_free()
	_conteneurs.erase(cle)


func morceaux_affiches() -> Array:
	return _conteneurs.keys()


func _ajouter_feu(parent: Node2D, pied: Vector2) -> Node:
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", 8)
	for f in 4:
		var at := AtlasTexture.new()
		at.atlas = TEX_FEU
		at.region = Rect2(f * 32, 0, 32, 32)
		frames.add_frame("default", at)
	var feu := AnimatedSprite2D.new()
	feu.sprite_frames = frames
	feu.offset = Vector2(0, -12)
	feu.position = pied
	feu.play()
	parent.add_child(feu)
	var lum := PointLight2D.new()
	lum.texture = TEX_LUMIERE
	lum.texture_scale = 5.0
	lum.color = Color(1.0, 0.7, 0.4)
	lum.position = Vector2(0, -10)
	feu.add_child(lum)
	_lumieres.append(lum)
	return feu


## Rend transparents les arbres qui cachent ce point (le joueur local).
func voir_a_travers(pos: Vector2) -> void:
	for spr in _transparents:
		if is_instance_valid(spr):
			spr.modulate.a = 1.0
	_transparents.clear()
	var c := Vector2i((pos / Config.TAILLE_TUILE).floor())
	for dy in range(1, 3):
		for dx in range(-1, 2):
			var spr: Sprite2D = _arbres.get(c + Vector2i(dx, dy))
			if spr and spr.position.y > pos.y and absf(spr.position.x - pos.x) < 28.0:
				spr.modulate.a = 0.45
				_transparents.append(spr)


## Couleur de la lumière ambiante selon l'heure (0 à 24).
static func couleur_heure(h: float) -> Color:
	var jour := Color(1, 1, 1)
	var nuit_c := Color(0.32, 0.36, 0.58)
	var aube := Color(1.0, 0.78, 0.62)
	if h >= 7.0 and h < 18.0:
		return jour
	if h >= 5.0 and h < 7.0:
		var t := (h - 5.0) / 2.0
		return nuit_c.lerp(aube, t * 2.0) if t < 0.5 else aube.lerp(jour, (t - 0.5) * 2.0)
	if h >= 18.0 and h < 20.0:
		var t := (h - 18.0) / 2.0
		return jour.lerp(aube, t * 2.0) if t < 0.5 else aube.lerp(nuit_c, (t - 0.5) * 2.0)
	return nuit_c


static func est_nuit(h: float) -> bool:
	return h < 6.0 or h >= 19.0


func definir_heure(h: float) -> void:
	nuit.color = couleur_heure(h)
	var force := clampf(1.0 - nuit.color.v, 0.0, 1.0) * 1.6
	for l in _lumieres:
		if is_instance_valid(l):
			l.energy = force + randf_range(-0.05, 0.05)
