class_name JoueurVisuel
extends Node2D
## Affichage d'un personnage : sprite animé, tenue du rôle, arme tournée vers la visée,
## nom, barre de vie, bulle de chat, effets (ombre, bouclier, mort), petite lumière la nuit.
## La position du nœud est celle des pieds (utile pour le tri par profondeur).

const RETARD_INTERPOLATION := 0.1 # secondes : les autres joueurs sont affichés un peu dans le passé
const DIRECTIONS := ["bas", "gauche", "droite", "haut"]
const TEX_TOMBE := preload("res://assets/combat/tombe.png")
const TEX_BOUCLIER := preload("res://assets/combat/bouclier.png")

var nom := ""
var role := "guerrier"
var equipe := ""
var allie := true # même équipe que le joueur local (ou le joueur local lui-même)
var vie := 100
var vie_max := 100
var drapeaux := 0
var visee := Vector2.RIGHT # direction de l'arme

var sprite: AnimatedSprite2D
var tenue: AnimatedSprite2D
var arme_pivot: Node2D
var arme: Sprite2D
var etiquette: Label
var bulle: Label
var lumiere: PointLight2D
var tombe: Sprite2D
var bouclier: Sprite2D
var _tampon: Array = [] # [temps, position] reçus du serveur
var _derniere_pos := Vector2.ZERO
var _duree_bulle := 0.0
var _direction := "bas"
var _geste := 0.0 # animation d'attaque


func _init(p_nom: String, apparence: int, est_admin := false) -> void:
	nom = p_nom
	sprite = AnimatedSprite2D.new()
	sprite.offset = Vector2(0, -13)
	add_child(sprite)
	tenue = AnimatedSprite2D.new()
	tenue.offset = Vector2(0, -17)
	add_child(tenue)
	arme_pivot = Node2D.new()
	arme_pivot.position = Vector2(0, -10)
	add_child(arme_pivot)
	arme = Sprite2D.new()
	arme.centered = false
	arme_pivot.add_child(arme)
	definir_apparence(apparence)
	definir_role("guerrier")
	etiquette = _label(p_nom, Color(1, 0.85, 0.35) if est_admin else Color.WHITE, 11)
	etiquette.position = Vector2(-60, -54)
	add_child(etiquette)
	bulle = _label("", Color(0.1, 0.1, 0.12), 10)
	bulle.position = Vector2(-80, -80)
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
	tombe = Sprite2D.new()
	tombe.texture = TEX_TOMBE
	tombe.offset = Vector2(0, -11)
	tombe.visible = false
	add_child(tombe)
	bouclier = Sprite2D.new()
	bouclier.texture = TEX_BOUCLIER
	bouclier.position = Vector2(0, -14)
	bouclier.modulate = Color(1, 1, 1, 0.55)
	bouclier.visible = false
	add_child(bouclier)


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


static func _frames(tex: Texture2D, hauteur: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for d in 4:
		var anim: String = DIRECTIONS[d]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, 8)
		for f in 4:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(f * 32, d * hauteur, 32, hauteur)
			frames.add_frame(anim, at)
	return frames


func definir_apparence(apparence: int) -> void:
	sprite.sprite_frames = _frames(load("res://assets/personnages/perso_%d.png" % clampi(apparence, 0, Config.NB_APPARENCES - 1)), 32)
	sprite.animation = _direction


func definir_role(p_role: String) -> void:
	role = p_role if Roles.valide(p_role) else "guerrier"
	tenue.sprite_frames = _frames(load("res://assets/personnages/role_%s.png" % role), 40)
	tenue.animation = _direction
	arme.texture = load("res://assets/armes/%s.png" % role)
	arme.offset = Vector2(4, -arme.texture.get_height() / 2.0)


## Arme équipée : l'arme du rôle prend la couleur de son matériau.
func definir_arme(id: String) -> void:
	var info: Dictionary = Equipement.objets().get(id, {})
	arme.modulate = Color.WHITE if info.is_empty() else Color.WHITE.lerp(info.couleur, 0.65)


func definir_couleur_nom(c: Color) -> void:
	etiquette.add_theme_color_override("font_color", c)


func dire(texte: String) -> void:
	bulle.text = texte
	bulle.visible = true
	_duree_bulle = 4.0 + texte.length() * 0.05


func geste(angle: float) -> void:
	visee = Vector2.from_angle(angle)
	_geste = 1.0


func est_mort() -> bool:
	return drapeaux & 1 != 0


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
	var mort := est_mort()
	if mouvement.length() > 0.2:
		if absf(mouvement.x) > absf(mouvement.y):
			_direction = "droite" if mouvement.x > 0 else "gauche"
		else:
			_direction = "bas" if mouvement.y > 0 else "haut"
		if sprite.animation != _direction or not sprite.is_playing():
			sprite.play(_direction)
			tenue.play(_direction)
		if _geste <= 0.0:
			visee = visee.lerp(mouvement.normalized(), minf(delta * 8.0, 1.0)).normalized()
	elif sprite.is_playing():
		sprite.stop()
		tenue.stop()
		sprite.animation = _direction
		tenue.animation = _direction
		sprite.frame = 0
		tenue.frame = 0
	tenue.frame = sprite.frame
	# Arme : tournée vers la visée, avec un petit mouvement d'attaque.
	_geste = maxf(0.0, _geste - delta * 5.0)
	arme_pivot.rotation = visee.angle() + sin(_geste * PI) * 1.2
	arme.flip_v = visee.x < 0
	arme_pivot.z_index = -1 if visee.y < -0.3 else 0
	# États
	var ombre := drapeaux & 2 != 0
	sprite.visible = not mort
	tenue.visible = not mort
	arme_pivot.visible = not mort
	tombe.visible = mort
	bouclier.visible = drapeaux & 4 != 0 and not mort
	if ombre:
		modulate.a = 0.35 if allie else 0.0
	else:
		modulate.a = 1.0
	if _duree_bulle > 0.0:
		_duree_bulle -= delta
		if _duree_bulle <= 0.0:
			bulle.visible = false
	queue_redraw()


func _draw() -> void:
	if est_mort() or vie_max <= 0:
		return
	# Barre de vie au-dessus de la tête
	var largeur := 30.0
	var r := Rect2(-largeur / 2, -38, largeur, 4)
	draw_rect(r.grow(1), Color(0, 0, 0, 0.7))
	var part := clampf(float(vie) / vie_max, 0.0, 1.0)
	var couleur := Color(0.35, 0.85, 0.35) if allie else Color(0.9, 0.3, 0.25)
	draw_rect(Rect2(r.position, Vector2(largeur * part, 4)), couleur)
