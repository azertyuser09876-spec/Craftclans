extends Node
## Partie en cours côté joueur.
##
## Déplacement : le joueur bouge tout de suite à l'écran (prédiction), envoie chaque
## entrée numérotée au serveur, et quand le serveur répond avec sa position officielle,
## on rejoue les entrées pas encore confirmées. Les autres joueurs sont interpolés.

var infos: Dictionary
var monde: Monde
var vue: VueMonde
var moi: JoueurVisuel
var camera: Camera2D
var autres := {} # id -> JoueurVisuel
var mon_id := 0
var reglages := {"mode_dev": false, "cheats": false, "admin": false, "vitesse": Config.VITESSE_JOUEUR, "vol": false, "dieu": false}
var heure := 9.0

var _pos := Vector2.ZERO # position prédite
var _correction := Vector2.ZERO # écart visuel résorbé en douceur
var _seq := 0
var _en_attente: Array = [] # [seq, direction] pas encore confirmées
var _derniere_dir := Vector2.ZERO
var _ping := 0
var _accu_ping := 0.0
var _debug := false
var _temps_auto := 0.0
var _ecart_max := 0.0 # plus grand écart prédiction/serveur (infos de debug)

# Interface
var _ui: Control
var _info: Label
var _debug_label: Label
var _journal: VBoxContainer
var _saisie: LineEdit
var _banniere: Label
var _menu_pause: PanelContainer
var _joystick: Joystick
var _debug_dessin: Node2D


func _ready() -> void:
	mon_id = int(infos.id)
	heure = float(infos.heure)
	monde = Monde.new(int(infos.graine))
	vue = VueMonde.new(monde)
	add_child(vue)
	_pos = infos.pos
	moi = JoueurVisuel.new(str(infos.nom), int(infos.apparence))
	moi.position = _pos
	vue.objets.add_child(moi)
	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	moi.add_child(camera)
	camera.make_current()
	_debug_dessin = Node2D.new()
	_debug_dessin.z_index = 100
	_debug_dessin.draw.connect(_dessiner_debug)
	vue.add_child(_debug_dessin)
	for id in infos.joueurs:
		_ajouter_autre(int(id), infos.joueurs[id])
	_creer_interface()
	_ajouter_message("Connecté à %s (serveur %s)." % [infos.serveur, infos.version], "systeme")
	if str(infos.motd) != "":
		_ajouter_message(str(infos.motd), "annonce")
	for nom in infos.get("boss_actifs", []):
		_ajouter_message("Boss mondial réveillé : %s" % nom, "boss")
	Reseau.etat_recu.connect(_sur_etat)
	Reseau.joueur_arrive.connect(_ajouter_autre)
	Reseau.joueur_parti.connect(_retirer_autre)
	Reseau.message_recu.connect(_ajouter_message)
	Reseau.reglages_recus.connect(_sur_reglages)
	Reseau.teleporte.connect(_sur_teleport)
	Reseau.evenement.connect(_sur_evenement)
	Reseau.deconnecte.connect(_sur_deconnexion)
	Reseau.pong.connect(func(ms): _ping = ms)
	if Config.auto_commande != "":
		for c in Config.auto_commande.split(";"):
			Reseau.c_chat.rpc_id(1, c)


# ------------------------------------------------------------------ Boucle

func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if not _saisie.has_focus() and not _menu_pause.visible:
		dir = Input.get_vector("gauche", "droite", "haut", "bas")
		if _joystick and _joystick.vecteur != Vector2.ZERO:
			dir = _joystick.vecteur
	if Config.auto_deplacement:
		_temps_auto += 1.0 / 60.0
		dir = Vector2(cos(_temps_auto * 0.8), sin(_temps_auto * 0.8))
		if int(_temps_auto * 60) % 120 == 0:
			print("[test] %s pos=%s attente=%d autres=%d heure=%.2f ping=%d ecart_max=%.2f" % [infos.nom, _pos.round(), _en_attente.size(), autres.size(), heure, _ping, _ecart_max])
	if dir != Vector2.ZERO or _derniere_dir != Vector2.ZERO:
		_seq += 1
		Reseau.c_entree.rpc_id(1, _seq, dir)
		_en_attente.append([_seq, dir])
		_pos = Regles.deplacer(monde, _pos, dir, reglages.vitesse, reglages.vol)
	_derniere_dir = dir


func _process(delta: float) -> void:
	_correction = _correction.lerp(Vector2.ZERO, minf(delta * 10.0, 1.0))
	moi.position = _pos + _correction
	for a in autres.values():
		a.interpoler()
	vue.definir_heure(heure)
	var lum := 0.9 if VueMonde.est_nuit(heure) else 0.0
	moi.lumiere.energy = lum
	for a in autres.values():
		a.lumiere.energy = lum
	_accu_ping += delta
	if _accu_ping > 2.0:
		_accu_ping = 0.0
		Reseau.c_ping.rpc_id(1, Time.get_ticks_msec())
	_info.text = "Craftclans %s  |  %d joueur(s)  |  ping %d ms  |  %02d:%02d" % [
		Config.version, autres.size() + 1, _ping, int(heure), int(fmod(heure, 1.0) * 60)]
	var montrer_debug: bool = _debug and (reglages.mode_dev or reglages.admin)
	_debug_label.visible = montrer_debug
	if montrer_debug:
		var c := Vector2i(_pos / Config.TAILLE_TUILE)
		_debug_label.text = "FPS %d\nCase %d, %d\nPosition %.0f, %.0f\nEntrées en attente %d (écart max %.1f)\nVitesse %.0f%s%s\nGraine %d" % [
			Engine.get_frames_per_second(), c.x, c.y, _pos.x, _pos.y, _en_attente.size(), _ecart_max,
			reglages.vitesse, "  [vol]" if reglages.vol else "", "  [dieu]" if reglages.dieu else "", monde.graine]
	_debug_dessin.visible = montrer_debug
	if montrer_debug:
		_debug_dessin.queue_redraw()


func _dessiner_debug() -> void:
	var t := Config.TAILLE_TUILE
	var c := Vector2i(_pos / t)
	for y in range(c.y - 6, c.y + 7):
		for x in range(c.x - 8, c.x + 9):
			if monde.case_bloquante(x, y):
				var r := Rect2(x * t, y * t, t, t)
				if monde.sol_en(x, y) != Monde.Sol.EAU:
					r = r.grow(-8)
				_debug_dessin.draw_rect(r, Color(1, 0.2, 0.2, 0.35))
	_debug_dessin.draw_circle(_pos, Config.RAYON_JOUEUR, Color(0.2, 1, 0.3, 0.5))
	for a in autres.values():
		_debug_dessin.draw_circle(a.position, Config.RAYON_JOUEUR, Color(0.3, 0.6, 1, 0.5))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat"):
		if _saisie.has_focus():
			_envoyer_saisie()
		else:
			_ouvrir_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug"):
		_debug = not _debug
		if not (reglages.mode_dev or reglages.admin):
			_ajouter_message("Le mode développeur est désactivé sur ce serveur.", "systeme")
	elif event.is_action_pressed("menu"):
		if _saisie.has_focus():
			_saisie.release_focus()
			_saisie.visible = false
		else:
			_menu_pause.visible = not _menu_pause.visible


# ------------------------------------------------------------------ Réseau

func _sur_etat(etat: Dictionary) -> void:
	heure = float(etat.h)
	for id in etat.j:
		var d: Array = etat.j[id]
		var p := Vector2(d[0], d[1])
		if int(id) == mon_id:
			_reconcilier(p, int(d[2]))
		elif autres.has(int(id)):
			autres[int(id)].ajouter_instantane(p)


func _reconcilier(pos_serveur: Vector2, seq_confirmee: int) -> void:
	while not _en_attente.is_empty() and _en_attente[0][0] <= seq_confirmee:
		_en_attente.pop_front()
	var p := pos_serveur
	for e in _en_attente:
		p = Regles.deplacer(monde, p, e[1], reglages.vitesse, reglages.vol)
	var ecart := _pos - p
	_ecart_max = maxf(_ecart_max, ecart.length())
	if ecart.length() < 64.0:
		_correction += ecart
	_pos = p


func _sur_teleport(pos: Vector2) -> void:
	_en_attente.clear()
	_pos = pos
	_correction = Vector2.ZERO
	camera.reset_smoothing()


func _sur_reglages(r: Dictionary) -> void:
	reglages.merge(r, true)
	moi.etiquette.add_theme_color_override("font_color", Color(1, 0.85, 0.35) if reglages.admin else Color.WHITE)


func _ajouter_autre(id: int, i: Dictionary) -> void:
	if id == mon_id or autres.has(id):
		return
	var j := JoueurVisuel.new(str(i.nom), int(i.apparence), bool(i.get("admin", false)))
	j.position = i.pos
	j.ajouter_instantane(i.pos)
	vue.objets.add_child(j)
	autres[id] = j


func _retirer_autre(id: int) -> void:
	if autres.has(id):
		autres[id].queue_free()
		autres.erase(id)


func _sur_evenement(genre: String, d: Dictionary) -> void:
	match genre:
		"bulle":
			var id := int(d.id)
			if id == mon_id:
				moi.dire(str(d.texte))
			elif autres.has(id):
				autres[id].dire(str(d.texte))
		"boss":
			_banniere.text = "%s s'est réveillé !\n%s" % [d.nom, d.lieu]
			_banniere.modulate.a = 1.0
			var tw := create_tween()
			tw.tween_interval(5.0)
			tw.tween_property(_banniere, "modulate:a", 0.0, 1.5)


func _sur_deconnexion(raison: String) -> void:
	get_parent().aller_au_menu(raison)


func _quitter_vers_menu() -> void:
	Reseau.deconnecte.disconnect(_sur_deconnexion)
	Reseau.fermer()
	get_parent().aller_au_menu("")


# ------------------------------------------------------------------ Interface

func _creer_interface() -> void:
	var calque := CanvasLayer.new()
	add_child(calque)
	_ui = Control.new()
	_ui.theme = ThemeJeu.creer()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	calque.add_child(_ui)

	_info = Label.new()
	_info.position = Vector2(12, 8)
	_info.add_theme_font_size_override("font_size", 15)
	_ui.add_child(_info)

	_debug_label = Label.new()
	_debug_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_label.position = Vector2(-260, 40)
	_debug_label.custom_minimum_size = Vector2(250, 0)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	_ui.add_child(_debug_label)

	_banniere = Label.new()
	_banniere.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banniere.position = Vector2(-400, 70)
	_banniere.custom_minimum_size = Vector2(800, 0)
	_banniere.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banniere.add_theme_font_size_override("font_size", 34)
	_banniere.add_theme_color_override("font_color", Color(1, 0.45, 0.3))
	_banniere.add_theme_constant_override("outline_size", 10)
	_banniere.add_theme_color_override("font_outline_color", Color(0.15, 0.03, 0.02))
	_banniere.modulate.a = 0.0
	_ui.add_child(_banniere)

	_journal = VBoxContainer.new()
	_journal.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_journal.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_journal.position = Vector2(12, -70)
	_journal.custom_minimum_size = Vector2(560, 0)
	_journal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_journal.alignment = BoxContainer.ALIGNMENT_END
	_ui.add_child(_journal)
	if Config.est_mobile():
		# Sur téléphone, le chat est en haut pour laisser la place au joystick.
		_journal.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_journal.grow_vertical = Control.GROW_DIRECTION_END
		_journal.position = Vector2(12, 40)

	_saisie = LineEdit.new()
	_saisie.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_saisie.position = Vector2(12, -56)
	_saisie.custom_minimum_size = Vector2(560, 44)
	_saisie.placeholder_text = "Message, ou /aide pour les commandes"
	_saisie.max_length = 200
	_saisie.visible = false
	_saisie.text_submitted.connect(func(_t): _envoyer_saisie())
	_ui.add_child(_saisie)
	if Config.est_mobile():
		_saisie.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_saisie.position = Vector2(-280, 8)

	if Config.est_mobile():
		_joystick = Joystick.new()
		_ui.add_child(_joystick)
		var bouton_chat := Button.new()
		bouton_chat.text = "Chat"
		bouton_chat.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		bouton_chat.position = Vector2(-200, 10)
		bouton_chat.custom_minimum_size = Vector2(90, 56)
		bouton_chat.pressed.connect(_ouvrir_chat)
		_ui.add_child(bouton_chat)
		var bouton_menu := Button.new()
		bouton_menu.text = "Menu"
		bouton_menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		bouton_menu.position = Vector2(-100, 10)
		bouton_menu.custom_minimum_size = Vector2(90, 56)
		bouton_menu.pressed.connect(func(): _menu_pause.visible = not _menu_pause.visible)
		_ui.add_child(bouton_menu)

	_menu_pause = PanelContainer.new()
	_menu_pause.set_anchors_preset(Control.PRESET_CENTER)
	_menu_pause.position = Vector2(-160, -110)
	_menu_pause.custom_minimum_size = Vector2(320, 0)
	_menu_pause.visible = false
	_ui.add_child(_menu_pause)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_menu_pause.add_child(vb)
	var titre := Label.new()
	titre.text = "Pause (le monde continue !)"
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(titre)
	for b in [["Reprendre", func(): _menu_pause.visible = false], ["Quitter vers le menu", _quitter_vers_menu]]:
		var bouton := Button.new()
		bouton.text = b[0]
		bouton.custom_minimum_size = Vector2(0, 48)
		bouton.pressed.connect(b[1])
		vb.add_child(bouton)
	var aide := Label.new()
	aide.text = "ZQSD ou flèches : se déplacer\nEntrée : chat (/aide)\nF3 : infos développeur"
	aide.add_theme_font_size_override("font_size", 14)
	aide.modulate.a = 0.7
	vb.add_child(aide)


func _ouvrir_chat() -> void:
	_saisie.visible = true
	_saisie.grab_focus()


func _envoyer_saisie() -> void:
	var t := _saisie.text.strip_edges()
	_saisie.text = ""
	_saisie.release_focus()
	_saisie.visible = false
	if t != "":
		Reseau.c_chat.rpc_id(1, t)


const COULEURS := {
	"chat": Color(1, 1, 1), "systeme": Color(0.7, 0.8, 0.9), "annonce": Color(1, 0.85, 0.35),
	"commande": Color(0.6, 1, 0.65), "boss": Color(1, 0.5, 0.35),
}


func _ajouter_message(texte: String, genre: String) -> void:
	var l := Label.new()
	l.text = texte
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", COULEURS.get(genre, Color.WHITE))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_journal.add_child(l)
	if Config.est_mobile():
		_journal.move_child(l, _journal.get_child_count() - 1)
	while _journal.get_child_count() > 8:
		var vieux := _journal.get_child(0)
		_journal.remove_child(vieux)
		vieux.queue_free()
	var duree := 30.0 if genre == "commande" else 12.0
	var tw := l.create_tween()
	tw.tween_interval(duree)
	tw.tween_property(l, "modulate:a", 0.0, 2.0)
	tw.tween_callback(l.queue_free)
