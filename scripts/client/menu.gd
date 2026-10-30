extends Node
## Menu principal : pseudo, apparence, adresse du serveur. Le monde défile derrière.

const FICHIER := "user://client.json"

var message_initial := ""
var reglages := {}
var _pseudo: LineEdit
var _adresse: LineEdit
var _apercu: TextureRect
var _etat: Label
var _bouton: Button
var _camera: Camera2D
var _angle := 0.0


func _ready() -> void:
	_charger()
	# Fond : un monde qui défile lentement.
	var vue := VueMonde.new(Monde.new(1234, true))
	add_child(vue)
	for y in range(-2, 2):
		for x in range(-2, 2):
			vue.afficher_morceau(Vector2i(x, y))
	vue.definir_heure(17.6)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(2, 2)
	vue.add_child(_camera)
	_camera.make_current()

	var calque := CanvasLayer.new()
	add_child(calque)
	var racine := Control.new()
	racine.theme = ThemeJeu.creer()
	racine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	calque.add_child(racine)
	var voile := ColorRect.new()
	voile.color = Color(0, 0, 0, 0.25)
	voile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	racine.add_child(voile)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	racine.add_child(centre)
	var panneau := PanelContainer.new()
	panneau.custom_minimum_size = Vector2(440, 0)
	centre.add_child(panneau)
	var boite := VBoxContainer.new()
	boite.add_theme_constant_override("separation", 10)
	panneau.add_child(boite)

	var titre := Label.new()
	titre.text = "CRAFTCLANS"
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titre.add_theme_font_size_override("font_size", 52)
	titre.add_theme_color_override("font_color", Color(0.55, 0.88, 0.5))
	titre.add_theme_constant_override("outline_size", 12)
	titre.add_theme_color_override("font_outline_color", Color(0.06, 0.12, 0.08))
	boite.add_child(titre)
	var sous_titre := Label.new()
	sous_titre.text = "version %s" % Config.version
	sous_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sous_titre.modulate = Color(1, 1, 1, 0.6)
	sous_titre.add_theme_font_size_override("font_size", 14)
	boite.add_child(sous_titre)

	boite.add_child(_texte("Pseudo"))
	_pseudo = LineEdit.new()
	_pseudo.text = reglages.pseudo
	_pseudo.max_length = 16
	_pseudo.placeholder_text = "2 à 16 caractères"
	boite.add_child(_pseudo)

	boite.add_child(_texte("Apparence"))
	var ligne := HBoxContainer.new()
	ligne.alignment = BoxContainer.ALIGNMENT_CENTER
	boite.add_child(ligne)
	var prec := Button.new()
	prec.text = " < "
	prec.pressed.connect(_changer_apparence.bind(-1))
	ligne.add_child(prec)
	_apercu = TextureRect.new()
	_apercu.custom_minimum_size = Vector2(96, 96)
	_apercu.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_apercu.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ligne.add_child(_apercu)
	var suiv := Button.new()
	suiv.text = " > "
	suiv.pressed.connect(_changer_apparence.bind(1))
	ligne.add_child(suiv)
	_changer_apparence(0)

	boite.add_child(_texte("Adresse du serveur"))
	_adresse = LineEdit.new()
	_adresse.text = reglages.adresse
	_adresse.placeholder_text = "ex : 86.12.34.56 ou monserveur.duckdns.org"
	boite.add_child(_adresse)

	_bouton = Button.new()
	_bouton.text = "Rejoindre le monde"
	_bouton.custom_minimum_size = Vector2(0, 52)
	_bouton.pressed.connect(_rejoindre)
	boite.add_child(_bouton)
	_pseudo.text_submitted.connect(func(_t): _rejoindre())
	_adresse.text_submitted.connect(func(_t): _rejoindre())

	_etat = Label.new()
	_etat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_etat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etat.add_theme_color_override("font_color", Color(1, 0.75, 0.5))
	_etat.text = message_initial
	boite.add_child(_etat)

	if not OS.has_feature("mobile"):
		var quitter := Button.new()
		quitter.text = "Quitter"
		quitter.pressed.connect(func(): get_tree().quit())
		boite.add_child(quitter)

	Reseau.echec.connect(_sur_echec)
	Reseau.tentative.connect(func(url): _etat.text = "Connexion à %s…" % url.replace("ws://", ""))
	Reseau.deconnecte.connect(_sur_echec)
	Reseau.accueil.connect(_sur_accueil)

	if Config.auto_connexion != "":
		_pseudo.text = Config.auto_connexion.get_slice("@", 0)
		_adresse.text = Config.auto_connexion.get_slice("@", 1)
		_rejoindre.call_deferred()


func _texte(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.modulate = Color(1, 1, 1, 0.75)
	return l


func _process(delta: float) -> void:
	_angle += delta * 0.05
	_camera.position = Vector2(cos(_angle), sin(_angle * 0.7)) * 700.0


func _changer_apparence(sens: int) -> void:
	reglages.apparence = posmod(int(reglages.apparence) + sens, Config.NB_APPARENCES)
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/personnages/perso_%d.png" % reglages.apparence)
	at.region = Rect2(0, 0, 32, 32)
	_apercu.texture = at


func _rejoindre() -> void:
	var pseudo := _pseudo.text.strip_edges()
	if pseudo.length() < 2:
		_etat.text = "Choisis un pseudo d'au moins 2 caractères."
		return
	reglages.pseudo = pseudo
	reglages.adresse = _adresse.text.strip_edges()
	_sauver()
	_bouton.disabled = true
	Reseau.connecter(reglages.adresse, {
		"pseudo": pseudo, "jeton": reglages.jeton, "apparence": int(reglages.apparence),
		"version": Config.version, "protocole": Config.PROTOCOLE,
	})


func _sur_echec(raison: String) -> void:
	print("Connexion : ", raison)
	_bouton.disabled = false
	_etat.text = raison


func _sur_accueil(infos: Dictionary) -> void:
	get_parent().aller_au_jeu(infos)


func _charger() -> void:
	reglages = {"pseudo": "", "adresse": "localhost", "apparence": 0, "jeton": ""}
	if FileAccess.file_exists(FICHIER):
		var lu = JSON.parse_string(FileAccess.get_file_as_string(FICHIER))
		if typeof(lu) == TYPE_DICTIONARY:
			reglages.merge(lu, true)
	if reglages.jeton == "":
		# Identifiant secret de cet appareil : il protège le pseudo sur le serveur.
		var octets := Crypto.new().generate_random_bytes(16)
		reglages.jeton = octets.hex_encode()
		_sauver()


func _sauver() -> void:
	var f := FileAccess.open(FICHIER, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(reglages, "\t"))
