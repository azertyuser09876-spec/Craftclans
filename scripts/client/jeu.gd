extends Node
## Partie en cours côté joueur.
##
## Déplacement : le joueur bouge tout de suite à l'écran (prédiction), envoie chaque
## entrée numérotée au serveur, et quand le serveur répond avec sa position officielle,
## on rejoue les entrées pas encore confirmées. Les autres joueurs sont interpolés.
##
## Combat : le jeu envoie seulement « j'attaque vers ce point » ; le serveur calcule
## les dégâts et renvoie des événements que l'on affiche (Effets).

var infos: Dictionary
var monde: Monde
var vue: VueMonde
var effets: Effets
var moi: JoueurVisuel
var camera: Camera2D
var autres := {} # id -> JoueurVisuel
var mannequins := {} # id -> MannequinVisuel
var mon_id := 0
var reglages := {"mode_dev": false, "cheats": false, "admin": false, "vitesse": Config.VITESSE_JOUEUR,
	"vol": false, "dieu": false, "role": "guerrier", "equipe": "", "esquive": 2.5, "pvp": true}
var heure := 9.0

var _mvt: Dictionary # état de déplacement prédit (Regles)
var _correction := Vector2.ZERO # écart visuel résorbé en douceur
var _seq := 0
var _en_attente: Array = [] # entrées pas encore confirmées : [seq, dir, esquive, regard_avant, dash_dir_avant]
var _esquive_demandee := false
var _ping := 0
var _accu_ping := 0.0
var _debug := false
var _temps_auto := 0.0
var _ecart_max := 0.0 # plus grand écart prédiction/serveur (infos de debug)
var _secousse := 0.0

# Combat
var _visee_genre := "" # capacité en cours de visée : "attaque" ou "competence"
var _visee_vecteur := Vector2.ZERO # visée tactile (longueur 0 à 1)
var _visee_tactile := false
var _charge_debut := 0.0
var _pret := {"attaque": 0.0, "competence": 0.0}
var _attaque_maintenue := false
var _mort_jusqua := 0.0
var _vaincu_par := ""
var _attaque_deja_partie := false # attaque au corps à corps déjà partie pendant l'appui

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
var _dessin_visee: Node2D
var _barre: BarreCombat
var _choix_role: PanelContainer
var _ecran_mort: Label
var _lieu: Label
var _minicarte: CarteVue
var _grande_carte: CarteVue
var _a_afficher: Array = [] # morceaux reçus, affichés petit à petit
var _accu_morceaux := 0.0
const RAYON_GARDE := 4 # morceaux gardés autour du joueur (le serveur envoie dans un rayon de 2)

# Ressources et inventaire
const TEX_SAC := preload("res://assets/objets/sac.png")
const TEX_CORPS := preload("res://assets/objets/corps.png")
var inventaire: Array = []
var equipement := {}
var _fabrication_vue: FabricationVue
var _personnage_vue: PersonnageVue
var progression := {}
var _accu_stations := 0.0
var sacs := {} # id -> {infos, noeud}
var _inventaire_vue: InventaireVue
var _cible := {} # ce qu'on peut récolter ou ramasser : {genre: "deco"|"sac", case|id, pos}
var _invite: Label
var _bouton_recolter: Button
var _bouton_tenu := false
var _recolte_envoyee := false
var _recolte_case := Vector2i.ZERO
var _recolte_progres := -1.0

# Constructions (étape 6)
var constructions := {} # id -> infos
var _noeuds_c := {} # id -> Node2D (constructions libres)
var _construction_vue: ConstructionVue
var _barres_c: Node2D # vie des constructions abîmées
var _construire_case := -1 # case de l'inventaire en cours de pose (-1 : pas en mode construction)
var _construire_grille := true
var _fantome: Sprite2D
var _aide_construction: Label
var _boutons_construction: HBoxContainer


func _ready() -> void:
	mon_id = int(infos.id)
	heure = float(infos.heure)
	monde = Monde.new(int(infos.graine))
	vue = VueMonde.new(monde)
	add_child(vue)
	effets = Effets.new()
	vue.add_child(effets)
	_mvt = Regles.nouvel_etat(infos.pos)
	moi = JoueurVisuel.new(str(infos.nom), int(infos.apparence))
	moi.position = _mvt.pos
	vue.objets.add_child(moi)
	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	moi.add_child(camera)
	camera.make_current()
	_dessin_visee = Node2D.new()
	_dessin_visee.z_index = 15
	_dessin_visee.draw.connect(_dessiner_visee)
	vue.add_child(_dessin_visee)
	_debug_dessin = Node2D.new()
	_debug_dessin.z_index = 100
	_debug_dessin.draw.connect(_dessiner_debug)
	vue.add_child(_debug_dessin)
	for id in infos.joueurs:
		_ajouter_autre(int(id), infos.joueurs[id])
	for id in infos.get("mannequins", {}):
		var m: Array = infos.mannequins[id]
		_ajouter_mannequin(int(id), Vector2(m[0], m[1]), int(m[2]), int(m[3]))
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
	Reseau.morceau_recu.connect(_sur_morceau)
	Reseau.case_changee.connect(_sur_case)
	Reseau.inventaire_recu.connect(func(inv, equip):
		inventaire = inv
		equipement = equip
		_inventaire_vue.afficher(inv, equip)
		_fabrication_vue.maj(inv, _fabrication_vue.stations))
	Reseau.recolte_recue.connect(func(p, _c): _recolte_progres = p)
	Reseau.progression_recue.connect(_sur_progression)
	Reseau.constructions_recues.connect(func(l):
		for id in constructions.keys():
			_retirer_construction(id)
		for i in l:
			_maj_construction(i))
	Reseau.construction_recue.connect(_maj_construction)
	Reseau.construction_retiree.connect(_retirer_construction)
	Reseau.contenu_recu.connect(func(id, contenu):
		if _construction_vue.visible and int(_construction_vue.rec.get("id", -1)) == id:
			_construction_vue.contenu = contenu
			_construction_vue.rafraichir())
	Reseau.sacs_recus.connect(func(liste):
		for infos_sac in liste:
			_ajouter_sac(infos_sac))
	Reseau.sac_recu.connect(_ajouter_sac)
	Reseau.sac_retire.connect(_retirer_sac)
	RenderingServer.set_default_clear_color(Color(0.08, 0.1, 0.09))
	if infos.get("nouveau", false) and Config.auto_connexion == "":
		_choix_role.visible = true
	if Config.auto_commande != "":
		# « @5 /commande » : envoyée 5 secondes après l'arrivée (pour les tests).
		for c in Config.auto_commande.split(";"):
			var delai := 0.0
			if c.begins_with("@"):
				delai = float(c.get_slice(" ", 0).substr(1))
				c = c.substr(c.find(" ") + 1)
			if c.begins_with("*"): # « *attaque 100 200 » : attaque vers ce point (tests)
				var m := c.substr(1).split(" ")
				get_tree().create_timer(delai).timeout.connect(Reseau.c_action.rpc_id.bind(1, m[0], Vector2(float(m[1]), float(m[2])), 1.0))
			elif c.begins_with("+"): # « +3 100 200 1 » : pose l'objet de la case 3 en (100, 200), sur la grille (tests)
				var m := c.substr(1).split(" ")
				get_tree().create_timer(delai).timeout.connect(Reseau.c_construire.rpc_id.bind(1, int(m[0]),
					Vector2(float(m[1]), float(m[2])), m.size() < 4 or m[3] == "1"))
			elif c.begins_with("&"): # « &ouvrir 5 0 » : action sur une construction (tests)
				var m := c.substr(1).split(" ")
				get_tree().create_timer(delai).timeout.connect(Reseau.c_construction.rpc_id.bind(1, m[0], int(m[1]), int(m[2]) if m.size() > 2 else 0))
			elif c.begins_with("#construire ") or c.begins_with("#gerer "): # mode construction, fenêtre d'une construction (tests)
				var n := int(c.get_slice(" ", 1))
				var type := c.get_slice(" ", 1)
				get_tree().create_timer(delai).timeout.connect(func():
					if c.begins_with("#construire "):
						_debut_construction(n)
						return
					for i in constructions.values():
						if i.type == type:
							_ouvrir_construction(i)
							return)
			elif c.begins_with("#"): # « #personnage » : ouvre une fenêtre (tests, captures)
				var f: Control = {"inventaire": _inventaire_vue, "fabriquer": _fabrication_vue, "personnage": _personnage_vue}.get(c.substr(1).strip_edges())
				if f:
					get_tree().create_timer(delai).timeout.connect(_basculer_fenetre.bind(f))
			elif c.begins_with("?"): # « ?carac vie » : progression (tests)
				get_tree().create_timer(delai).timeout.connect(Reseau.c_progression.rpc_id.bind(1, c.substr(1).get_slice(" ", 0), c.get_slice(" ", 1)))
			elif c.begins_with("!"): # « !fabriquer etabli » : action d'atelier (tests)
				get_tree().create_timer(delai).timeout.connect(Reseau.c_atelier.rpc_id.bind(1, c.substr(1).get_slice(" ", 0), c.get_slice(" ", 1)))
			else:
				get_tree().create_timer(delai).timeout.connect(Reseau.c_chat.rpc_id.bind(1, c))


func _en_jeu() -> bool:
	return not _saisie.has_focus() and not _menu_pause.visible and not _choix_role.visible \
		and not _grande_carte.visible and not _inventaire_vue.visible and not _fabrication_vue.visible \
		and not _personnage_vue.visible and not _construction_vue.visible


# ------------------------------------------------------------------ Boucle

func _physics_process(_delta: float) -> void:
	if moi.est_mort():
		_esquive_demandee = false
		return
	var dir := Vector2.ZERO
	if _en_jeu():
		dir = Input.get_vector("gauche", "droite", "haut", "bas")
		if _joystick and _joystick.vecteur != Vector2.ZERO:
			dir = _joystick.vecteur
	if Config.auto_deplacement:
		_temps_auto += 1.0 / 60.0
		dir = Vector2(cos(_temps_auto * 0.8), sin(_temps_auto * 0.8))
		_esquive_demandee = _esquive_demandee or int(_temps_auto * 60) % 180 == 90
		if int(_temps_auto * 60) % 120 == 0:
			print("[test] %s pos=%s attente=%d autres=%d heure=%.2f ping=%d ecart_max=%.2f vie=%d" % [infos.nom, _mvt.pos.round(), _en_attente.size(), autres.size(), heure, _ping, _ecart_max, moi.vie])
		if int(_temps_auto * 60) % 40 == 0:
			_tirer("attaque", _cible_auto("attaque"), 1.0)
	var esquive := _esquive_demandee
	_esquive_demandee = false
	_seq += 1
	Reseau.c_entree.rpc_id(1, _seq, dir, 1 if esquive else 0)
	_en_attente.append([_seq, dir, esquive, _mvt.regard, _mvt.dash_dir])
	Regles.pas(monde, _mvt, dir, esquive, reglages.vitesse, reglages.vol, reglages.esquive)


func _sur_morceau(cle: Vector2i, donnees: PackedByteArray) -> void:
	if not monde.recevoir(cle, donnees).is_empty():
		_a_afficher.erase(cle)
		_a_afficher.append(cle)


## Affiche quelques morceaux par image (pour ne pas saccader) et oublie ceux qui sont loin.
func _gerer_morceaux(delta: float) -> void:
	var ici := Monde.cle_de_position(_mvt.pos)
	# Les plus proches d'abord
	_a_afficher.sort_custom(func(a, b): return (a - ici).length_squared() < (b - ici).length_squared())
	for i in mini(2, _a_afficher.size()):
		var cle: Vector2i = _a_afficher.pop_front()
		if monde.morceaux.has(cle):
			vue.afficher_morceau(cle)
	_accu_morceaux += delta
	if _accu_morceaux < 1.0:
		return
	_accu_morceaux = 0.0
	for cle in vue.morceaux_affiches():
		if maxi(absi(cle.x - ici.x), absi(cle.y - ici.y)) > RAYON_GARDE:
			vue.retirer_morceau(cle)
			monde.oublier(cle)


func _process(delta: float) -> void:
	_gerer_morceaux(delta)
	_correction = _correction.lerp(Vector2.ZERO, minf(delta * 10.0, 1.0))
	moi.position = _mvt.pos + _correction
	vue.voir_a_travers(moi.position)
	_secousse = maxf(0.0, _secousse - delta * 3.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _secousse * 4.0
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
	_maj_combat()
	_maj_interaction(delta)
	_maj_construction_mode()
	_barres_c.queue_redraw()
	_maj_lieu()
	_info.text = "Craftclans %s  |  %d joueur(s)  |  ping %d ms  |  %02d:%02d%s" % [
		Config.version, autres.size() + 1, _ping, int(heure), int(fmod(heure, 1.0) * 60),
		"" if reglages.equipe == "" else "  |  équipe " + reglages.equipe]
	var montrer_debug: bool = _debug and (reglages.mode_dev or reglages.admin)
	_debug_label.visible = montrer_debug
	if montrer_debug:
		var c := Vector2i(_mvt.pos / Config.TAILLE_TUILE)
		_debug_label.text = "FPS %d\nCase %d, %d\nPosition %.0f, %.0f\nEntrées en attente %d (écart max %.1f)\nVitesse %.0f%s%s\nEsquive %d / %d\nGraine %d" % [
			Engine.get_frames_per_second(), c.x, c.y, _mvt.pos.x, _mvt.pos.y, _en_attente.size(), _ecart_max,
			reglages.vitesse, "  [vol]" if reglages.vol else "", "  [dieu]" if reglages.dieu else "",
			_mvt.dash_f, _mvt.dash_cd, monde.graine]
	_debug_dessin.visible = montrer_debug
	if montrer_debug:
		_debug_dessin.queue_redraw()


func _maj_lieu() -> void:
	var c := Vector2i((_mvt.pos / Config.TAILLE_TUILE).floor())
	if monde.morceaux.has(Monde.cle_de_case(c.x, c.y)):
		var danger := monde.danger_en(c.x, c.y)
		_lieu.text = "%s  ·  danger %d  ·  %d, %d" % [Monde.NOMS_BIOMES[monde.biome_en(c.x, c.y)], danger, c.x, c.y]
		_lieu.add_theme_color_override("font_color", Color(0.75, 1, 0.7).lerp(Color(1, 0.35, 0.25), danger / 10.0))
	var marqueurs := [[_mvt.pos, Color.WHITE]]
	for a in autres.values():
		marqueurs.append([a.position, Color(0.5, 1, 0.5) if a.allie else Color(1, 0.4, 0.35)])
	for s in sacs.values():
		if s.infos.genre == "corps":
			marqueurs.append([s.infos.pos, Color(1, 0.6, 0.15) if s.infos.nom == infos.nom else Color(0.75, 0.75, 0.75)])
	for i in constructions.values():
		if i.type == "coeur_base":
			marqueurs.append([i.pos, Color(0.4, 0.8, 1.0) if _allie_de(str(i.proprio)) else Color(0.85, 0.3, 0.9)])
	for carte in [_minicarte, _grande_carte]:
		if carte.visible:
			carte.centre = _mvt.pos
			carte.marqueurs = marqueurs
			carte.queue_redraw()


func _dessiner_debug() -> void:
	var t := Config.TAILLE_TUILE
	var c := Vector2i(_mvt.pos / t)
	for y in range(c.y - 6, c.y + 7):
		for x in range(c.x - 8, c.x + 9):
			if monde.case_bloquante(x, y):
				var r := Rect2(x * t, y * t, t, t)
				if monde.sol_en(x, y) != Monde.Sol.EAU:
					r = r.grow(-8)
				_debug_dessin.draw_rect(r, Color(1, 0.2, 0.2, 0.35))
	_debug_dessin.draw_circle(_mvt.pos, Config.RAYON_JOUEUR, Color(0.2, 1, 0.3, 0.5))
	for a in autres.values():
		_debug_dessin.draw_circle(a.position, Config.RAYON_JOUEUR, Color(0.3, 0.6, 1, 0.5))
		_debug_dessin.draw_arc(a.position + Vector2(0, -10), Combat.RAYON_CIBLE, 0, TAU, 16, Color(1, 1, 0.3, 0.6))
	for m in mannequins.values():
		_debug_dessin.draw_arc(m.position + Vector2(0, -10), Combat.RAYON_CIBLE, 0, TAU, 16, Color(1, 1, 0.3, 0.6))


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
	elif event.is_action_pressed("menu") and _construire_case >= 0 and not _saisie.has_focus():
		_fin_construction()
	elif event.is_action_pressed("menu"):
		if _saisie.has_focus():
			_saisie.release_focus()
			_saisie.visible = false
		elif _choix_role.visible:
			_choix_role.visible = false
		elif _grande_carte.visible:
			_grande_carte.visible = false
		elif _inventaire_vue.visible:
			_inventaire_vue.visible = false
		elif _fabrication_vue.visible:
			_fabrication_vue.visible = false
		elif _personnage_vue.visible:
			_personnage_vue.visible = false
		elif _construction_vue.visible:
			_construction_vue.fermer_fenetre()
		else:
			_menu_pause.visible = not _menu_pause.visible
	elif event.is_action_pressed("inventaire") and not _saisie.has_focus() and not _menu_pause.visible:
		_basculer_fenetre(_inventaire_vue)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fabriquer") and not _saisie.has_focus() and not _menu_pause.visible:
		_basculer_fenetre(_fabrication_vue)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("personnage") and not _saisie.has_focus() and not _menu_pause.visible:
		_basculer_fenetre(_personnage_vue)
		get_viewport().set_input_as_handled()
	elif not _en_jeu() or _visee_tactile:
		return
	elif _construire_case >= 0 and event.is_action_pressed("grille"):
		_construire_grille = not _construire_grille
	elif _construire_case >= 0 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_poser()
		get_viewport().set_input_as_handled()
	elif _construire_case >= 0 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_fin_construction()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interagir"):
		_interagir()
	elif event.is_action_pressed("role"):
		_choix_role.visible = true
	elif event.is_action_pressed("carte"):
		_grande_carte.visible = not _grande_carte.visible
	elif event.is_action_pressed("esquive"):
		_esquive_demandee = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_commencer_visee("attaque")
			_attaque_maintenue = true
		else:
			_attaque_maintenue = false
			_relacher_visee("attaque", vue.get_global_mouse_position())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_commencer_visee("competence")
		else:
			_relacher_visee("competence", vue.get_global_mouse_position())
	elif event.is_action("competence") and not event.is_echo():
		if event.pressed:
			_commencer_visee("competence")
		else:
			_relacher_visee("competence", vue.get_global_mouse_position())


# ------------------------------------------------------------------ Combat

func _capacite(genre: String) -> Dictionary:
	# Capacités modifiées par l'arbre de compétences (envoyées par le serveur).
	var caps: Dictionary = reglages.get("caps", {})
	return caps[genre] if caps.has(genre) else Roles.donnees(reglages.role)[genre]


func _charge() -> float:
	var cap := _capacite("attaque")
	if not cap.has("charge") or _visee_genre != "attaque":
		return 0.0
	return clampf((Time.get_ticks_msec() / 1000.0 - _charge_debut) / float(cap.charge), 0.0, 1.0)


func _commencer_visee(genre: String) -> void:
	if moi.est_mort():
		return
	var cap := _capacite(genre)
	# Capacités sans visée : immédiates.
	if cap.genre in ["buff", "zone_soi"]:
		_tirer(genre, _mvt.pos, 0.0)
		return
	_visee_genre = genre
	_charge_debut = Time.get_ticks_msec() / 1000.0


func _relacher_visee(genre: String, cible: Vector2) -> void:
	if _visee_genre != genre:
		return
	var charge := _charge()
	_visee_genre = ""
	var cap := _capacite(genre)
	# Les attaques simples partent quand on clique ; seule l'attaque chargée part au relâchement.
	if cap.genre != "melee" or not _attaque_deja_partie:
		_tirer(genre, cible, charge)
	_attaque_deja_partie = false


func _tirer(genre: String, cible: Vector2, charge: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if moi.est_mort() or t < _pret[genre]:
		return
	_pret[genre] = t + float(_capacite(genre).recharge)
	Reseau.c_action.rpc_id(1, genre, cible, charge)


## Point visé automatiquement (tactile, tap rapide) : l'ennemi le plus proche à portée.
func _cible_auto(genre: String) -> Vector2:
	var cap := _capacite(genre)
	var portee := Roles.portee(cap, 1.0) + 20.0
	var meilleur: Vector2 = _mvt.pos + _mvt.regard * minf(portee, 120.0)
	var d_min := portee
	var candidats: Array = []
	for a in autres.values():
		if not a.allie and not a.est_mort() and a.modulate.a > 0.0:
			candidats.append(a.position)
	for m in mannequins.values():
		candidats.append(m.position)
	for p in candidats:
		var d: float = _mvt.pos.distance_to(p)
		if d < d_min:
			d_min = d
			meilleur = p
	return meilleur


func _point_vise() -> Vector2:
	if _visee_tactile:
		var cap := _capacite(_visee_genre)
		return _mvt.pos + _visee_vecteur * Roles.portee(cap, 1.0)
	return vue.get_global_mouse_position()


func _maj_combat() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	# Attaque au corps à corps maintenue : on frappe dès que c'est rechargé.
	if _attaque_maintenue and _visee_genre == "attaque" and _capacite("attaque").genre == "melee" and t >= _pret.attaque:
		_tirer("attaque", vue.get_global_mouse_position(), 0.0)
		_attaque_deja_partie = true
	_barre.vie = moi.vie
	_barre.vie_max = moi.vie_max
	for g in ["attaque", "competence"]:
		var rec := float(_capacite(g).recharge)
		_barre.recharges[g] = clampf((_pret[g] - t) / rec, 0.0, 1.0)
	_barre.recharges.esquive = clampf(float(_mvt.dash_cd) / (float(reglages.esquive) * 60.0), 0.0, 1.0)
	_barre.charge = _charge() if _capacite("attaque").has("charge") and _visee_genre == "attaque" else -1.0
	_barre.queue_redraw()
	if _visee_genre != "" and not _visee_tactile:
		moi.visee = (_point_vise() - _mvt.pos).normalized()
	_dessin_visee.queue_redraw()
	_ecran_mort.visible = moi.est_mort()
	if moi.est_mort():
		_ecran_mort.text = "Vaincu par %s\nRéapparition dans %d s" % [_vaincu_par, ceili(maxf(0.0, _mort_jusqua - t))]


func _dessiner_visee() -> void:
	_dessiner_recolte()
	if _visee_genre == "" or moi.est_mort():
		return
	var cap := _capacite(_visee_genre)
	var depart: Vector2 = moi.position
	var cible := _point_vise()
	var dir: Vector2 = (cible - depart).normalized() if cible != depart else _mvt.regard
	var couleur := Color(1, 1, 1, 0.55)
	match cap.genre:
		"melee":
			var demi := deg_to_rad(float(cap.angle) * 0.5)
			var pts := PackedVector2Array([depart])
			for i in 13:
				pts.append(depart + Vector2.from_angle(dir.angle() - demi + 2.0 * demi * i / 12.0) * float(cap.portee))
			_dessin_visee.draw_colored_polygon(pts, Color(1, 1, 1, 0.18))
		"tir":
			var portee := Roles.portee(cap, _charge())
			_dessin_visee.draw_line(depart + Vector2(0, -10), depart + Vector2(0, -10) + dir * portee, couleur, 3.0)
			_dessin_visee.draw_line(depart + Vector2(0, -10), depart + Vector2(0, -10) + dir * float(cap.portee_max), Color(1, 1, 1, 0.15), 1.0)
		"lancer", "zone_visee", "tourelle":
			var portee := float(cap.portee)
			_dessin_visee.draw_arc(depart, portee, 0, TAU, 64, Color(1, 1, 1, 0.15), 1.5)
			var point: Vector2 = cible if depart.distance_to(cible) <= portee else depart + dir * portee
			_dessin_visee.draw_circle(point, float(cap.rayon), Color(1, 1, 1, 0.16))
			_dessin_visee.draw_arc(point, float(cap.rayon), 0, TAU, 48, couleur, 2.0)
			_dessin_visee.draw_dashed_line(depart, point, Color(1, 1, 1, 0.4), 2.0, 6.0)


func _sur_visee_tactile_commencee(genre: String) -> void:
	_visee_tactile = true
	_visee_vecteur = Vector2.ZERO
	_commencer_visee(genre)


func _sur_visee_tactile_changee(genre: String, v: Vector2) -> void:
	_visee_vecteur = v
	if v.length() > 0.05:
		moi.visee = v.normalized()


func _sur_visee_tactile_relachee(genre: String, v: Vector2, tape: bool) -> void:
	_visee_tactile = false
	if _visee_genre != genre:
		return
	var cible: Vector2 = _cible_auto(genre) if tape else _mvt.pos + v * Roles.portee(_capacite(genre), 1.0)
	_relacher_visee(genre, cible)


func choisir_role(role: String) -> void:
	_choix_role.visible = false
	Reseau.c_role.rpc_id(1, role)


# ------------------------------------------------------------------ Réseau

func _sur_etat(etat: Dictionary) -> void:
	heure = float(etat.h)
	for id in etat.j:
		var d: Array = etat.j[id]
		var p := Vector2(d[0], d[1])
		var visuel: JoueurVisuel = moi if int(id) == mon_id else autres.get(int(id))
		if visuel == null:
			continue
		visuel.vie = int(d[3])
		visuel.vie_max = int(d[4])
		var etait_mort := visuel.est_mort()
		visuel.drapeaux = int(d[5])
		if int(id) == mon_id:
			if visuel.est_mort() and not etait_mort:
				_en_attente.clear()
			if not visuel.est_mort():
				_reconcilier(p, int(d[2]), int(d[6]), int(d[7]))
		else:
			visuel.ajouter_instantane(p)
	for id in etat.get("m", {}):
		if mannequins.has(int(id)):
			mannequins[int(id)].vie = int(etat.m[id])


func _reconcilier(pos_serveur: Vector2, seq_confirmee: int, dash_f: int, dash_cd: int) -> void:
	while not _en_attente.is_empty() and _en_attente[0][0] <= seq_confirmee:
		_en_attente.pop_front()
	var e := Regles.nouvel_etat(pos_serveur)
	e.dash_f = dash_f
	e.dash_cd = dash_cd
	if _en_attente.is_empty():
		e.regard = _mvt.regard
		e.dash_dir = _mvt.dash_dir
	else:
		e.regard = _en_attente[0][3]
		e.dash_dir = _en_attente[0][4]
	for entree in _en_attente:
		Regles.pas(monde, e, entree[1], entree[2], reglages.vitesse, reglages.vol, reglages.esquive)
	var ecart: Vector2 = _mvt.pos - e.pos
	_ecart_max = maxf(_ecart_max, ecart.length())
	if ecart.length() < 64.0:
		_correction += ecart
	_mvt = e


func _sur_teleport(pos: Vector2) -> void:
	_en_attente.clear()
	_mvt.pos = pos
	_mvt.dash_f = 0
	_correction = Vector2.ZERO
	camera.reset_smoothing()


func _sur_reglages(r: Dictionary) -> void:
	var ancien_role: String = reglages.role
	reglages.merge(r, true)
	moi.etiquette.add_theme_color_override("font_color", Color(1, 0.85, 0.35) if reglages.admin else Color.WHITE)
	if reglages.role != ancien_role or moi.role != reglages.role:
		moi.definir_role(reglages.role)
		_barre.definir_role(reglages.role)
		_pret = {"attaque": 0.0, "competence": 0.0}
	moi.equipe = reglages.equipe
	_inventaire_vue.maj_stats(reglages.get("stats", {}))
	_personnage_vue.maj(progression, reglages.role, reglages.get("stats", {}), inventaire)
	for a in autres.values():
		_maj_allie(a)


func _sur_progression(p: Dictionary) -> void:
	if not progression.is_empty() and int(p.niveau) == int(progression.niveau) and int(p.xp) > int(progression.xp):
		effets.texte(moi.position + Vector2(0, -44), "+%d xp" % (int(p.xp) - int(progression.xp)), Color(0.55, 0.8, 1.0))
	progression = p
	_barre.niveau = int(p.niveau)
	_barre.part_xp = float(p.xp) / maxf(1.0, float(p.xp_suivant)) if int(p.xp_suivant) > 0 else 1.0
	_barre.queue_redraw()
	moi.definir_niveau(int(p.niveau))
	_personnage_vue.maj(p, reglages.role, reglages.get("stats", {}), inventaire)


func _maj_allie(a: JoueurVisuel) -> void:
	a.allie = reglages.equipe != "" and a.equipe == reglages.equipe
	if a.allie:
		a.definir_couleur_nom(Color(0.55, 1, 0.55))


func _ajouter_autre(id: int, i: Dictionary) -> void:
	if id == mon_id:
		moi.definir_arme(str(i.get("arme", "")))
		return
	var j: JoueurVisuel = autres.get(id)
	if j == null:
		j = JoueurVisuel.new(str(i.nom), int(i.apparence), bool(i.get("admin", false)))
		j.position = i.pos
		j.ajouter_instantane(i.pos)
		vue.objets.add_child(j)
		autres[id] = j
	j.definir_role(str(i.get("role", "guerrier")))
	j.definir_arme(str(i.get("arme", "")))
	j.definir_niveau(int(i.get("niveau", 1)))
	j.equipe = str(i.get("equipe", ""))
	_maj_allie(j)


func _retirer_autre(id: int) -> void:
	if autres.has(id):
		autres[id].queue_free()
		autres.erase(id)


func _ajouter_mannequin(id: int, pos: Vector2, vie: int, vie_max: int) -> void:
	if mannequins.has(id):
		return
	var m := MannequinVisuel.new(pos, vie, vie_max)
	vue.objets.add_child(m)
	mannequins[id] = m


func _visuel(id: int) -> JoueurVisuel:
	return moi if id == mon_id else autres.get(id)


func _sur_evenement(genre: String, d: Dictionary) -> void:
	match genre:
		"bulle":
			var v := _visuel(int(d.id))
			if v: v.dire(str(d.texte))
		"boss":
			_banniere.text = "%s s'est réveillé !\n%s" % [d.nom, d.lieu]
			_banniere.modulate.a = 1.0
			var tw := create_tween()
			tw.tween_interval(5.0)
			tw.tween_property(_banniere, "modulate:a", 0.0, 1.5)
		"geste":
			var v := _visuel(int(d.id))
			if v == null:
				return
			v.geste(float(d.angle))
			var role := v.role if v != moi else str(reglages.role)
			var cap: Dictionary = Roles.donnees(role)[d.genre]
			if cap.genre == "melee":
				effets.balayage(v.position, float(d.angle), float(cap.portee))
		"projectile":
			effets.projectile(int(d.pid), d.de, d.dir, float(d.vitesse), float(d.portee))
		"fin_projectile":
			effets.fin_projectile(int(d.pid), d.pos, bool(d.touche))
		"lancer":
			effets.lancer(d.de, d.vers, float(d.duree), str(d.genre))
		"zone":
			effets.zone(d.pos, float(d.rayon), float(d.delai), str(d.genre), int(d.get("vagues", 1)))
		"impact":
			effets.impact(d.pos, float(d.rayon), str(d.genre))
		"buff":
			var v := _visuel(int(d.id))
			if v and d.effet == "sprint":
				effets.anneau(v.position, 24.0, Color(0.6, 0.9, 1, 0.9))
			elif v and d.effet == "ruee":
				effets.anneau(v.position, 26.0, Color(1, 0.8, 0.3, 0.9))
		"degats":
			var cle := str(d.cle)
			var sur_moi := cle == "j%d" % mon_id
			effets.nombre(d.pos, int(d.montant), d.get("soin", false), sur_moi)
			if sur_moi and not d.get("soin", false):
				_secousse = 1.0
			if cle.begins_with("m") and mannequins.has(int(cle.substr(1))):
				mannequins[int(cle.substr(1))].touche()
		"mort":
			if int(d.id) == mon_id:
				_vaincu_par = str(d.par)
				_mort_jusqua = Time.get_ticks_msec() / 1000.0 + Roles.REAPPARITION
				_visee_genre = ""
			effets.explosion(d.pos, "impact", 1.2)
		"mannequin":
			_ajouter_mannequin(int(d.id), d.pos, int(d.vie), int(d.max))
		"recolte":
			var v := _visuel(int(d.id))
			if v:
				v.geste(float(d.angle))
			effets.explosion(d.pos + Vector2(0, -8), "impact", 0.35)
			if int(d.id) == mon_id:
				var info := Objets.infos(str(d.objet))
				effets.texte(d.pos, "+1 %s" % info.nom, Objets.COULEURS_RARETE[int(info.rarete)])
		"fabrication":
			if int(d.id) == mon_id:
				var info_f := Objets.infos(str(d.objet))
				effets.texte(d.pos, info_f.nom, Objets.COULEURS_RARETE[int(info_f.rarete)])
			effets.explosion(d.pos + Vector2(0, -10), "impact", 0.5)
		"ramasser":
			if int(d.id) == mon_id:
				var parts := []
				for id_objet in d.objets:
					parts.append("+%d %s" % [d.objets[id_objet], Objets.infos(id_objet).nom])
				effets.texte(d.pos, ", ".join(PackedStringArray(parts)), Color(1, 0.95, 0.6))
		"niveau":
			var v := _visuel(int(d.id))
			if v:
				effets.anneau(v.position, 34.0, Color(1, 0.85, 0.3, 0.95))
				effets.explosion(v.position + Vector2(0, -12), "impact", 0.9)
				effets.texte(v.position + Vector2(0, -30), "Niveau %d !" % int(d.niveau), Color(1, 0.85, 0.3))
			if int(d.id) == mon_id:
				_banniere.text = "Niveau %d !\n+%d points de caractéristiques, +%d point de compétence (touche P)" % [
					int(d.niveau), Progression.POINTS_CARACS_PAR_NIVEAU, Progression.POINTS_COMPETENCE_PAR_NIVEAU]
				_banniere.modulate.a = 1.0
				var tw_n := create_tween()
				tw_n.tween_interval(3.5)
				tw_n.tween_property(_banniere, "modulate:a", 0.0, 1.2)
		"construction":
			effets.explosion(d.pos + Vector2(0, -8), "impact", 0.6)
		"destruction":
			effets.explosion(d.pos + Vector2(0, -10), "explosion", 1.0)
			_secousse = maxf(_secousse, 0.4) if _mvt.pos.distance_to(d.pos) < 200.0 else _secousse
		"mannequin_retire":
			if mannequins.has(int(d.id)):
				mannequins[int(d.id)].queue_free()
				mannequins.erase(int(d.id))


# ------------------------------------------------------------------ Ressources, sacs et corps

func _sur_case(c: Vector2i, deco: int) -> void:
	if monde.changer_deco(c.x, c.y, deco):
		vue.changer_case(c)


func _ajouter_sac(i: Dictionary) -> void:
	_retirer_sac(int(i.id))
	var n := Node2D.new()
	n.position = i.pos
	var spr := Sprite2D.new()
	spr.texture = TEX_CORPS if i.genre == "corps" else TEX_SAC
	spr.offset = Vector2(0, -spr.texture.get_height() / 2.0 + 3)
	n.add_child(spr)
	if i.genre == "corps":
		var l := Label.new()
		l.text = "Ton corps" if i.nom == infos.nom else "Corps de %s" % i.nom
		l.position = Vector2(-60, -36)
		l.custom_minimum_size = Vector2(120, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 9)
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_color_override("font_color", Color(1, 0.7, 0.4) if i.nom == infos.nom else Color(0.85, 0.85, 0.85))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		n.add_child(l)
	vue.objets.add_child(n)
	sacs[int(i.id)] = {"infos": i, "noeud": n}


func _retirer_sac(id: int) -> void:
	if sacs.has(id):
		sacs[id].noeud.queue_free()
		sacs.erase(id)


## Cherche ce que le joueur peut ramasser (en priorité) ou récolter à côté de lui.
func _chercher_cible() -> Dictionary:
	if moi.est_mort():
		return {}
	var meilleur := {}
	var meilleure_dist := Objets.PORTEE_RAMASSER
	for s in sacs.values():
		var d: float = _mvt.pos.distance_to(s.infos.pos)
		if d <= meilleure_dist:
			meilleure_dist = d
			meilleur = {"genre": "sac", "id": int(s.infos.id), "pos": s.infos.pos, "infos": s.infos}
	if not meilleur.is_empty():
		return meilleur
	# Constructions (sauf sols et stations, gérés plus bas)
	meilleure_dist = Objets.PORTEE_RECOLTE + 4.0
	for i in constructions.values():
		if i.type in ["sol_bois", "sol_pierre", "etabli", "fourneau", "enclume"]:
			continue
		var d: float = _mvt.pos.distance_to(i.pos)
		if d <= meilleure_dist:
			meilleure_dist = d
			meilleur = {"genre": "construction", "id": int(i.id), "pos": i.pos, "infos": i}
	if not meilleur.is_empty():
		return meilleur
	meilleure_dist = Objets.PORTEE_RECOLTE
	var c0 := Vector2i((_mvt.pos / Config.TAILLE_TUILE).floor())
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := c0 + Vector2i(dx, dy)
			var deco := monde.deco_en(c.x, c.y)
			if not Objets.recoltable(deco):
				continue
			var centre := VueMonde.centre_case(c)
			var d: float = _mvt.pos.distance_to(centre)
			# Préfère légèrement ce qui est devant le joueur.
			d -= maxf(0.0, (centre - _mvt.pos).normalized().dot(_mvt.regard)) * 6.0
			if d <= meilleure_dist:
				meilleure_dist = d
				meilleur = {"genre": "deco", "case": c, "pos": centre, "deco": deco}
	if meilleur.is_empty():
		for i in constructions.values():
			if i.type in ["sol_bois", "sol_pierre"] and _mvt.pos.distance_to(i.pos) <= 20.0:
				return {"genre": "construction", "id": int(i.id), "pos": i.pos, "infos": i}
	return meilleur


func _interagir() -> void:
	if _cible.get("genre", "") == "sac":
		Reseau.c_ramasser.rpc_id(1, int(_cible.id))
	elif _cible.get("genre", "") == "construction":
		_ouvrir_construction(_cible.infos)


func _basculer_fenetre(f: Control) -> void:
	var ouvrir := not f.visible
	_inventaire_vue.visible = false
	_fabrication_vue.visible = false
	_personnage_vue.visible = false
	_construction_vue.fermer_fenetre()
	f.visible = ouvrir
	if ouvrir:
		_maj_stations()
		if f == _fabrication_vue:
			_fabrication_vue.rafraichir()
		elif f == _personnage_vue:
			_personnage_vue.maj(progression, reglages.role, reglages.get("stats", {}), inventaire)
			_personnage_vue.rafraichir()


func _maj_stations() -> void:
	var st := Atelier.stations_autour(monde, _mvt.pos)
	_inventaire_vue.stations = st
	_fabrication_vue.maj(inventaire, st)


func _maj_interaction(delta: float) -> void:
	_accu_stations += delta
	if _accu_stations > 0.5 and (_inventaire_vue.visible or _fabrication_vue.visible):
		_accu_stations = 0.0
		_maj_stations()
	_cible = _chercher_cible() if _en_jeu() or _bouton_tenu else {}
	var tenu := _bouton_tenu or Config.auto_recolte or (_en_jeu() and Input.is_action_pressed("interagir"))
	var vise_deco: bool = _cible.get("genre", "") == "deco"
	if Config.auto_recolte and _cible.get("genre", "") == "sac" and Engine.get_process_frames() % 30 == 0:
		_interagir()
	if tenu and vise_deco and not moi.est_mort():
		if not _recolte_envoyee or _recolte_case != _cible.case:
			Reseau.c_recolter.rpc_id(1, true, _cible.case)
			_recolte_envoyee = true
			_recolte_case = _cible.case
			_recolte_progres = 0.0
	elif _recolte_envoyee:
		Reseau.c_recolter.rpc_id(1, false, Vector2i.ZERO)
		_recolte_envoyee = false
		_recolte_progres = -1.0
	# Barre de progression lissée entre deux messages du serveur.
	if _recolte_envoyee and _recolte_progres >= 0.0 and Objets.recoltable(monde.deco_en(_recolte_case.x, _recolte_case.y)):
		var duree := Objets.duree_recolte(monde.deco_en(_recolte_case.x, _recolte_case.y), reglages.role, moi.drapeaux & 16 != 0,
			float(reglages.get("stats", {}).get("recolte", 0.0)))
		_recolte_progres = minf(_recolte_progres + delta / duree, 1.0)
	# Invite au-dessus de la cible
	var touche := "" if Config.est_mobile() else "F : "
	_invite.visible = not _cible.is_empty()
	if _bouton_recolter:
		_bouton_recolter.visible = not _cible.is_empty() or _bouton_tenu
	if _cible.is_empty():
		return
	if _cible.genre == "construction":
		var ic: Dictionary = _cible.infos
		var b := Batiments.infos(ic.type)
		var a_moi := _allie_de(str(ic.proprio))
		if b.has("cases") and (a_moi or not b.get("verrou", false)):
			_invite.text = "%sOuvrir : %s%s" % [touche, b.nom, "" if a_moi else " de " + str(ic.proprio)]
		elif a_moi:
			_invite.text = "%s%s (gérer)" % [touche, b.nom]
		else:
			_invite.text = "%s de %s (%d/%d)" % [b.nom, ic.proprio, ic.vie, ic.max]
	elif _cible.genre == "sac":
		var i: Dictionary = _cible.infos
		var quoi := "le sac (%d objets)" % int(i.n)
		if i.genre == "corps":
			quoi = "tes affaires" if i.nom == infos.nom else "le corps de %s (%d objets)" % [i.nom, int(i.n)]
		_invite.text = "%sRamasser %s" % [touche, quoi]
	else:
		var r: Dictionary = Objets.RECOLTE[_cible.deco]
		_invite.text = "%s%s (%s)" % [touche, r.verbe, Objets.infos(r.objet).nom]
	_invite.position = _cible.pos + Vector2(-100, -62)


func _dessiner_recolte() -> void:
	if not _recolte_envoyee or _recolte_progres < 0.0:
		return
	var centre := VueMonde.centre_case(_recolte_case) + Vector2(-14, -40)
	var r := Rect2(centre, Vector2(28, 4))
	_dessin_visee.draw_rect(r.grow(1), Color(0, 0, 0, 0.75))
	_dessin_visee.draw_rect(Rect2(r.position, Vector2(28 * _recolte_progres, 4)), Color(1, 0.85, 0.35))


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
	_debug_label.position = Vector2(-260, 200)
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

	_barre = BarreCombat.new()
	_barre.tactile = Config.est_mobile()
	_ui.add_child(_barre)
	_barre.definir_role(reglages.role)
	_barre.visee_commencee.connect(_sur_visee_tactile_commencee)
	_barre.visee_changee.connect(_sur_visee_tactile_changee)
	_barre.visee_relachee.connect(_sur_visee_tactile_relachee)
	_barre.esquive_demandee.connect(func(): _esquive_demandee = true)

	_ecran_mort = Label.new()
	_ecran_mort.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ecran_mort.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ecran_mort.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ecran_mort.add_theme_font_size_override("font_size", 34)
	_ecran_mort.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	_ecran_mort.add_theme_constant_override("outline_size", 10)
	_ecran_mort.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ecran_mort.visible = false
	_ui.add_child(_ecran_mort)

	if Config.est_mobile():
		_journal.custom_minimum_size = Vector2(400, 0)
		_joystick = Joystick.new()
		_ui.add_child(_joystick)
		var bouton_role := Button.new()
		bouton_role.text = "Rôle"
		bouton_role.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		bouton_role.position = Vector2(-300, 10)
		bouton_role.custom_minimum_size = Vector2(90, 56)
		bouton_role.pressed.connect(func(): _choix_role.visible = true)
		_ui.add_child(bouton_role)
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

	_creer_choix_role()

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.z_index = 5 # au-dessus de la mini-carte
	_ui.add_child(centre)
	_inventaire_vue = InventaireVue.new()
	_inventaire_vue.visible = false
	_inventaire_vue.action.connect(func(genre, valeur):
		if genre == "jeter":
			Reseau.c_jeter.rpc_id(1, int(valeur))
		elif genre == "poser":
			_debut_construction(int(valeur))
		else:
			Reseau.c_atelier.rpc_id(1, genre, valeur))
	centre.add_child(_inventaire_vue)
	_fabrication_vue = FabricationVue.new()
	_fabrication_vue.visible = false
	_fabrication_vue.fabriquer.connect(func(id): Reseau.c_atelier.rpc_id(1, "fabriquer", id))
	centre.add_child(_fabrication_vue)
	_personnage_vue = PersonnageVue.new()
	_personnage_vue.visible = false
	_personnage_vue.demande.connect(func(genre, valeur): Reseau.c_progression.rpc_id(1, genre, valeur))
	centre.add_child(_personnage_vue)
	_construction_vue = ConstructionVue.new()
	_construction_vue.visible = false
	_construction_vue.action.connect(func(genre, id, valeur): Reseau.c_construction.rpc_id(1, genre, id, valeur))
	centre.add_child(_construction_vue)
	_creer_construction()
	_invite = Label.new()
	_invite.z_index = 30
	_invite.custom_minimum_size = Vector2(200, 0)
	_invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invite.add_theme_font_size_override("font_size", 11)
	_invite.add_theme_constant_override("outline_size", 4)
	_invite.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_invite.visible = false
	vue.add_child(_invite)
	if Config.est_mobile():
		_bouton_recolter = Button.new()
		_bouton_recolter.icon = preload("res://assets/ui/recolter.png")
		_bouton_recolter.expand_icon = true
		_bouton_recolter.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_bouton_recolter.position = Vector2(-300, -250)
		_bouton_recolter.custom_minimum_size = Vector2(84, 84)
		_bouton_recolter.button_down.connect(func():
			_bouton_tenu = true
			_interagir())
		_bouton_recolter.button_up.connect(func(): _bouton_tenu = false)
		_bouton_recolter.visible = false
		_ui.add_child(_bouton_recolter)
		var bouton_sac := Button.new()
		bouton_sac.icon = preload("res://assets/ui/inventaire.png")
		bouton_sac.expand_icon = true
		bouton_sac.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		bouton_sac.position = Vector2(-370, 10)
		bouton_sac.custom_minimum_size = Vector2(60, 56)
		bouton_sac.pressed.connect(_basculer_fenetre.bind(_inventaire_vue))
		_ui.add_child(bouton_sac)
		var bouton_fab := Button.new()
		bouton_fab.icon = preload("res://assets/ui/fabriquer.png")
		bouton_fab.expand_icon = true
		bouton_fab.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		bouton_fab.position = Vector2(-440, 10)
		bouton_fab.custom_minimum_size = Vector2(60, 56)
		bouton_fab.pressed.connect(_basculer_fenetre.bind(_fabrication_vue))
		_ui.add_child(bouton_fab)
		var bouton_perso := Button.new()
		bouton_perso.icon = preload("res://assets/ui/personnage.png")
		bouton_perso.expand_icon = true
		bouton_perso.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		bouton_perso.position = Vector2(-510, 10)
		bouton_perso.custom_minimum_size = Vector2(60, 56)
		bouton_perso.pressed.connect(_basculer_fenetre.bind(_personnage_vue))
		_ui.add_child(bouton_perso)

	_lieu = Label.new()
	_lieu.position = Vector2(12, 30)
	_lieu.add_theme_font_size_override("font_size", 15)
	_ui.add_child(_lieu)
	_minicarte = CarteVue.new()
	_minicarte.vue = vue
	_minicarte.custom_minimum_size = Vector2(170, 170)
	_minicarte.size = Vector2(170, 170)
	_minicarte.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minicarte.position = Vector2(-182, 80 if Config.est_mobile() else 12)
	_minicarte.mouse_filter = Control.MOUSE_FILTER_STOP
	_minicarte.gui_input.connect(func(ev):
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed:
			_grande_carte.visible = true)
	_ui.add_child(_minicarte)
	_grande_carte = CarteVue.new()
	_grande_carte.vue = vue
	_grande_carte.grande = true
	_grande_carte.pixels_par_case = 3.0
	_grande_carte.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grande_carte.offset_left = 60
	_grande_carte.offset_top = 50
	_grande_carte.offset_right = -60
	_grande_carte.offset_bottom = -50
	_grande_carte.visible = false
	_grande_carte.mouse_filter = Control.MOUSE_FILTER_STOP
	_grande_carte.gui_input.connect(func(ev):
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed:
			_grande_carte.visible = false)
	_ui.add_child(_grande_carte)

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
	var changer := Button.new()
	changer.text = "Changer de rôle"
	changer.custom_minimum_size = Vector2(0, 48)
	changer.pressed.connect(func():
		_menu_pause.visible = false
		_choix_role.visible = true)
	vb.add_child(changer)
	var aide := Label.new()
	aide.text = "ZQSD ou flèches : se déplacer\nClic gauche : attaque (maintenir pour charger l'arc)\nClic droit ou E : compétence\nEspace : esquive    R : changer de rôle    M : carte    F : récolter / ramasser    I : inventaire (Construire)    C : fabriquer    P : personnage    G : grille / libre\nEntrée : chat (/aide)    F3 : infos développeur"
	aide.add_theme_font_size_override("font_size", 14)
	aide.modulate.a = 0.7
	vb.add_child(aide)


func _creer_choix_role() -> void:
	_choix_role = PanelContainer.new()
	_choix_role.set_anchors_preset(Control.PRESET_CENTER)
	_choix_role.position = Vector2(-450, -250)
	_choix_role.custom_minimum_size = Vector2(900, 0)
	_choix_role.visible = false
	_ui.add_child(_choix_role)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_choix_role.add_child(vb)
	var titre := Label.new()
	titre.text = "Choisis ton rôle"
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titre.add_theme_font_size_override("font_size", 26)
	vb.add_child(titre)
	var grille := GridContainer.new()
	grille.columns = 4
	grille.add_theme_constant_override("h_separation", 10)
	grille.add_theme_constant_override("v_separation", 10)
	vb.add_child(grille)
	for role in Roles.ORDRE:
		var d: Dictionary = Roles.LISTE[role]
		var b := Button.new()
		b.custom_minimum_size = Vector2(270, 140)
		b.icon = load("res://assets/ui/role_%s.png" % role)
		b.expand_icon = false
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 14)
		b.text = "%s  (vie %d)\n%s\nAttaque : %s\nCompétence : %s" % [d.nom, d.vie, d.description, d.attaque.nom, d.competence.nom]
		b.pressed.connect(choisir_role.bind(role))
		grille.add_child(b)
	var fermer := Button.new()
	fermer.text = "Fermer"
	fermer.pressed.connect(func(): _choix_role.visible = false)
	vb.add_child(fermer)
	var note := Label.new()
	note.text = "On ne peut pas changer de rôle en plein combat. Changer de rôle rend tes points de compétence (le niveau reste). Touche R pour revenir ici."
	note.add_theme_font_size_override("font_size", 13)
	note.modulate.a = 0.7
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(note)


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
	"commande": Color(0.6, 1, 0.65), "boss": Color(1, 0.5, 0.35), "combat": Color(1, 0.7, 0.55),
}


func _ajouter_message(texte: String, genre: String) -> void:
	if Config.auto_connexion != "":
		print("[message] ", texte)
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


# ------------------------------------------------------------------ Constructions (étape 6)

func _allie_de(proprio: String) -> bool:
	if proprio == "" or proprio == str(infos.nom):
		return true
	if reglages.equipe == "":
		return false
	for a in autres.values():
		if a.nom == proprio:
			return a.equipe == reglages.equipe
	return false


func _maj_construction(i: Dictionary) -> void:
	var id := int(i.id)
	constructions[id] = i
	if not i.grille and not _noeuds_c.has(id):
		var spr := Sprite2D.new()
		var chemin := "res://assets/constructions/%s.png" % i.type
		spr.texture = load(chemin) if ResourceLoader.exists(chemin) else TEX_SAC
		spr.offset = Vector2(0, -spr.texture.get_height() / 2.0 + 3)
		spr.position = i.pos
		if i.get("temporaire", false):
			spr.modulate = Color(0.75, 0.9, 1.0, 0.85)
		vue.objets.add_child(spr)
		_noeuds_c[id] = spr
	if _construction_vue.visible and int(_construction_vue.rec.get("id", -1)) == id:
		_construction_vue.rec = i
		_construction_vue.rafraichir()


func _retirer_construction(id: int) -> void:
	constructions.erase(id)
	if _noeuds_c.has(id):
		_noeuds_c[id].queue_free()
		_noeuds_c.erase(id)
	if _construction_vue.visible and int(_construction_vue.rec.get("id", -1)) == id:
		_construction_vue.visible = false


func _ouvrir_construction(i: Dictionary) -> void:
	var b := Batiments.infos(i.type)
	var a_moi := _allie_de(str(i.proprio))
	if not a_moi and not b.has("cases"):
		return
	_inventaire_vue.visible = false
	_fabrication_vue.visible = false
	_personnage_vue.visible = false
	_construction_vue.ouvrir(i, a_moi, inventaire)
	if b.has("cases"):
		Reseau.c_construction.rpc_id(1, "ouvrir", int(i.id), 0)


func _dessiner_barres_constructions() -> void:
	for i in constructions.values():
		if int(i.vie) >= int(i.max) or _mvt.pos.distance_to(i.pos) > 500.0:
			continue
		var haut := 52.0 if i.grille and Batiments.infos(i.type).get("deco", -1) in Monde.DECOS_PLEINES else 40.0
		var r := Rect2(i.pos + Vector2(-14, -haut), Vector2(28, 4))
		var part := clampf(float(i.vie) / maxf(1.0, float(i.max)), 0.0, 1.0)
		_barres_c.draw_rect(r.grow(1), Color(0, 0, 0, 0.75))
		_barres_c.draw_rect(Rect2(r.position, Vector2(28 * part, 4)), Color(0.9, 0.3, 0.2).lerp(Color(0.95, 0.85, 0.3), part))


func _creer_construction() -> void:
	_barres_c = Node2D.new()
	_barres_c.z_index = 20
	_barres_c.draw.connect(_dessiner_barres_constructions)
	vue.add_child(_barres_c)
	_fantome = Sprite2D.new()
	_fantome.z_index = 10
	_fantome.visible = false
	vue.add_child(_fantome)
	_aide_construction = Label.new()
	_aide_construction.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_aide_construction.position = Vector2(-300, -150)
	_aide_construction.custom_minimum_size = Vector2(600, 0)
	_aide_construction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aide_construction.add_theme_font_size_override("font_size", 15)
	_aide_construction.add_theme_constant_override("outline_size", 5)
	_aide_construction.add_theme_color_override("font_outline_color", Color.BLACK)
	_aide_construction.visible = false
	_ui.add_child(_aide_construction)
	if Config.est_mobile():
		_boutons_construction = HBoxContainer.new()
		_boutons_construction.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_boutons_construction.position = Vector2(-220, -110)
		_boutons_construction.add_theme_constant_override("separation", 10)
		_boutons_construction.visible = false
		_ui.add_child(_boutons_construction)
		for d in [["Poser", _poser], ["Grille / libre", func(): _construire_grille = not _construire_grille], ["Fin", _fin_construction]]:
			var b := Button.new()
			b.text = d[0]
			b.custom_minimum_size = Vector2(130, 56)
			b.pressed.connect(d[1])
			_boutons_construction.add_child(b)


func _debut_construction(case: int) -> void:
	if case < 0 or case >= inventaire.size() or inventaire[case].is_empty() or not Batiments.existe(str(inventaire[case].id)):
		return
	_construire_case = case
	_inventaire_vue.visible = false
	_fantome.visible = true
	_aide_construction.visible = true
	if _boutons_construction:
		_boutons_construction.visible = true


func _fin_construction() -> void:
	_construire_case = -1
	_fantome.visible = false
	_aide_construction.visible = false
	if _boutons_construction:
		_boutons_construction.visible = false


## Position de pose : la souris (à portée) ou devant le joueur sur téléphone.
func _point_construction() -> Vector2:
	var p: Vector2
	if Config.est_mobile():
		p = _mvt.pos + _mvt.regard * 40.0
	else:
		p = vue.get_global_mouse_position()
		if p.distance_to(_mvt.pos) > Batiments.PORTEE:
			p = _mvt.pos + (p - _mvt.pos).normalized() * Batiments.PORTEE
	var type := _type_construction()
	if Batiments.grille_seulement(type) or _construire_grille:
		p = VueMonde.centre_case(Vector2i((p / Config.TAILLE_TUILE).floor()))
	return p


func _type_construction() -> String:
	if _construire_case < 0 or _construire_case >= inventaire.size() or inventaire[_construire_case].is_empty():
		return ""
	return str(inventaire[_construire_case].id)


func _poser() -> void:
	var type := _type_construction()
	if type == "":
		_fin_construction()
		return
	Reseau.c_construire.rpc_id(1, _construire_case, _point_construction(), _construire_grille)


func _maj_construction_mode() -> void:
	if _construire_case < 0:
		return
	var type := _type_construction()
	if type == "" or not Batiments.existe(type):
		# Plus rien à poser dans cette case : on cherche la même chose ailleurs, sinon on arrête.
		_fin_construction()
		return
	var b := Batiments.infos(type)
	var p := _point_construction()
	if b.mode == "grille":
		var tex: Texture2D = VueMonde.TEX_DECOS.get(int(b.deco))
		_fantome.texture = tex
		_fantome.offset = Vector2(0, -tex.get_height() / 2.0 + 4) if tex else Vector2.ZERO
		_fantome.position = p + Vector2(0, Config.TAILLE_TUILE * 0.2)
		if int(b.deco) in VueMonde.DECOS_CONSTRUITES:
			_fantome.position = p + Vector2(0, Config.TAILLE_TUILE * 0.5)
			_fantome.offset = Vector2(0, -tex.get_height() / 2.0)
		elif int(b.deco) in VueMonde.DECOS_PLATES:
			_fantome.position = p
			_fantome.offset = Vector2.ZERO
	else:
		var chemin := "res://assets/constructions/%s.png" % type
		_fantome.texture = load(chemin) if ResourceLoader.exists(chemin) else TEX_SAC
		_fantome.offset = Vector2(0, -_fantome.texture.get_height() / 2.0 + 3)
		_fantome.position = p
	var ok := _pose_possible(type, p)
	_fantome.modulate = Color(0.6, 1, 0.6, 0.6) if ok else Color(1, 0.4, 0.4, 0.6)
	var touches := "" if Config.est_mobile() else "Clic gauche : poser   ·   %sÉchap ou clic droit : terminer" % ("" if b.mode == "grille" else "G : grille / libre   ·   ")
	_aide_construction.text = "Construction : %s (×%d)%s\n%s" % [b.nom, Objets.compter(inventaire, type),
		"" if b.mode == "grille" else ("   ·   sur la grille" if _construire_grille else "   ·   placement libre"), touches]


## Vérification côté jeu (le serveur décide) : case libre pour la grille, pas d'obstacle sinon.
func _pose_possible(type: String, p: Vector2) -> bool:
	var c := Vector2i((p / Config.TAILLE_TUILE).floor())
	if monde.sol_en(c.x, c.y) in Monde.SOLS_BLOQUANTS:
		return false
	var d := monde.deco_en(c.x, c.y)
	if Batiments.grille_seulement(type):
		var boite := Rect2(Vector2(c) * Config.TAILLE_TUILE, Vector2.ONE * Config.TAILLE_TUILE).grow(Config.RAYON_JOUEUR)
		if Batiments.infos(type).deco in Monde.DECOS_BLOQUANTES and boite.has_point(_mvt.pos):
			return false
		return d == Monde.Deco.AUCUN
	if d != Monde.Deco.AUCUN and not d in [Monde.Deco.SOL_BOIS, Monde.Deco.SOL_PIERRE, Monde.Deco.FLEURS, Monde.Deco.OS]:
		return false
	for i in constructions.values():
		if not i.grille and Vector2(i.pos).distance_to(p) < Batiments.ECART_LIBRE:
			return false
	return true
