class_name JoueurVisuel
extends Node2D
## Affichage d'un personnage : sprite animé, nom, bulle de chat, petite lumière la nuit.
## La position du nœud est celle des pieds (utile pour le tri par profondeur).

const RETARD_INTERPOLATION := 0.1 # secondes : les autres joueurs sont affichés un peu dans le passé
const DIRECTIONS := ["bas", "gauche", "droite", "haut"]

var sprite: AnimatedSprite2D
var etiquette: Label
var bulle: Label
var lumiere: PointLight2D
var _tampon: Array = [] # [temps, position] reçus du serveur
var _derniere_pos := Vector2.ZERO
var _duree_bulle := 0.0
var _direction := "bas"


func _init(nom: String, apparence: int, est_admin := false) -> void:
	sprite = AnimatedSprite2D.new()
	sprite.offset = Vector2(0, -13)
	add_child(sprite)
	definir_apparence(apparence)
	etiquette = _label(nom, Color(1, 0.85, 0.35) if est_admin else Color.WHITE, 11)
	etiquette.position = Vector2(-60, -46)
	add_child(etiquette)
	bulle = _label("", Color(0.1, 0.1, 0.12), 10)
	bulle.position = Vector2(-80, -72)
	bulle.custom_minimum_size = Vector2(160, 0)
	bulle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var fond := StyleBoxFlat.new()
	fond.bg_color = Color(1, 1, 1, 0.92)
	fond.set_corner_radius_all(6)
	fond.content_margin_left = 6
	fond.content_margin_right = 6
	bulle.add_theme_stylebox_override("normal", fond)
	bulle.add_theme_constant_override("outline_size", 0)
	bulle.visible = false
	bulle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bulle)
	lumiere = PointLight2D.new()
	lumiere.texture = preload("res://assets/ui/lumiere.png")
	lumiere.texture_scale = 2.2
	lumiere.energy = 0.0
	lumiere.position = Vector2(0, -12)
	add_child(lumiere)


func _label(texte: String, couleur: Color, taille: int) -> Label:
	var l := Label.new()
	l.text = texte
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(120, 0)
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", couleur)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l


func definir_apparence(apparence: int) -> void:
	var tex: Texture2D = load("res://assets/personnages/perso_%d.png" % clampi(apparence, 0, Config.NB_APPARENCES - 1))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for d in 4:
		var anim: String = DIRECTIONS[d]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, 8)
		for f in 4:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(f * 32, d * 32, 32, 32)
			frames.add_frame(anim, at)
	sprite.sprite_frames = frames
	sprite.animation = "bas"


func dire(texte: String) -> void:
	bulle.text = texte
	bulle.visible = true
	_duree_bulle = 4.0 + texte.length() * 0.05


## Pour les autres joueurs : position reçue du serveur.
func ajouter_instantane(pos: Vector2) -> void:
	_tampon.append([Time.get_ticks_msec() / 1000.0, pos])
	if _tampon.size() > 30:
		_tampon.pop_front()


func interpoler() -> void:
	if _tampon.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0 - RETARD_INTERPOLATION
	while _tampon.size() >= 2 and _tampon[1][0] <= t:
		_tampon.pop_front()
	if _tampon.size() >= 2:
		var a: Array = _tampon[0]
		var b: Array = _tampon[1]
		var k := clampf((t - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0)
		position = (a[1] as Vector2).lerp(b[1], k)
	else:
		position = _tampon[0][1]


func _process(delta: float) -> void:
	var mouvement := position - _derniere_pos
	_derniere_pos = position
	if mouvement.length() > 0.2:
		if absf(mouvement.x) > absf(mouvement.y):
			_direction = "droite" if mouvement.x > 0 else "gauche"
		else:
			_direction = "bas" if mouvement.y > 0 else "haut"
		if sprite.animation != _direction or not sprite.is_playing():
			sprite.play(_direction)
	elif sprite.is_playing():
		sprite.stop()
		sprite.animation = _direction
		sprite.frame = 0
	if _duree_bulle > 0.0:
		_duree_bulle -= delta
		if _duree_bulle <= 0.0:
			bulle.visible = false
