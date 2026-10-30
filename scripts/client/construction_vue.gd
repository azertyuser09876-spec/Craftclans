class_name ConstructionVue
extends PanelContainer
## Fenêtre d'une construction (étape 6) : vie, renforcement, réparation, démontage,
## et pour les coffres : leur contenu à côté de l'inventaire (cliquer pour déplacer une pile).

signal action(genre: String, id: int, valeur: int) # renforcer, reparer, demonter, prendre, deposer, fermer

var rec := {} # infos de la construction (Construction.infos côté serveur)
var allie := false
var contenu: Array = []
var inventaire: Array = []
var _titre: Label
var _infos: Label
var _boutons := {}
var _zone_coffre: HBoxContainer
var _grille_coffre: GridContainer
var _grille_inv: GridContainer


func _ready() -> void:
	var boite := VBoxContainer.new()
	boite.add_theme_constant_override("separation", 8)
	add_child(boite)
	_titre = Label.new()
	_titre.add_theme_font_size_override("font_size", 22)
	_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boite.add_child(_titre)
	_infos = Label.new()
	_infos.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_infos.custom_minimum_size = Vector2(560, 0)
	_infos.add_theme_font_size_override("font_size", 14)
	boite.add_child(_infos)
	_zone_coffre = HBoxContainer.new()
	_zone_coffre.add_theme_constant_override("separation", 18)
	boite.add_child(_zone_coffre)
	_grille_coffre = _grille(_zone_coffre, "Coffre", 4)
	_grille_inv = _grille(_zone_coffre, "Inventaire", 6)
	var ligne := HBoxContainer.new()
	ligne.alignment = BoxContainer.ALIGNMENT_CENTER
	ligne.add_theme_constant_override("separation", 8)
	boite.add_child(ligne)
	for genre in ["renforcer", "reparer", "demonter"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 46)
		b.pressed.connect(func(): action.emit(genre, int(rec.get("id", -1)), 0))
		ligne.add_child(b)
		_boutons[genre] = b
	var fermer := Button.new()
	fermer.text = "Fermer"
	fermer.custom_minimum_size = Vector2(110, 46)
	fermer.pressed.connect(fermer_fenetre)
	ligne.add_child(fermer)
	rafraichir()


func _grille(parent: Control, titre: String, colonnes: int) -> GridContainer:
	var v := VBoxContainer.new()
	parent.add_child(v)
	var l := Label.new()
	l.text = titre
	l.add_theme_font_size_override("font_size", 14)
	v.add_child(l)
	var g := GridContainer.new()
	g.columns = colonnes
	g.add_theme_constant_override("h_separation", 3)
	g.add_theme_constant_override("v_separation", 3)
	v.add_child(g)
	return g


func ouvrir(p_rec: Dictionary, p_allie: bool, inv: Array) -> void:
	rec = p_rec
	allie = p_allie
	inventaire = inv
	contenu = []
	visible = true
	rafraichir()


func fermer_fenetre() -> void:
	if visible and not rec.is_empty():
		action.emit("fermer", int(rec.id), 0)
	visible = false


func rafraichir() -> void:
	if _titre == null or rec.is_empty():
		return
	var b := Batiments.infos(rec.type)
	var nom: String = b.get("nom", rec.type)
	_titre.text = nom + ("" if int(rec.niv) == 0 else "  (renforcé %d)" % int(rec.niv))
	var lignes := ["Vie : %d / %d   ·   %s   ·   %s" % [rec.vie, rec.max, Batiments.NOMS_MATERIAUX[b.materiau],
		"à toi ou ton équipe" if allie else "à %s" % rec.proprio]]
	if rec.proprio == "":
		lignes[0] = "Vie : %d / %d   ·   sans propriétaire" % [rec.vie, rec.max]
	var mult: Dictionary = Batiments.MULTIPLICATEURS[b.materiau]
	var parts := []
	for t in Batiments.TYPES_DEGATS:
		parts.append("%s ×%s" % [Batiments.TYPES_DEGATS[t], str(snappedf(float(mult[t]) * (1.0 - Batiments.REDUCTION_NIVEAU * int(rec.niv)), 0.01))])
	lignes.append("Dégâts subis : " + ", ".join(PackedStringArray(parts)))
	match str(rec.type):
		"coeur_base":
			lignes.append("Base sur %d cases autour. Avec un lit dans la base, ton équipe y réapparaît." % Batiments.RAYON_BASE)
		"tourelle":
			lignes.append("Tire sur les ennemis à %d pixels, même quand tu n'es pas connecté." % int(Batiments.infos("tourelle").portee))
		"porte_bois", "porte_metal":
			lignes.append("S'ouvre toute seule devant toi et ton équipe.")
	_infos.text = "\n".join(PackedStringArray(lignes))
	var renfort := Batiments.cout_renfort(rec.type, int(rec.niv))
	_boutons.renforcer.text = "Renforcer (%s)" % _cout(renfort) if not renfort.is_empty() else "Renfort maximum"
	_boutons.renforcer.disabled = renfort.is_empty() or not _peut_payer(renfort)
	var repar := Batiments.cout_reparation(rec.type, int(rec.max) - int(rec.vie))
	_boutons.reparer.text = "Réparer (%s)" % _cout(repar) if not repar.is_empty() else "Intact"
	_boutons.reparer.disabled = repar.is_empty() or not _peut_payer(repar)
	_boutons.demonter.text = "Démonter"
	for g in _boutons:
		_boutons[g].visible = allie and not rec.get("temporaire", false)
	# Coffre
	var est_coffre := b.has("cases")
	_zone_coffre.visible = est_coffre
	if est_coffre:
		_remplir(_grille_coffre, contenu, int(b.cases), "prendre")
		_remplir(_grille_inv, inventaire, Objets.TAILLE_INVENTAIRE, "deposer")


func _cout(cout: Dictionary) -> String:
	var parts := []
	for id in cout:
		parts.append("%d %s" % [cout[id], Objets.infos(id).nom])
	return ", ".join(PackedStringArray(parts))


func _peut_payer(cout: Dictionary) -> bool:
	for id in cout:
		if Objets.compter(inventaire, id) < int(cout[id]):
			return false
	return true


func _remplir(g: GridContainer, objets: Array, n: int, genre: String) -> void:
	while g.get_child_count() < n:
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var i := g.get_child_count()
		b.pressed.connect(func(): action.emit(genre, int(rec.get("id", -1)), i))
		var nb := Label.new()
		nb.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
		nb.position = Vector2(-30, -20)
		nb.custom_minimum_size = Vector2(26, 0)
		nb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		nb.add_theme_font_size_override("font_size", 13)
		nb.add_theme_constant_override("outline_size", 5)
		nb.add_theme_color_override("font_outline_color", Color.BLACK)
		nb.mouse_filter = MOUSE_FILTER_IGNORE
		b.add_child(nb)
		g.add_child(b)
	while g.get_child_count() > n:
		var dernier := g.get_child(g.get_child_count() - 1)
		g.remove_child(dernier)
		dernier.queue_free()
	for i in n:
		var b: Button = g.get_child(i)
		var o: Dictionary = objets[i] if i < objets.size() and objets[i] is Dictionary else {}
		b.icon = null if o.is_empty() else Objets.icone(o.id)
		b.tooltip_text = "" if o.is_empty() else Equipement.nom_objet(o)
		b.disabled = o.is_empty()
		var nb: Label = b.get_child(0)
		nb.text = "" if o.is_empty() or int(o.n) <= 1 else str(o.n)
