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
	if infos.get("nouveau", false) and Config.auto_connexion == "":
		_choix_role.visible = true
	if Config.auto_commande != "":
		for c in Config.auto_commande.split(";"):
			Reseau.c_chat.rpc_id(1, c)


func _en_jeu() -> bool:
	return not _saisie.has_focus() and not _menu_pause.visible and not _choix_role.visible


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


func _process(delta: float) -> void:
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
	elif event.is_action_pressed("menu"):
		if _saisie.has_focus():
			_saisie.release_focus()
			_saisie.visible = false
		elif _choix_role.visible:
			_choix_role.visible = false
		else:
			_menu_pause.visible = not _menu_pause.visible
	elif not _en_jeu() or _visee_tactile:
		return
	elif event.is_action_pressed("role"):
		_choix_role.visible = true
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
	return Roles.donnees(reglages.role)[genre]


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
		"lancer", "zone_visee":
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
	for a in autres.values():
		_maj_allie(a)


func _maj_allie(a: JoueurVisuel) -> void:
	a.allie = reglages.equipe != "" and a.equipe == reglages.equipe
	if a.allie:
		a.definir_couleur_nom(Color(0.55, 1, 0.55))


func _ajouter_autre(id: int, i: Dictionary) -> void:
	if id == mon_id:
		return
	var j: JoueurVisuel = autres.get(id)
	if j == null:
		j = JoueurVisuel.new(str(i.nom), int(i.apparence), bool(i.get("admin", false)))
		j.position = i.pos
		j.ajouter_instantane(i.pos)
		vue.objets.add_child(j)
		autres[id] = j
	j.definir_role(str(i.get("role", "guerrier")))
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
		"mannequin_retire":
			if mannequins.has(int(d.id)):
				mannequins[int(d.id)].queue_free()
				mannequins.erase(int(d.id))


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
	aide.text = "ZQSD ou flèches : se déplacer\nClic gauche : attaque (maintenir pour charger l'arc)\nClic droit ou E : compétence\nEspace : esquive    R : changer de rôle\nEntrée : chat (/aide)    F3 : infos développeur"
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
	grille.columns = 3
	grille.add_theme_constant_override("h_separation", 10)
	grille.add_theme_constant_override("v_separation", 10)
	vb.add_child(grille)
	for role in Roles.ORDRE:
		var d: Dictionary = Roles.LISTE[role]
		var b := Button.new()
		b.custom_minimum_size = Vector2(285, 150)
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
	note.text = "On ne peut pas changer de rôle en plein combat. Touche R pour revenir ici."
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
