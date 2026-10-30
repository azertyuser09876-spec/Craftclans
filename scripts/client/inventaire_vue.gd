class_name InventaireVue
extends PanelContainer
## Fenêtre d'inventaire : l'équipement porté (avec ses bonus), les cases du joueur,
## le détail de l'objet choisi et les actions (équiper, retirer, améliorer, poser, jeter).

signal action(genre: String, valeur: String) # genre : equiper, retirer, ameliorer, poser, jeter

var inventaire: Array = []
var equipement := {}
var stats := {}
var stations := {} # stations posées à côté du joueur (pour l'amélioration)
var _cases: Array[Button] = []
var _nombres: Array[Label] = []
var _emplacements := {} # emplacement -> Button
var _niveaux := {} # emplacement -> Label
var _detail: Label
var _resume: Label
var _boutons := {} # genre -> Button
var _choisie := -1
var _emplacement_choisi := ""


func _ready() -> void:
	var boite := VBoxContainer.new()
	boite.add_theme_constant_override("separation", 8)
	add_child(boite)
	var titre := Label.new()
	titre.text = "Inventaire et équipement"
	titre.add_theme_font_size_override("font_size", 22)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boite.add_child(titre)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	boite.add_child(h)
	# Équipement
	var gauche := VBoxContainer.new()
	gauche.add_theme_constant_override("separation", 4)
	h.add_child(gauche)
	var grille_e := GridContainer.new()
	grille_e.columns = 2
	grille_e.add_theme_constant_override("h_separation", 4)
	grille_e.add_theme_constant_override("v_separation", 4)
	gauche.add_child(grille_e)
	for emplacement in Equipement.EMPLACEMENTS:
		var b := _case_bouton(56)
		b.tooltip_text = Equipement.NOMS_EMPLACEMENTS[emplacement]
		b.text = Equipement.NOMS_EMPLACEMENTS[emplacement]
		b.pressed.connect(_choisir_emplacement.bind(emplacement))
		grille_e.add_child(b)
		_emplacements[emplacement] = b
		_niveaux[emplacement] = _nombre(b)
	_resume = Label.new()
	_resume.custom_minimum_size = Vector2(116, 0)
	_resume.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resume.add_theme_font_size_override("font_size", 12)
	gauche.add_child(_resume)
	# Sac
	var grille := GridContainer.new()
	grille.columns = 6
	grille.add_theme_constant_override("h_separation", 4)
	grille.add_theme_constant_override("v_separation", 4)
	h.add_child(grille)
	for i in Objets.TAILLE_INVENTAIRE:
		var b := _case_bouton(62)
		b.pressed.connect(_choisir.bind(i))
		grille.add_child(b)
		_cases.append(b)
		_nombres.append(_nombre(b))
	_detail = Label.new()
	_detail.custom_minimum_size = Vector2(0, 58)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 14)
	boite.add_child(_detail)
	var ligne := HBoxContainer.new()
	ligne.alignment = BoxContainer.ALIGNMENT_CENTER
	ligne.add_theme_constant_override("separation", 8)
	boite.add_child(ligne)
	for genre in ["equiper", "retirer", "ameliorer", "poser", "jeter"]:
		var b := Button.new()
		b.text = {"equiper": "Équiper", "retirer": "Retirer", "ameliorer": "Améliorer", "poser": "Construire", "jeter": "Jeter"}[genre]
		b.custom_minimum_size = Vector2(110, 46)
		b.pressed.connect(_agir.bind(genre))
		ligne.add_child(b)
		_boutons[genre] = b
	var fermer := Button.new()
	fermer.text = "Fermer"
	fermer.custom_minimum_size = Vector2(100, 46)
	fermer.pressed.connect(func(): visible = false)
	ligne.add_child(fermer)
	afficher(inventaire, equipement)


func _case_bouton(taille: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(taille, taille)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.toggle_mode = true
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 10)
	return b


func _nombre(b: Button) -> Label:
	var n := Label.new()
	n.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	n.position = Vector2(-34, -22)
	n.custom_minimum_size = Vector2(30, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.add_theme_font_size_override("font_size", 14)
	n.add_theme_constant_override("outline_size", 5)
	n.add_theme_color_override("font_outline_color", Color.BLACK)
	n.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(n)
	return n


func _remplir(b: Button, n: Label, o: Dictionary, vide: String) -> void:
	b.icon = null if o.is_empty() else Objets.icone(o.id)
	b.text = vide if o.is_empty() else ""
	b.tooltip_text = vide if o.is_empty() else Equipement.nom_objet(o)
	b.modulate = Color.WHITE if o.is_empty() else Objets.COULEURS_RARETE[int(Objets.infos(o.id).rarete)].lerp(Color.WHITE, 0.6)
	if o.is_empty():
		n.text = ""
	elif int(o.get("niv", 0)) > 0:
		n.text = "+%d" % int(o.niv)
	else:
		n.text = "" if int(o.n) <= 1 else str(o.n)


func afficher(inv: Array, equip: Dictionary) -> void:
	inventaire = inv
	equipement = equip
	if _cases.is_empty():
		return
	for i in _cases.size():
		_remplir(_cases[i], _nombres[i], inv[i] if i < inv.size() else {}, "")
	for emplacement in _emplacements:
		_remplir(_emplacements[emplacement], _niveaux[emplacement], equip.get(emplacement, {}), Equipement.NOMS_EMPLACEMENTS[emplacement])
	if _choisie >= 0 and (_choisie >= inv.size() or inv[_choisie].is_empty()):
		_choisie = -1
	if _emplacement_choisi != "" and equip.get(_emplacement_choisi, {}).is_empty():
		_emplacement_choisi = ""
	_maj_detail()


func _choisir(i: int) -> void:
	_emplacement_choisi = ""
	_choisie = i if inventaire.size() > i and not inventaire[i].is_empty() else -1
	_maj_detail()


func _choisir_emplacement(emplacement: String) -> void:
	_choisie = -1
	_emplacement_choisi = emplacement if not equipement.get(emplacement, {}).is_empty() else ""
	_maj_detail()


func _agir(genre: String) -> void:
	if genre in ["retirer", "ameliorer"]:
		if _emplacement_choisi != "":
			action.emit(genre, _emplacement_choisi)
	elif _choisie >= 0:
		action.emit(genre, str(_choisie))
		if genre == "poser":
			visible = false # pour voir la station apparaître


func _texte_cout(cout: Dictionary) -> String:
	var parts := []
	for id in cout:
		parts.append("%d %s (%d)" % [cout[id], Objets.infos(id).nom, Objets.compter(inventaire, id)])
	return ", ".join(PackedStringArray(parts))


func maj_stats(s: Dictionary) -> void:
	stats = s
	_maj_detail()


func _maj_detail() -> void:
	if _cases.is_empty():
		return
	for i in _cases.size():
		_cases[i].set_pressed_no_signal(i == _choisie)
	for emplacement in _emplacements:
		_emplacements[emplacement].set_pressed_no_signal(emplacement == _emplacement_choisi)
	var ensemble := Equipement.ensemble_complet(equipement)
	_resume.text = "%s%s" % [Equipement.decrire(stats).replace(", ", "\n"),
		"" if ensemble == "" else "\nEnsemble %s complet" % Equipement.MATERIAUX[ensemble].nom]
	for b in _boutons.values():
		b.visible = false
	_detail.remove_theme_color_override("font_color")
	if _emplacement_choisi != "":
		var o: Dictionary = equipement[_emplacement_choisi]
		var info := Objets.infos(o.id)
		var texte := "%s\n%s" % [Equipement.nom_objet(o), Equipement.decrire(Equipement.stats_objet(o))]
		var cout := Equipement.cout_amelioration(o)
		if cout.is_empty():
			texte += "\nNiveau maximum."
		else:
			var station := Equipement.station_amelioration(o)
			texte += "\nAmélioration +%d : %s, près d'un(e) %s%s." % [int(o.get("niv", 0)) + 1, _texte_cout(cout),
				Equipement.STATIONS[station], "" if stations.has(station) else " (aucune ici)"]
		_detail.text = texte
		_detail.add_theme_color_override("font_color", Objets.COULEURS_RARETE[int(info.rarete)])
		_boutons.retirer.visible = true
		_boutons.ameliorer.visible = not cout.is_empty()
		return
	if _choisie < 0:
		_detail.text = "Choisis un objet. Tu portes %d objet(s).\nÀ ta mort, tout ce que tu portes (équipement compris) tombe sur ton corps." % Objets.nombre_objets(inventaire)
		return
	var o: Dictionary = inventaire[_choisie]
	var info := Objets.infos(o.id)
	_detail.text = "%s ×%d\n%s" % [Equipement.nom_objet(o), o.n, info.description] if int(o.n) > 1 \
		else "%s\n%s" % [Equipement.nom_objet(o), info.description if not info.has("stats") else Equipement.decrire(Equipement.stats_objet(o))]
	_detail.add_theme_color_override("font_color", Objets.COULEURS_RARETE[int(info.rarete)])
	_boutons.equiper.visible = info.has("emplacement")
	_boutons.poser.visible = info.get("station", false) or info.get("construction", false)
	_boutons.jeter.visible = true
