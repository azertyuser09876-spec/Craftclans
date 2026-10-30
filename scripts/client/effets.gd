class_name Effets
extends Node2D
## Effets visuels du combat : projectiles, potions lancées, zones, explosions,
## nombres de dégâts. Tout est décidé par le serveur ; ici on ne fait qu'afficher.

const TEX_FLECHE := preload("res://assets/combat/fleche.png")
const TEX_BALAYAGE := preload("res://assets/combat/balayage.png")
const TEX_ZONE := preload("res://assets/combat/zone.png")
const PLANCHES := {
	"explosion": preload("res://assets/combat/explosion.png"),
	"soin": preload("res://assets/combat/soin.png"),
	"impact": preload("res://assets/combat/impact.png"),
}

var projectiles := {} # pid -> Sprite2D


func _ready() -> void:
	z_index = 20


# ------------------------------------------------------------------ Projectiles

func projectile(pid: int, de: Vector2, dir: Vector2, vitesse: float, portee: float) -> void:
	var f := Sprite2D.new()
	f.texture = TEX_FLECHE
	f.position = de
	f.rotation = dir.angle()
	add_child(f)
	projectiles[pid] = f
	var tw := f.create_tween()
	tw.tween_property(f, "position", de + dir * portee, portee / vitesse)
	tw.tween_callback(func(): _retirer_projectile(pid))


func fin_projectile(pid: int, pos: Vector2, touche: bool) -> void:
	if projectiles.has(pid):
		projectiles[pid].position = pos
		_retirer_projectile(pid)
	if touche:
		explosion(pos, "impact", 0.5)


func _retirer_projectile(pid: int) -> void:
	if projectiles.has(pid):
		projectiles[pid].queue_free()
		projectiles.erase(pid)


func lancer(de: Vector2, vers: Vector2, duree: float, genre: String) -> void:
	var p := Sprite2D.new()
	p.texture = load("res://assets/combat/%s.png" % genre)
	add_child(p)
	var depart := de + Vector2(0, -12)
	var hauteur := 60.0 + de.distance_to(vers) * 0.15
	var tw := p.create_tween()
	tw.tween_method(func(t: float):
		p.position = depart.lerp(vers, t) + Vector2(0, -sin(t * PI) * hauteur)
		p.rotation = t * TAU * 1.5, 0.0, 1.0, duree)
	tw.tween_callback(p.queue_free)
	zone_temporaire(vers, 40.0, duree, Color(1, 0.6, 0.3, 0.5) if genre == "potion_degats" else Color(0.4, 1, 0.5, 0.5))


# ------------------------------------------------------------------ Zones et explosions

func zone_temporaire(pos: Vector2, rayon: float, duree: float, couleur: Color) -> void:
	var z := Sprite2D.new()
	z.texture = TEX_ZONE
	z.position = pos
	z.scale = Vector2.ONE * (rayon * 2.0 / TEX_ZONE.get_width())
	z.modulate = couleur
	z.z_index = -15
	add_child(z)
	var tw := z.create_tween()
	tw.tween_interval(duree)
	tw.tween_property(z, "modulate:a", 0.0, 0.25)
	tw.tween_callback(z.queue_free)


func explosion(pos: Vector2, genre: String, echelle := 1.0) -> void:
	var frames := SpriteFrames.new()
	frames.set_animation_loop("default", false)
	frames.set_animation_speed("default", 14)
	for f in 4:
		var at := AtlasTexture.new()
		at.atlas = PLANCHES[genre]
		at.region = Rect2(f * 64, 0, 64, 64)
		frames.add_frame("default", at)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = frames
	a.position = pos + Vector2(0, -6)
	a.scale = Vector2.ONE * echelle
	add_child(a)
	a.play()
	a.animation_finished.connect(a.queue_free)


func zone(pos: Vector2, rayon: float, delai: float, genre: String, vagues: int) -> void:
	match genre:
		"pluie":
			zone_temporaire(pos, rayon, delai + vagues * 0.35, Color(1, 0.85, 0.4, 0.55))
			for i in vagues * 6:
				var f := Sprite2D.new()
				f.texture = TEX_FLECHE
				f.rotation = PI / 2
				var arrivee := pos + Vector2.from_angle(randf() * TAU) * randf() * rayon
				f.position = arrivee + Vector2(0, -220)
				f.modulate.a = 0.0
				add_child(f)
				var tw := f.create_tween()
				tw.tween_interval(delai + (i / 6) * 0.35 - 0.25 + randf() * 0.1)
				tw.tween_property(f, "modulate:a", 1.0, 0.01)
				tw.tween_property(f, "position", arrivee, 0.25)
				tw.tween_interval(0.3)
				tw.tween_callback(f.queue_free)
		"guerrier":
			anneau(pos + Vector2(0, -8), rayon, Color(1, 1, 1, 0.9))
		"paladin":
			anneau(pos + Vector2(0, -8), rayon, Color(1, 0.85, 0.4, 0.9))


func impact(pos: Vector2, rayon: float, genre: String) -> void:
	match genre:
		"potion_degats":
			explosion(pos, "explosion", rayon / 32.0)
		"potion_soin":
			explosion(pos, "soin", rayon / 32.0)
		"pluie":
			explosion(pos, "impact", rayon / 40.0)


func anneau(pos: Vector2, rayon: float, couleur: Color) -> void:
	var a := Sprite2D.new()
	a.texture = TEX_BALAYAGE
	a.position = pos
	a.modulate = couleur
	add_child(a)
	var tw := a.create_tween().set_parallel()
	tw.tween_property(a, "rotation", TAU * 1.5, 0.35)
	tw.tween_property(a, "scale", Vector2.ONE * (rayon / 28.0), 0.35).from(Vector2.ONE * 0.4)
	tw.tween_property(a, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(a.queue_free)


func balayage(pos: Vector2, angle: float, portee: float) -> void:
	var b := Sprite2D.new()
	b.texture = TEX_BALAYAGE
	b.position = pos + Vector2(0, -10)
	b.rotation = angle
	b.scale = Vector2.ONE * (portee / 28.0)
	add_child(b)
	var tw := b.create_tween()
	tw.tween_property(b, "modulate:a", 0.0, 0.2)
	tw.tween_callback(b.queue_free)


# ------------------------------------------------------------------ Nombres

func nombre(pos: Vector2, montant: int, soin: bool, sur_moi: bool) -> void:
	var l := Label.new()
	l.text = ("+%d" if soin else "%d") % montant
	l.add_theme_font_size_override("font_size", 14 if not sur_moi else 16)
	var couleur := Color(0.45, 1, 0.5) if soin else (Color(1, 0.35, 0.3) if sur_moi else Color(1, 0.95, 0.6))
	l.add_theme_color_override("font_color", couleur)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.position = pos + Vector2(-20 + randf_range(-8, 8), -50)
	l.custom_minimum_size = Vector2(40, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 26, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)
