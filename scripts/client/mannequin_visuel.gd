class_name MannequinVisuel
extends Node2D
## Mannequin d'entraînement : il encaisse les coups et se remet d'aplomb.

var vie := 1
var vie_max := 1
var _secousse := 0.0
var sprite: Sprite2D


func _init(pos: Vector2, p_vie: int, p_max: int) -> void:
	position = pos
	vie = p_vie
	vie_max = p_max
	sprite = Sprite2D.new()
	sprite.texture = preload("res://assets/combat/mannequin.png")
	sprite.offset = Vector2(0, -18)
	add_child(sprite)


func touche() -> void:
	_secousse = 1.0


func _process(delta: float) -> void:
	_secousse = maxf(0.0, _secousse - delta * 4.0)
	sprite.rotation = sin(_secousse * 20.0) * 0.25 * _secousse
	queue_redraw()


func _draw() -> void:
	if vie >= vie_max:
		return
	var r := Rect2(-15, -44, 30, 4)
	draw_rect(r.grow(1), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(r.position, Vector2(30.0 * vie / vie_max, 4)), Color(0.95, 0.75, 0.3))
