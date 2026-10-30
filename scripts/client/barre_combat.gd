class_name BarreCombat
extends Control
## Interface de combat : barre de vie, icônes des capacités avec leur recharge,
## et sur téléphone les boutons d'attaque à faire glisser pour viser (façon Brawl Stars).

signal visee_commencee(genre: String)
signal visee_changee(genre: String, vecteur: Vector2) # longueur 0 à 1
signal visee_relachee(genre: String, vecteur: Vector2, tape: bool)
signal esquive_demandee

const ICONE_ESQUIVE := preload("res://assets/ui/esquive.png")
const ICONE_COMPETENCE := preload("res://assets/ui/competence.png")
const DISTANCE_GLISSER := 90.0

var tactile := false
var role := "guerrier"
var vie := 100
var vie_max := 100
var recharges := {"attaque": 0.0, "competence": 0.0, "esquive": 0.0} # 0 = prêt, 1 = vient d'être utilisé
var charge := -1.0 # charge de l'archer, -1 si rien
var niveau := 1
var part_xp := 0.0 # avancement dans le niveau (0 à 1)
var _icone_role: Texture2D
var _doigts := {} # index -> {genre, depart, vecteur, deplace}


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	definir_role(role)


func definir_role(r: String) -> void:
	role = r
	_icone_role = load("res://assets/ui/role_%s.png" % r)
	queue_redraw()


func _boutons() -> Dictionary:
	var b := {}
	if tactile:
		b["attaque"] = {"centre": Vector2(size.x - 120, size.y - 130), "rayon": 58.0}
		b["competence"] = {"centre": Vector2(size.x - 250, size.y - 80), "rayon": 44.0}
		b["esquive"] = {"centre": Vector2(size.x - 95, size.y - 265), "rayon": 38.0}
	else:
		var y := size.y - 44
		b["attaque"] = {"centre": Vector2(size.x / 2 + 190, y), "rayon": 22.0}
		b["competence"] = {"centre": Vector2(size.x / 2 + 245, y), "rayon": 22.0}
		b["esquive"] = {"centre": Vector2(size.x / 2 + 300, y), "rayon": 22.0}
	return b


func _icone(genre: String) -> Texture2D:
	match genre:
		"attaque": return _icone_role
		"competence": return ICONE_COMPETENCE
	return ICONE_ESQUIVE


func _draw() -> void:
	var police := get_theme_default_font()
	# Barre de vie
	var largeur := 300.0
	var haut := Rect2(size.x / 2 - largeur / 2, size.y - 56, largeur, 22)
	if tactile:
		haut.position = Vector2(size.x / 2 - largeur / 2, 14)
	draw_rect(haut.grow(3), Color(0, 0, 0, 0.6))
	var part := clampf(float(vie) / maxf(vie_max, 1), 0.0, 1.0)
	draw_rect(Rect2(haut.position, Vector2(largeur * part, haut.size.y)), Color(0.85, 0.25, 0.22).lerp(Color(0.3, 0.8, 0.35), part))
	draw_string(police, haut.position + Vector2(0, 17), "%d / %d" % [vie, vie_max], HORIZONTAL_ALIGNMENT_CENTER, largeur, 15)
	draw_texture_rect(_icone_role, Rect2(haut.position + Vector2(-46, -12), Vector2(40, 40)), false)
	# Niveau et expérience
	var bx := Rect2(haut.position + Vector2(0, haut.size.y + 4), Vector2(largeur, 5))
	draw_rect(bx, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bx.position, Vector2(largeur * clampf(part_xp, 0.0, 1.0), bx.size.y)), Color(0.45, 0.7, 1.0))
	draw_string(police, bx.position + Vector2(0, 19), "Niveau %d" % niveau, HORIZONTAL_ALIGNMENT_CENTER, largeur, 12)
	# Charge de l'archer
	if charge >= 0.0:
		var c := Rect2(haut.position + Vector2(0, -12), Vector2(largeur * charge, 6))
		if tactile:
			c.position.y = haut.end.y + 6
		draw_rect(c, Color(1, 0.85, 0.3))
	# Capacités
	var noms := {"attaque": "Clic G", "competence": "Clic D / E", "esquive": "Espace"}
	for genre in _boutons():
		var b: Dictionary = _boutons()[genre]
		var r: float = b.rayon
		var centre: Vector2 = b.centre
		draw_circle(centre, r + 3, Color(0, 0, 0, 0.45))
		draw_texture_rect(_icone(genre), Rect2(centre - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6), false)
		var rec: float = recharges[genre]
		if rec > 0.0:
			draw_circle(centre, r, Color(0, 0, 0, 0.5))
			draw_arc(centre, r - 2, -PI / 2, -PI / 2 + TAU * (1.0 - rec), 32, Color(1, 1, 1, 0.8), 3)
		if not tactile:
			draw_string(police, centre + Vector2(-40, r + 16), noms[genre], HORIZONTAL_ALIGNMENT_CENTER, 80, 11)
	# Visée en cours (tactile)
	for d in _doigts.values():
		if d.genre == "esquive":
			continue
		var b: Dictionary = _boutons()[d.genre]
		draw_circle(b.centre + d.vecteur * 40.0, 14, Color(1, 1, 1, 0.6))


func _input(event: InputEvent) -> void:
	if not tactile:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var boutons := _boutons()
			for genre in boutons:
				if event.position.distance_to(boutons[genre].centre) <= boutons[genre].rayon * 1.3:
					get_viewport().set_input_as_handled()
					if genre == "esquive":
						esquive_demandee.emit()
						return
					_doigts[event.index] = {"genre": genre, "depart": event.position, "vecteur": Vector2.ZERO, "deplace": false}
					visee_commencee.emit(genre)
					return
		elif _doigts.has(event.index):
			var d: Dictionary = _doigts[event.index]
			_doigts.erase(event.index)
			visee_relachee.emit(d.genre, d.vecteur, not d.deplace)
			get_viewport().set_input_as_handled()
			queue_redraw()
	elif event is InputEventScreenDrag and _doigts.has(event.index):
		var d: Dictionary = _doigts[event.index]
		var ecart: Vector2 = event.position - d.depart
		if ecart.length() > 18.0:
			d.deplace = true
		d.vecteur = (ecart / DISTANCE_GLISSER).limit_length(1.0)
		visee_changee.emit(d.genre, d.vecteur)
		get_viewport().set_input_as_handled()
		queue_redraw()


func doigt_sur_bouton(index: int) -> bool:
	return _doigts.has(index)
