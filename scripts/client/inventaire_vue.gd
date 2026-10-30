class_name InventaireVue
extends PanelContainer
## Fenêtre d'inventaire : les cases du joueur, le détail de l'objet choisi, et « Jeter ».

signal jeter(case: int)

var inventaire: Array = []
var _cases: Array[Button] = []
var _nombres: Array[Label] = []
var _detail: Label
var _bouton_jeter: Button
var _choisie := -1


func _ready() -> void:
	custom_minimum_size = Vector2(470, 0)
	var boite := VBoxContainer.new()
	boite.add_theme_constant_override("separation", 10)
	add_child(boite)
	var titre := Label.new()
	titre.text = "Inventaire"
	titre.add_theme_font_size_override("font_size", 24)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boite.add_child(titre)
	var grille := GridContainer.new()
	grille.columns = 6
	grille.add_theme_constant_override("h_separation", 6)
	grille.add_theme_constant_override("v_separation", 6)
	boite.add_child(grille)
	for i in Objets.TAILLE_INVENTAIRE:
		var b := Button.new()
		b.custom_minimum_size = Vector2(68, 68)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.toggle_mode = true
		b.pressed.connect(_choisir.bind(i))
		var n := Label.new()
		n.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
		n.position = Vector2(-34, -24)
		n.custom_minimum_size = Vector2(30, 0)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		n.add_theme_font_size_override("font_size", 15)
		n.add_theme_constant_override("outline_size", 5)
		n.add_theme_color_override("font_outline_color", Color.BLACK)
		n.mouse_filter = MOUSE_FILTER_IGNORE
		b.add_child(n)
		grille.add_child(b)
		_cases.append(b)
		_nombres.append(n)
	_detail = Label.new()
	_detail.custom_minimum_size = Vector2(0, 52)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boite.add_child(_detail)
	var ligne := HBoxContainer.new()
	ligne.alignment = BoxContainer.ALIGNMENT_CENTER
	ligne.add_theme_constant_override("separation", 10)
	boite.add_child(ligne)
	_bouton_jeter = Button.new()
	_bouton_jeter.text = "Jeter au sol"
	_bouton_jeter.custom_minimum_size = Vector2(150, 48)
	_bouton_jeter.pressed.connect(func():
		if _choisie >= 0:
			jeter.emit(_choisie))
	ligne.add_child(_bouton_jeter)
	var fermer := Button.new()
	fermer.text = "Fermer"
	fermer.custom_minimum_size = Vector2(150, 48)
	fermer.pressed.connect(func(): visible = false)
	ligne.add_child(fermer)
	afficher(inventaire)


func afficher(inv: Array) -> void:
	inventaire = inv
	if _cases.is_empty():
		return
	for i in _cases.size():
		var o: Dictionary = inv[i] if i < inv.size() else {}
		var b := _cases[i]
		b.icon = null if o.is_empty() else Objets.icone(o.id)
		b.tooltip_text = "" if o.is_empty() else Objets.infos(o.id).nom
		b.modulate = Color.WHITE if o.is_empty() else Objets.COULEURS_RARETE[int(Objets.infos(o.id).rarete)].lerp(Color.WHITE, 0.6)
		_nombres[i].text = "" if o.is_empty() or int(o.n) <= 1 else str(o.n)
	if _choisie >= 0 and (_choisie >= inv.size() or inv[_choisie].is_empty()):
		_choisie = -1
	_maj_detail()


func _choisir(i: int) -> void:
	_choisie = i if inventaire.size() > i and not inventaire[i].is_empty() else -1
	_maj_detail()


func _maj_detail() -> void:
	for i in _cases.size():
		_cases[i].set_pressed_no_signal(i == _choisie)
	_bouton_jeter.disabled = _choisie < 0
	if _choisie < 0:
		var n := Objets.nombre_objets(inventaire)
		_detail.text = "Choisis un objet. %s\nÀ ta mort, tout ce que tu portes tombe sur ton corps." % (
			"Tu ne portes rien." if n == 0 else "Tu portes %d objet(s)." % n)
		_detail.remove_theme_color_override("font_color")
		return
	var o: Dictionary = inventaire[_choisie]
	var info := Objets.infos(o.id)
	_detail.text = "%s ×%d\n%s" % [info.nom, o.n, info.description]
	_detail.add_theme_color_override("font_color", Objets.COULEURS_RARETE[int(info.rarete)])
