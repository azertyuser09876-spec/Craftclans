class_name ThemeJeu
extends RefCounted
## Thème de l'interface (couleurs, boutons, champs), créé par le code.

const FOND := Color(0.09, 0.12, 0.16, 0.92)
const BORD := Color(0.36, 0.62, 0.38)
const ACCENT := Color(0.42, 0.75, 0.45)
const TEXTE := Color(0.93, 0.95, 0.92)


static func boite(couleur: Color, bord := Color.TRANSPARENT, rayon := 8, marge := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = couleur
	s.set_corner_radius_all(rayon)
	s.set_content_margin_all(marge)
	if bord.a > 0:
		s.border_color = bord
		s.set_border_width_all(2)
	return s


static func creer() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_stylebox("panel", "PanelContainer", boite(FOND, BORD, 12, 18))
	t.set_stylebox("panel", "Panel", boite(FOND, BORD, 12, 18))
	t.set_stylebox("normal", "Button", boite(Color(0.2, 0.36, 0.24), Color(0.3, 0.5, 0.32), 8, 10))
	t.set_stylebox("hover", "Button", boite(Color(0.26, 0.46, 0.3), ACCENT, 8, 10))
	t.set_stylebox("pressed", "Button", boite(Color(0.16, 0.28, 0.2), ACCENT, 8, 10))
	t.set_stylebox("disabled", "Button", boite(Color(0.2, 0.22, 0.24), Color.TRANSPARENT, 8, 10))
	t.set_stylebox("focus", "Button", boite(Color.TRANSPARENT, Color(1, 1, 1, 0.5), 8, 10))
	t.set_stylebox("normal", "LineEdit", boite(Color(0.05, 0.07, 0.09, 0.95), Color(0.3, 0.36, 0.4), 6, 8))
	t.set_stylebox("focus", "LineEdit", boite(Color.TRANSPARENT, ACCENT, 6, 8))
	t.set_color("font_color", "Label", TEXTE)
	t.set_color("font_color", "Button", TEXTE)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.7))
	t.set_constant("outline_size", "Label", 3)
	return t
