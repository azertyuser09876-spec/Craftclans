class_name Joystick
extends Control
## Joystick tactile : on pose le doigt n'importe où dans la moitié gauche de l'écran.

const RAYON := 70.0
const FOND := preload("res://assets/ui/joystick_fond.png")
const BOUTON := preload("res://assets/ui/joystick_bouton.png")

var vecteur := Vector2.ZERO
var _doigt := -1
var _centre := Vector2.ZERO
var _repos := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func _position_repos() -> Vector2:
	return Vector2(140, size.y - 140)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _doigt == -1 and event.position.x < size.x * 0.5 and event.position.y > size.y * 0.25:
			_doigt = event.index
			_centre = event.position
			_maj(event.position)
		elif not event.pressed and event.index == _doigt:
			_doigt = -1
			vecteur = Vector2.ZERO
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == _doigt:
		_maj(event.position)


func _maj(pos: Vector2) -> void:
	var d := (pos - _centre).limit_length(RAYON)
	vecteur = d / RAYON
	if vecteur.length() < 0.15:
		vecteur = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var c := _centre if _doigt != -1 else _position_repos()
	draw_texture(FOND, c - FOND.get_size() / 2)
	draw_texture(BOUTON, c + vecteur * RAYON - BOUTON.get_size() / 2)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
