extends Control
## Programme de gestion du serveur : la fenêtre qui s'ouvre quand on lance le serveur.
## Onglets : tableau de bord, joueurs, monde et triches, boss mondiaux, console.

var serveur: Node
var _statut: Label
var _carte: Control
var _textures_carte := {} # Vector2i -> ImageTexture
var _liste_joueurs: VBoxContainer
var _liste_connus: VBoxContainer
var _liste_boss: VBoxContainer
var _console: RichTextLabel
var _saisie: LineEdit
var _heure: HSlider
var _vitesse_temps: SpinBox
var _mode_dev: CheckButton
var _cheats: CheckButton
var _pvp: CheckButton
var _labels_vie := {} # pseudo -> Label (vie mise à jour chaque seconde)
var _mdp: LineEdit
var _motd: LineEdit
var _nom: LineEdit
var _a_rafraichir := true
var _maj_en_cours := false


func _init(p_serveur: Node) -> void:
	serveur = p_serveur


func _ready() -> void:
	theme = ThemeJeu.creer()
	theme.default_font_size = 16
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var fond := ColorRect.new()
	fond.color = Color(0.07, 0.09, 0.12)
	fond.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(fond)
	var marge := MarginContainer.new()
	marge.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for c in ["left", "right", "top", "bottom"]:
		marge.add_theme_constant_override("margin_" + c, 10)
	add_child(marge)
	var onglets := TabContainer.new()
	marge.add_child(onglets)
	onglets.add_child(_onglet_tableau())
	onglets.add_child(_onglet_joueurs())
	onglets.add_child(_onglet_monde())
	onglets.add_child(_onglet_boss())
	onglets.add_child(_onglet_console())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--onglet="): # option de test : ouvrir un onglet précis
			onglets.current_tab = int(arg.get_slice("=", 1))
	serveur.journal_ajoute.connect(_sur_journal)
	serveur.etat_change.connect(func(): _a_rafraichir = true)
	var minuteur := Timer.new()
	minuteur.wait_time = 1.0
	minuteur.autostart = true
	minuteur.timeout.connect(_chaque_seconde)
	add_child(minuteur)
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		serveur.arreter()


# ------------------------------------------------------------------ Outils

func _vbox(nom: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = nom
	v.add_theme_constant_override("separation", 8)
	return v


func _defilant(contenu: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	contenu.size_flags_horizontal = SIZE_EXPAND_FILL
	s.add_child(contenu)
	return s


func _titre(texte: String) -> Label:
	var l := Label.new()
	l.text = texte
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", ThemeJeu.ACCENT)
	return l


func _bouton(texte: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = texte
	b.pressed.connect(action)
	return b


func _ligne(enfants: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for e in enfants:
		h.add_child(e)
	return h


func _label(texte: String, largeur := 0) -> Label:
	var l := Label.new()
	l.text = texte
	if largeur > 0:
		l.custom_minimum_size.x = largeur
		l.clip_text = true
	return l


func _vider(conteneur: Node) -> void:
	for e in conteneur.get_children():
		e.queue_free()


func _executer(commande: String) -> void:
	serveur.journal("> " + commande)
	var reponse: String = serveur.commandes.executer(commande)
	for ligne in reponse.split("\n"):
		serveur.journal(ligne)


# ------------------------------------------------------------------ Tableau de bord

func _onglet_tableau() -> Control:
	var v := _vbox("Tableau de bord")
	var h := HBoxContainer.new()
	h.size_flags_vertical = SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var gauche := _vbox("g")
	gauche.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(gauche)
	gauche.add_child(_titre("Serveur"))
	_statut = _label("")
	_statut.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gauche.add_child(_statut)
	gauche.add_child(_ligne([
		_bouton("Sauvegarder maintenant", func(): _executer("sauver")),
		_bouton("Copie de secours", func(): serveur.sauvegarde.copie_de_secours(); serveur.journal("Copie de secours faite.")),
		_bouton("Ouvrir le dossier", func(): OS.shell_open(Sauvegarde.chemin_reel())),
	]))
	gauche.add_child(_ligne([_bouton("Arrêter le serveur", serveur.arreter)]))
	gauche.add_child(_titre("Réglages"))
	_nom = LineEdit.new()
	_nom.text = serveur.config.nom
	_nom.size_flags_horizontal = SIZE_EXPAND_FILL
	gauche.add_child(_ligne([_label("Nom du serveur", 190), _nom]))
	_motd = LineEdit.new()
	_motd.text = serveur.config.message_du_jour
	_motd.size_flags_horizontal = SIZE_EXPAND_FILL
	gauche.add_child(_ligne([_label("Message du jour", 190), _motd]))
	_mdp = LineEdit.new()
	_mdp.text = serveur.config.mot_de_passe_admin
	_mdp.secret = true
	_mdp.size_flags_horizontal = SIZE_EXPAND_FILL
	var voir := CheckButton.new()
	voir.text = "voir"
	voir.toggled.connect(func(on): _mdp.secret = not on)
	gauche.add_child(_ligne([_label("Mot de passe admin", 190), _mdp, voir]))
	gauche.add_child(_ligne([_bouton("Enregistrer les réglages", _enregistrer_config)]))
	var aide := _label("En jeu, un joueur tape /login <mot de passe> pour devenir admin.\nLe premier joueur à se connecter à un nouveau serveur devient admin automatiquement.\nLe port se change dans config.json (dossier des sauvegardes) puis redémarrage.")
	aide.modulate.a = 0.6
	aide.add_theme_font_size_override("font_size", 14)
	gauche.add_child(aide)
	var droite := _vbox("d")
	h.add_child(droite)
	droite.add_child(_titre("Carte"))
	_carte = Control.new()
	_carte.custom_minimum_size = Vector2(384, 384)
	_carte.draw.connect(_dessiner_carte)
	droite.add_child(_carte)
	return v


func _enregistrer_config() -> void:
	serveur.config.nom = _nom.text.strip_edges()
	serveur.config.message_du_jour = _motd.text.strip_edges()
	if _mdp.text.strip_edges().length() >= 4:
		serveur.config.mot_de_passe_admin = _mdp.text.strip_edges()
	Sauvegarde.enregistrer_config(serveur.config)
	serveur.journal("Réglages du serveur enregistrés.")


func _dessiner_carte() -> void:
	if serveur.monde == null:
		return
	# Cadre : tous les morceaux explorés (et les joueurs), au moins 6×6 morceaux.
	var mini := Vector2i(-3, -3)
	var maxi := Vector2i(2, 2)
	for cle in serveur.cartes:
		mini = Vector2i(mini.x if mini.x < cle.x else cle.x, mini.y if mini.y < cle.y else cle.y)
		maxi = Vector2i(maxi.x if maxi.x > cle.x else cle.x, maxi.y if maxi.y > cle.y else cle.y)
	if _textures_carte.size() > serveur.cartes.size():
		_textures_carte.clear() # le monde a été remis à zéro
	var cote := maxi(maxi.x - mini.x, maxi.y - mini.y) + 1
	var taille := _carte.size.x
	var px_morceau := taille / cote
	_carte.draw_rect(Rect2(Vector2.ZERO, Vector2(taille, taille)), Color(0.05, 0.06, 0.08))
	for cle in serveur.cartes:
		if not _textures_carte.has(cle):
			_textures_carte[cle] = ImageTexture.create_from_image(serveur.cartes[cle])
		_carte.draw_texture_rect(_textures_carte[cle], Rect2(Vector2(cle - mini) * px_morceau, Vector2(px_morceau, px_morceau)), false)
	var echelle := px_morceau / (Monde.TAILLE_MORCEAU * Config.TAILLE_TUILE)
	var origine := -Vector2(mini) * Monde.TAILLE_MORCEAU * Config.TAILLE_TUILE
	_carte.draw_circle((origine) * echelle, 3, Color(1, 0.5, 0.2))
	for s in serveur.joueurs.values():
		var p: Vector2 = (s.pos + origine) * echelle
		_carte.draw_circle(p, 5, Color.BLACK)
		_carte.draw_circle(p, 4, Color(1, 0.85, 0.3) if serveur.est_admin(s.nom) else Color.WHITE)
		_carte.draw_string(get_theme_default_font(), p + Vector2(7, 4), s.nom, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	_carte.draw_string(get_theme_default_font(), Vector2(4, taille - 6), "%d morceaux explorés" % serveur.cartes.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)


# ------------------------------------------------------------------ Joueurs

func _onglet_joueurs() -> Control:
	var v := _vbox("Joueurs")
	v.add_child(_titre("Connectés"))
	_liste_joueurs = _vbox("liste")
	v.add_child(_liste_joueurs)
	v.add_child(_titre("Tous les joueurs connus et bannis"))
	_liste_connus = _vbox("connus")
	v.add_child(_defilant(_liste_connus))
	return v


func _texte_vie(s: Dictionary) -> String:
	return "%s %d/%d%s" % [Roles.donnees(s.role).nom, s.vie, s.vie_max, " (mort)" if s.mort else ""]


func _label_vie(s: Dictionary) -> Label:
	var l := _label(_texte_vie(s), 190)
	_labels_vie[s.nom] = l
	return l


func _rafraichir_joueurs() -> void:
	_labels_vie.clear()
	_vider(_liste_joueurs)
	if serveur.joueurs.is_empty():
		_liste_joueurs.add_child(_label("Personne n'est connecté."))
	for s in serveur.joueurs.values():
		var nom: String = s.nom
		var admin: bool = serveur.est_admin(nom)
		var vitesse_x2: bool = s.vitesse > 1.0
		_liste_joueurs.add_child(_ligne([
			_label(nom + (" [admin]" if admin else ""), 150),
			_label_vie(s),
			_bouton("Soigner", func(): serveur.combat.soigner(serveur.session_par_nom(nom), 9999)),
			_bouton("Tuer", func():
				var cible: Dictionary = serveur.session_par_nom(nom)
				if not cible.is_empty() and not cible.mort: serveur.combat.mourir(cible, "l'admin")),
			_bouton("Retirer admin" if admin else "Rendre admin", func(): serveur.definir_admin(nom, not admin)),
			_bouton("TP au centre", func(): serveur.teleporter(serveur.session_par_nom(nom), serveur.monde.centre())),
			_bouton("Vitesse x1" if vitesse_x2 else "Vitesse x2", func(): serveur.definir_cheat(serveur.session_par_nom(nom), "vitesse", 1.0 if vitesse_x2 else 2.0)),
			_bouton("Vol : " + ("oui" if s.vol else "non"), func(): serveur.definir_cheat(serveur.session_par_nom(nom), "vol", not s.vol)),
			_bouton("Dieu : " + ("oui" if s.dieu else "non"), func(): serveur.definir_cheat(serveur.session_par_nom(nom), "dieu", not s.dieu)),
			_bouton("Expulser", func(): serveur.expulser(nom, "")),
			_bouton("Bannir", func(): serveur.bannir(nom, "Banni depuis le panneau")),
		]))
	_vider(_liste_connus)
	for nom in serveur.donnees.joueurs:
		var fiche: Dictionary = serveur.donnees.joueurs[nom]
		var en_ligne: bool = not serveur.session_par_nom(nom).is_empty()
		var elements := [_label(nom, 170), _label("en ligne" if en_ligne else "vu le " + str(fiche.get("vu_le", "?")).replace("T", " "), 220),
			_label("admin" if fiche.get("admin", false) else "", 70)]
		if not en_ligne:
			elements.append(_bouton("Oublier (libère le pseudo)", func(): serveur.oublier_joueur(nom)))
		_liste_connus.add_child(_ligne(elements))
	for nom in serveur.donnees.bannis:
		_liste_connus.add_child(_ligne([_label(nom, 170), _label("BANNI : " + str(serveur.donnees.bannis[nom]), 290),
			_bouton("Débannir", func(): serveur.debannir(nom))]))


# ------------------------------------------------------------------ Monde, triches, mode dev

func _onglet_monde() -> Control:
	var v := _vbox("Monde et triches")
	v.add_child(_titre("Temps"))
	_heure = HSlider.new()
	_heure.min_value = 0
	_heure.max_value = 24
	_heure.step = 0.25
	_heure.custom_minimum_size.x = 400
	_heure.value_changed.connect(func(h): if not _maj_en_cours: serveur.definir_heure(h))
	v.add_child(_ligne([_label("Heure du jeu", 190), _heure]))
	_vitesse_temps = SpinBox.new()
	_vitesse_temps.min_value = 0
	_vitesse_temps.max_value = 100
	_vitesse_temps.step = 0.5
	_vitesse_temps.value_changed.connect(func(x): if not _maj_en_cours: serveur.definir_reglage("vitesse_temps", x))
	v.add_child(_ligne([_label("Vitesse du temps", 190), _vitesse_temps, _label("(1 = une journée en 20 minutes, 0 = temps arrêté)")]))
	v.add_child(_titre("Mode développeur et triches"))
	_mode_dev = CheckButton.new()
	_mode_dev.text = "Mode développeur (tous les joueurs peuvent afficher les infos de debug avec F3 : collisions, positions, FPS)"
	_mode_dev.toggled.connect(func(on): if not _maj_en_cours: serveur.definir_reglage("mode_dev", on))
	v.add_child(_mode_dev)
	_cheats = CheckButton.new()
	_cheats.text = "Triches autorisées pour les admins en jeu (/tp, /vitesse, /vol, /dieu)"
	_cheats.toggled.connect(func(on): if not _maj_en_cours: serveur.definir_reglage("cheats", on))
	v.add_child(_cheats)
	_pvp = CheckButton.new()
	_pvp.text = "Combats entre joueurs (PvP) autorisés"
	_pvp.toggled.connect(func(on): if not _maj_en_cours: serveur.definir_reglage("pvp", on))
	v.add_child(_pvp)
	v.add_child(_ligne([
		_bouton("Ajouter un mannequin près du feu de camp", func(): serveur.combat.ajouter_mannequin(serveur.monde.point_libre(serveur.monde.centre() + Vector2(randf_range(-150, 150), randf_range(60, 150))))),
		_bouton("Retirer tous les mannequins", serveur.combat.retirer_mannequins),
		_bouton("Remettre les mannequins de départ", func():
			serveur.combat.retirer_mannequins()
			serveur.combat.mannequins_par_defaut()),
	]))
	var aide := _label("Les triches par joueur se règlent dans l'onglet Joueurs ou avec les commandes (onglet Console).")
	aide.modulate.a = 0.6
	v.add_child(aide)
	v.add_child(_titre("Remise à zéro"))
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "Remettre le monde à zéro ?"
	confirmation.dialog_text = "Un nouveau monde va être créé. L'ancien est déplacé dans le dossier archives (rien n'est effacé).\nLes joueurs connectés seront déconnectés. Les pseudos, admins et bannissements sont gardés."
	confirmation.ok_button_text = "Remettre à zéro"
	confirmation.cancel_button_text = "Annuler"
	confirmation.confirmed.connect(serveur.reinitialiser_monde)
	v.add_child(confirmation)
	v.add_child(_ligne([_bouton("Remettre le monde à zéro…", confirmation.popup_centered)]))
	return v


# ------------------------------------------------------------------ Boss mondiaux

func _onglet_boss() -> Control:
	var v := _vbox("Boss mondiaux")
	var aide := _label("Activer un boss le réveille et prévient tous les joueurs. Un boss vaincu ne revient que si tu le réactives.\nProgrammation : une date précise (AAAA-MM-JJ HH:MM) ou chaque semaine. Heure de ce PC.\nLes combats de boss arrivent à l'étape 11 : pour l'instant, l'activation et les annonces fonctionnent.")
	aide.modulate.a = 0.65
	aide.add_theme_font_size_override("font_size", 14)
	v.add_child(aide)
	_liste_boss = _vbox("boss")
	v.add_child(_defilant(_liste_boss))
	return v


func _rafraichir_boss() -> void:
	_vider(_liste_boss)
	for b in DonneesBoss.LISTE:
		var e: Dictionary = serveur.etat_boss(b.id)
		var id: String = b.id
		var cadre := PanelContainer.new()
		var vb := _vbox(id)
		cadre.add_child(vb)
		var etat := _label("%s  (niveau %d, %s)  :  %s" % [b.nom, b.niveau, b.lieu, str(e.etat).to_upper()])
		etat.add_theme_color_override("font_color", Color(1, 0.5, 0.35) if e.etat == "actif" else ThemeJeu.TEXTE)
		vb.add_child(etat)
		vb.add_child(_ligne([
			_bouton("Activer maintenant", func(): serveur.activer_boss(id)),
			_bouton("Endormir", func(): serveur.endormir_boss(id)),
			_bouton("Effacer les programmes", func(): serveur.deprogrammer_boss(id)),
		]))
		var date := LineEdit.new()
		date.placeholder_text = "2026-11-07 20:00"
		date.custom_minimum_size.x = 190
		var jour := OptionButton.new()
		for j in DonneesBoss.JOURS:
			jour.add_item(j)
		jour.selected = 6
		var heure := LineEdit.new()
		heure.placeholder_text = "20:00"
		heure.custom_minimum_size.x = 80
		vb.add_child(_ligne([
			_label("Une fois le"), date, _bouton("Programmer", func():
				if not serveur.programmer_boss(id, date.text.strip_edges()):
					serveur.journal("Date invalide : écris AAAA-MM-JJ HH:MM")),
			_label("   Chaque"), jour, _label("à"), heure, _bouton("Programmer", func():
				if not serveur.programmer_boss(id, "hebdo %d %s" % [jour.selected, heure.text.strip_edges()]):
					serveur.journal("Heure invalide : écris HH:MM")),
		]))
		var progs := []
		for p in e.programmes:
			if p.begins_with("hebdo"):
				progs.append("chaque %s à %s" % [DonneesBoss.JOURS[int(p.get_slice(" ", 1))], p.get_slice(" ", 2)])
			else:
				progs.append("le " + p)
		vb.add_child(_label("Programmé : " + (", ".join(PackedStringArray(progs)) if not progs.is_empty() else "rien")))
		_liste_boss.add_child(cadre)


# ------------------------------------------------------------------ Console

func _onglet_console() -> Control:
	var v := _vbox("Console")
	_console = RichTextLabel.new()
	_console.size_flags_vertical = SIZE_EXPAND_FILL
	_console.scroll_following = true
	_console.selection_enabled = true
	_console.add_theme_font_size_override("normal_font_size", 14)
	v.add_child(_console)
	_saisie = LineEdit.new()
	_saisie.placeholder_text = "Commande (tape aide), par exemple : annonce Bonsoir !"
	_saisie.size_flags_horizontal = SIZE_EXPAND_FILL
	_saisie.text_submitted.connect(func(t):
		_saisie.text = ""
		if t.strip_edges() != "":
			_executer(t.strip_edges()))
	v.add_child(_ligne([_saisie, _bouton("Aide", func(): _executer("aide"))]))
	return v


func _sur_journal(ligne: String) -> void:
	if _console:
		_console.add_text(ligne + "\n")


# ------------------------------------------------------------------ Mise à jour

func _chaque_seconde() -> void:
	if serveur.donnees.is_empty():
		_statut.text = "Le serveur n'a pas démarré : regarde l'onglet Console."
		return
	var duree: int = (Time.get_ticks_msec() - serveur.demarre_le) / 1000
	var ips := []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			ips.append(ip)
	_statut.text = "%s\nÉtat : %s\nVersion %s, protocole %d, format de sauvegarde %d\nEn marche depuis %dh%02d\nJoueurs connectés : %d / %d\nAdresses locales : %s (port %d)\nGraine du monde : %d, heure du jeu : %.1f h\nDernière sauvegarde : %s\nSauvegardes : %s" % [
		serveur.config.nom, "en ligne" if serveur.actif else "ARRÊTÉ (voir la console)",
		Config.version, Config.PROTOCOLE, Sauvegarde.FORMAT, duree / 3600, (duree / 60) % 60,
		serveur.joueurs.size(), int(serveur.config.joueurs_max), ", ".join(PackedStringArray(ips)),
		Config.port if Config.port != Config.PORT_DEFAUT else int(serveur.config.port),
		int(serveur.donnees.graine), serveur.donnees.heure, serveur.derniere_sauvegarde, Sauvegarde.chemin_reel()]
	_maj_en_cours = true
	_heure.value = serveur.donnees.heure
	_vitesse_temps.value = float(serveur.donnees.reglages.vitesse_temps)
	_mode_dev.button_pressed = serveur.donnees.reglages.mode_dev
	_cheats.button_pressed = serveur.donnees.reglages.cheats
	_pvp.button_pressed = serveur.donnees.reglages.get("pvp", true)
	_maj_en_cours = false
	_carte.queue_redraw()
	if _a_rafraichir:
		_a_rafraichir = false
		_rafraichir_joueurs()
		_rafraichir_boss()
	for nom in _labels_vie:
		var sj: Dictionary = serveur.session_par_nom(nom)
		if not sj.is_empty() and is_instance_valid(_labels_vie[nom]):
			_labels_vie[nom].text = _texte_vie(sj)
