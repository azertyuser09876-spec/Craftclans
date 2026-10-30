class_name CarteVue
extends Control
## Carte du monde dessinée à partir des morceaux vus pendant la partie.
## Sert de minicarte (petite, centrée sur le joueur) et de grande carte (touche M).

var vue: VueMonde
var centre := Vector2.ZERO # position du monde au centre de la carte
var pixels_par_case := 1.0
var marqueurs: Array = [] # [position, couleur]
var grande := false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.85))
	if vue == null:
		return
	var t := float(Config.TAILLE_TUILE)
	var cote := Monde.TAILLE_MORCEAU * pixels_par_case
	var milieu := size / 2.0
	for cle in vue.cartes:
		var coin: Vector2 = milieu + (Vector2(cle * Monde.TAILLE_MORCEAU) - centre / t) * pixels_par_case
		var r := Rect2(coin, Vector2(cote, cote))
		if r.intersects(Rect2(Vector2.ZERO, size)):
			draw_texture_rect(vue.cartes[cle], r, false)
	for m in marqueurs:
		var p: Vector2 = milieu + (m[0] - centre) / t * pixels_par_case
		if Rect2(Vector2.ZERO, size).has_point(p):
			draw_circle(p, 4.0 if grande else 3.0, Color.BLACK)
			draw_circle(p, 3.0 if grande else 2.0, m[1])
	# Point de départ (feu de camp)
	var depart := milieu + (Vector2.ZERO - centre) / t * pixels_par_case
	if Rect2(Vector2.ZERO, size).has_point(depart):
		draw_circle(depart, 3.0, Color(1, 0.5, 0.2))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.5), false, 2.0)
