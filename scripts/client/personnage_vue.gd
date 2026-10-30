class_name PersonnageVue
extends PanelContainer
## Fenêtre « Personnage » (étape 5) : niveau et expérience, points de caractéristiques,
## arbre de compétences principal (le rôle joué) et arbre secondaire. Le serveur vérifie tout.

signal demande(genre: String, valeur: String) # carac, noeud (« arbre:noeud »), oublier

var progression := {}
var role := "guerrier"
var stats := {}
var inventaire: Array = []
var _arbre_vu := "" # arbre affiché ("" = principal)
var _titre: Label
var _barre_xp: ProgressBar
var _texte_xp: Label
var _points_caracs: Label
var _caracs := {} # carac -> {valeur: Label, bouton: Button}
var _bonus: Label
var _oublier: Button
var _onglet_principal: Button
var _onglet_secondaire: Button
var _choix_secondaire: OptionButton
var _points_competence: Label
var _liste: VBoxContainer
var _roles_secondaires: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(860, 560)
	var boite := VBoxContainer.new()
	boite.add_theme_constant_override("separation", 8)
	add_child(boite)
	_titre = Label.new()
	_titre.add_theme_font_size_override("font_size", 22)
	_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boite.add_child(_titre)
	var ligne_xp := HBoxContainer.new()
	boite.add_child(ligne_xp)
	_barre_xp = ProgressBar.new()
	_barre_xp.show_percentage = false
	_barre_xp.custom_minimum_size = Vector2(0, 16)
	_barre_xp.size_flags_horizontal = SIZE_EXPAND_FILL
	_barre_xp.size_flags_vertical = SIZE_SHRINK_CENTER
	var fond := StyleBoxFlat.new()
	fond.bg_color = Color(0, 0, 0, 0.5)
	var plein := StyleBoxFlat.new()
	plein.bg_color = Color(0.45, 0.7, 1.0)
	_barre_xp.add_theme_stylebox_override("background", fond)
	_barre_xp.add_theme_stylebox_override("fill", plein)
	ligne_xp.add_child(_barre_xp)
	_texte_xp = Label.new()
	_texte_xp.custom_minimum_size = Vector2(150, 0)
	_texte_xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_texte_xp.add_theme_font_size_override("font_size", 13)
	ligne_xp.add_child(_texte_xp)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.size_flags_vertical = SIZE_EXPAND_FILL
	boite.add_child(h)
	# Caractéristiques
	var gauche := VBoxContainer.new()
	gauche.custom_minimum_size = Vector2(250, 0)
	gauche.add_theme_constant_override("separation", 6)
	h.add_child(gauche)
	_points_caracs = Label.new()
	_points_caracs.add_theme_font_size_override("font_size", 15)
	gauche.add_child(_points_caracs)
	for c in Progression.ORDRE_CARACS:
		var l := HBoxContainer.new()
		gauche.add_child(l)
		var nom := Label.new()
		nom.text = Progression.CARACS[c].nom
		nom.tooltip_text = "Par point : " + Progression.decrire_stats(Progression.CARACS[c].stats)
		nom.mouse_filter = MOUSE_FILTER_PASS
		nom.custom_minimum_size = Vector2(100, 0)
		l.add_child(nom)
		var valeur := Label.new()
		valeur.custom_minimum_size = Vector2(96, 0)
		valeur.add_theme_font_size_override("font_size", 12)
		valeur.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_child(valeur)
		var b := Button.new()
		b.text = "+"
		b.custom_minimum_size = Vector2(44, 36)
		b.pressed.connect(func(): demande.emit("carac", c))
		l.add_child(b)
		_caracs[c] = {"valeur": valeur, "bouton": b}
	var titre_bonus := Label.new()
	titre_bonus.text = "Bonus totaux (équipement compris)"
	titre_bonus.add_theme_font_size_override("font_size", 13)
	titre_bonus.modulate.a = 0.75
	gauche.add_child(titre_bonus)
	_bonus = Label.new()
	_bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bonus.custom_minimum_size = Vector2(240, 0)
	_bonus.add_theme_font_size_override("font_size", 13)
	gauche.add_child(_bonus)
	_oublier = Button.new()
	_oublier.custom_minimum_size = Vector2(0, 40)
	_oublier.pressed.connect(func(): demande.emit("oublier", ""))
	gauche.add_child(_oublier)
	# Arbres
	var droite := VBoxContainer.new()
	droite.size_flags_horizontal = SIZE_EXPAND_FILL
	droite.add_theme_constant_override("separation", 6)
	h.add_child(droite)
	var onglets := HBoxContainer.new()
	onglets.add_theme_constant_override("separation", 6)
	droite.add_child(onglets)
	_onglet_principal = Button.new()
	_onglet_principal.toggle_mode = true
	_onglet_principal.pressed.connect(func():
		_arbre_vu = ""
		rafraichir())
	onglets.add_child(_onglet_principal)
	_onglet_secondaire = Button.new()
	_onglet_secondaire.toggle_mode = true
	_onglet_secondaire.text = "Secondaire :"
	_onglet_secondaire.pressed.connect(func():
		_arbre_vu = _secondaire_choisi()
		rafraichir())
	onglets.add_child(_onglet_secondaire)
	_choix_secondaire = OptionButton.new()
	_choix_secondaire.item_selected.connect(func(_i):
		_arbre_vu = _secondaire_choisi()
		rafraichir())
	onglets.add_child(_choix_secondaire)
	_points_competence = Label.new()
	_points_competence.add_theme_font_size_override("font_size", 13)
	_points_competence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	droite.add_child(_points_competence)
	var defile := ScrollContainer.new()
	defile.size_flags_vertical = SIZE_EXPAND_FILL
	defile.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	droite.add_child(defile)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 4)
	defile.add_child(_liste)
	var fermer := Button.new()
	fermer.text = "Fermer"
	fermer.custom_minimum_size = Vector2(0, 44)
	fermer.pressed.connect(func(): visible = false)
	boite.add_child(fermer)
	rafraichir()


func maj(p: Dictionary, p_role: String, p_stats: Dictionary, inv: Array) -> void:
	if p_role != role:
		_arbre_vu = ""
	progression = p
	role = p_role
	stats = p_stats
	inventaire = inv
	if visible:
		rafraichir()


func _secondaire_choisi() -> String:
	if progression.get("secondaire", "") != "":
		return progression.secondaire
	var i := _choix_secondaire.selected
	return _roles_secondaires[i] if i >= 0 and i < _roles_secondaires.size() else ""


func rafraichir() -> void:
	if _liste == null or progression.is_empty():
		return
	var p := progression
	var niveau := int(p.niveau)
	_titre.text = "%s  —  niveau %d" % [Roles.donnees(role).nom, niveau]
	var suivant := int(p.get("xp_suivant", 0))
	_barre_xp.max_value = maxi(1, suivant)
	_barre_xp.value = int(p.xp) if suivant > 0 else 1
	_texte_xp.text = "%d / %d xp" % [p.xp, suivant] if suivant > 0 else "Niveau maximum"
	# Caractéristiques
	var pc := int(p.points_caracs)
	_points_caracs.text = "Caractéristiques : %d point(s) à placer" % pc
	_points_caracs.modulate = Color(1, 0.9, 0.4) if pc > 0 else Color.WHITE
	for c in _caracs:
		var n := int(p.caracs.get(c, 0))
		var bonus := {}
		for cle in Progression.CARACS[c].stats:
			bonus[cle] = Progression.CARACS[c].stats[cle] * n
		_caracs[c].valeur.text = "%d  (%s)" % [n, Progression.decrire_stats(bonus) if n > 0 else "—"]
		_caracs[c].bouton.disabled = pc <= 0 or n >= Progression.CARAC_MAX
	_bonus.text = Progression.decrire_stats(stats).replace(", ", "\n")
	var cout := Progression.cout_oubli(p)
	var parts := []
	for id in cout:
		parts.append("%d %s" % [cout[id], Objets.infos(id).nom])
	_oublier.text = "Tout oublier (%s)" % ", ".join(PackedStringArray(parts))
	_oublier.disabled = p.arbres.is_empty() and _somme(p.caracs) == 0
	# Choix de l'arbre secondaire
	_roles_secondaires.clear()
	var selection := _choix_secondaire.selected
	_choix_secondaire.clear()
	for r in Roles.ORDRE:
		if r != role:
			_roles_secondaires.append(r)
			_choix_secondaire.add_item(Roles.donnees(r).nom)
	if p.secondaire != "" and p.secondaire in _roles_secondaires:
		_choix_secondaire.select(_roles_secondaires.find(p.secondaire))
		_choix_secondaire.disabled = true
	else:
		_choix_secondaire.select(clampi(selection, 0, _roles_secondaires.size() - 1))
		_choix_secondaire.disabled = false
	if _arbre_vu != "" and _arbre_vu != _secondaire_choisi():
		_arbre_vu = _secondaire_choisi()
	var arbre := role if _arbre_vu == "" else _arbre_vu
	var principal := arbre == role
	_onglet_principal.text = "Principal : %s" % Roles.donnees(role).nom
	_onglet_principal.set_pressed_no_signal(principal)
	_onglet_secondaire.set_pressed_no_signal(not principal)
	_points_competence.text = "%d point(s) de compétence. %s" % [int(p.points_competence),
		"1 point par rang. Changer de rôle rend les points." if principal else
		"Arbre secondaire : 2 points par rang, sans les compétences qui changent les capacités. Un seul arbre secondaire."]
	# Nœuds
	for enfant in _liste.get_children():
		enfant.queue_free()
	var rangs := Progression.rangs_dans(p, arbre)
	for palier in Progression.PALIERS.size():
		var entete := Label.new()
		var seuil: int = Progression.PALIERS[palier]
		entete.text = "Palier %d%s" % [palier + 1, "" if seuil == 0 else "  (%d rangs dans l'arbre, tu en as %d)" % [seuil, rangs]]
		entete.add_theme_font_size_override("font_size", 14)
		entete.modulate = Color(0.75, 0.85, 1) if rangs >= seuil else Color(0.6, 0.6, 0.6)
		_liste.add_child(entete)
		for noeud in Progression.ARBRES[arbre]:
			if int(Progression.ARBRES[arbre][noeud].palier) == palier:
				_liste.add_child(_ligne(arbre, noeud))


func _somme(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


func _ligne(arbre: String, noeud: String) -> Control:
	var n: Dictionary = Progression.ARBRES[arbre][noeud]
	var r := Progression.rang(progression, arbre, noeud)
	var raison := Progression.empechement_noeud(progression, role, arbre, noeud)
	var cadre := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	cadre.add_child(h)
	var texte := RichTextLabel.new()
	texte.bbcode_enabled = true
	texte.fit_content = true
	texte.scroll_active = false
	texte.size_flags_horizontal = SIZE_EXPAND_FILL
	texte.add_theme_font_size_override("normal_font_size", 13)
	texte.add_theme_font_size_override("bold_font_size", 14)
	var couleur := "#ffd966" if r >= int(n.rangs) else ("#9fdf9f" if r > 0 else "#dddddd")
	texte.text = "[b][color=%s]%s[/color][/b]  %d/%d%s\n%s" % [couleur, n.nom, r, n.rangs,
		"" if raison == "" or raison == "Rang maximum." else "  [color=#999999](%s)[/color]" % raison,
		Progression.decrire_noeud(arbre, noeud)]
	h.add_child(texte)
	var b := Button.new()
	b.text = "+1"
	b.disabled = raison != ""
	b.tooltip_text = raison
	b.custom_minimum_size = Vector2(56, 40)
	b.pressed.connect(func(): demande.emit("noeud", "%s:%s" % [arbre, noeud]))
	h.add_child(b)
	return cadre
