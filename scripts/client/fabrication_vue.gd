class_name FabricationVue
extends PanelContainer
## Fenêtre « Fabriquer » : les recettes, ce qu'il faut (station proche, plan, ressources)
## et un bouton pour chaque. Le serveur vérifie tout à nouveau.

signal fabriquer(id: String)

const CATEGORIES := [["station", "Stations"], ["construction", "Constructions"], ["lingot", "Lingots (fourneau)"], ["arme", "Armes"], ["outil", "Outils"],
	["tete", "Armures : tête"], ["torse", "Armures : torse"], ["jambes", "Armures : jambes"], ["pieds", "Armures : pieds"]]

var inventaire: Array = []
var stations := {}
var _liste: VBoxContainer
var _onglets: HBoxContainer
var _categorie := "station"
var _seulement_possibles: CheckButton
var _entete: Label


func _ready() -> void:
	custom_minimum_size = Vector2(640, 520)
	var boite := VBoxContainer.new()
	boite.add_theme_constant_override("separation", 8)
	add_child(boite)
	var titre := Label.new()
	titre.text = "Fabriquer"
	titre.add_theme_font_size_override("font_size", 22)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boite.add_child(titre)
	_entete = Label.new()
	_entete.add_theme_font_size_override("font_size", 13)
	_entete.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boite.add_child(_entete)
	var defile_onglets := ScrollContainer.new()
	defile_onglets.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	defile_onglets.custom_minimum_size = Vector2(0, 44)
	boite.add_child(defile_onglets)
	_onglets = HBoxContainer.new()
	defile_onglets.add_child(_onglets)
	for c in CATEGORIES:
		var b := Button.new()
		b.text = c[1]
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			_categorie = c[0]
			rafraichir())
		_onglets.add_child(b)
	_seulement_possibles = CheckButton.new()
	_seulement_possibles.text = "Seulement ce que je peux fabriquer ici"
	_seulement_possibles.add_theme_font_size_override("font_size", 13)
	_seulement_possibles.toggled.connect(func(_on): rafraichir())
	boite.add_child(_seulement_possibles)
	var defile := ScrollContainer.new()
	defile.size_flags_vertical = SIZE_EXPAND_FILL
	defile.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	boite.add_child(defile)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 6)
	defile.add_child(_liste)
	var fermer := Button.new()
	fermer.text = "Fermer"
	fermer.custom_minimum_size = Vector2(0, 44)
	fermer.pressed.connect(func(): visible = false)
	boite.add_child(fermer)
	rafraichir()


func maj(inv: Array, p_stations: Dictionary) -> void:
	var change := inv != inventaire or p_stations != stations
	inventaire = inv
	stations = p_stations
	if change and visible:
		rafraichir()


func rafraichir() -> void:
	if _liste == null:
		return
	for i in _onglets.get_child_count():
		_onglets.get_child(i).set_pressed_no_signal(CATEGORIES[i][0] == _categorie)
	var noms := []
	for st in stations:
		noms.append(Equipement.STATIONS[st])
	_entete.text = "Stations à côté de toi : %s. Pose un établi depuis l'inventaire pour commencer (8 bois)." % (
		"aucune" if noms.is_empty() else ", ".join(PackedStringArray(noms)))
	for enfant in _liste.get_children():
		enfant.queue_free()
	var recettes := Equipement.recettes()
	for id in recettes:
		var r: Dictionary = recettes[id]
		if r.categorie != _categorie:
			continue
		var raison := Atelier.empechement(r, inventaire, stations)
		if _seulement_possibles.button_pressed and raison != "":
			continue
		_liste.add_child(_ligne(r, raison))


func _ligne(r: Dictionary, raison: String) -> Control:
	var cadre := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	cadre.add_child(h)
	var icone := TextureRect.new()
	icone.texture = Objets.icone(r.objet)
	icone.custom_minimum_size = Vector2(40, 40)
	icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icone.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	h.add_child(icone)
	var info := Objets.infos(r.objet)
	var texte := RichTextLabel.new()
	texte.bbcode_enabled = true
	texte.fit_content = true
	texte.scroll_active = false
	texte.size_flags_horizontal = SIZE_EXPAND_FILL
	texte.add_theme_font_size_override("normal_font_size", 13)
	texte.add_theme_font_size_override("bold_font_size", 14)
	var parts := []
	for ing in r.ingredients:
		var a := Objets.compter(inventaire, ing)
		var besoin := int(r.ingredients[ing])
		parts.append("[color=%s]%d %s[/color]" % ["#8f8" if a >= besoin else "#f88", besoin, Objets.infos(ing).nom])
	var conditions := []
	if r.station != "":
		conditions.append("[color=%s]%s[/color]" % ["#8f8" if stations.has(r.station) else "#f88", Equipement.STATIONS[r.station]])
	if r.plan != "":
		conditions.append("[color=%s]%s[/color]" % ["#8f8" if Objets.compter(inventaire, r.plan) > 0 else "#f88", Objets.infos(r.plan).nom])
	texte.text = "[b][color=#%s]%s[/color][/b]%s\n%s%s" % [Objets.COULEURS_RARETE[int(info.rarete)].to_html(false), info.nom,
		"" if not info.has("stats") else "  —  " + Equipement.decrire(info.stats),
		", ".join(PackedStringArray(parts)),
		"" if conditions.is_empty() else "   ·   " + ", ".join(PackedStringArray(conditions))]
	h.add_child(texte)
	var b := Button.new()
	b.text = "Fabriquer"
	b.disabled = raison != ""
	b.tooltip_text = raison
	b.custom_minimum_size = Vector2(110, 40)
	b.pressed.connect(func(): fabriquer.emit(r.objet))
	h.add_child(b)
	return cadre
