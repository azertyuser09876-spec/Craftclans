class_name VueMonde
extends Node2D
## Affichage du terrain : sol en tuiles, décors triés par profondeur (plus un objet
## est bas à l'écran, plus il passe devant), et cycle jour/nuit.

const TEX_SOLS := preload("res://assets/tuiles/sols.png")
const TEX_DECOS := {
	Monde.Deco.ARBRE: preload("res://assets/decors/arbre.png"),
	Monde.Deco.SAPIN: preload("res://assets/decors/sapin.png"),
	Monde.Deco.ROCHER: preload("res://assets/decors/rocher.png"),
	Monde.Deco.BUISSON: preload("res://assets/decors/buisson.png"),
	Monde.Deco.FLEURS: preload("res://assets/decors/fleurs.png"),
}
const TEX_FEU := preload("res://assets/decors/feu_de_camp.png")
const TEX_LUMIERE := preload("res://assets/ui/lumiere.png")

var monde: Monde
var sol: TileMapLayer
## Les personnages s'ajoutent ici pour être triés avec les arbres et les rochers.
var objets: Node2D
var nuit: CanvasModulate
var _lumieres: Array[PointLight2D] = []


func _init(p_monde: Monde) -> void:
	monde = p_monde


func _ready() -> void:
	sol = TileMapLayer.new()
	sol.tile_set = _creer_tileset()
	add_child(sol)
	var rng := RandomNumberGenerator.new()
	rng.seed = monde.graine
	for y in Monde.TAILLE:
		for x in Monde.TAILLE:
			var s := monde.sol_en(x, y)
			if s == Monde.Sol.EAU:
				sol.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
			else:
				var variante := 3 if rng.randf() < 0.08 else rng.randi_range(0, 2)
				sol.set_cell(Vector2i(x, y), 0, Vector2i(variante, s))
	# Une bordure d'eau autour de l'île, pour ne pas voir le vide.
	for y in range(-20, Monde.TAILLE + 20):
		for x in range(-20, Monde.TAILLE + 20):
			if not monde.dans_le_monde(x, y):
				sol.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	objets = Node2D.new()
	objets.y_sort_enabled = true
	add_child(objets)
	var t := Config.TAILLE_TUILE
	for y in Monde.TAILLE:
		for x in Monde.TAILLE:
			var d := monde.deco_en(x, y)
			if d == Monde.Deco.AUCUN:
				continue
			var pied := Vector2((x + 0.5) * t, (y + 0.7) * t)
			if d == Monde.Deco.FEU:
				_ajouter_feu(pied)
				continue
			var spr := Sprite2D.new()
			spr.texture = TEX_DECOS[d]
			spr.offset = Vector2(0, -spr.texture.get_height() / 2.0 + 4)
			spr.position = pied + Vector2(rng.randf_range(-3, 3), 0)
			spr.flip_h = rng.randf() < 0.5
			if d == Monde.Deco.FLEURS:
				spr.z_index = -1 # au ras du sol
			objets.add_child(spr)
	nuit = CanvasModulate.new()
	add_child(nuit)


func _creer_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	var src := TileSetAtlasSource.new()
	src.texture = TEX_SOLS
	src.texture_region_size = Vector2i(32, 32)
	# Eau : une tuile animée sur 4 images (ligne 0).
	src.create_tile(Vector2i(0, 0))
	src.set_tile_animation_columns(Vector2i(0, 0), 4)
	src.set_tile_animation_frames_count(Vector2i(0, 0), 4)
	for f in 4:
		src.set_tile_animation_frame_duration(Vector2i(0, 0), f, 0.35)
	for ligne in range(1, 6):
		for v in 4:
			src.create_tile(Vector2i(v, ligne))
	ts.add_source(src, 0)
	return ts


func _ajouter_feu(pied: Vector2) -> void:
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
	objets.add_child(feu)
	var lum := PointLight2D.new()
	lum.texture = TEX_LUMIERE
	lum.texture_scale = 5.0
	lum.color = Color(1.0, 0.7, 0.4)
	lum.position = Vector2(0, -10)
	feu.add_child(lum)
	_lumieres.append(lum)


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
		l.energy = force + randf_range(-0.05, 0.05)
