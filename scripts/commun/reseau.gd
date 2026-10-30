extends Node
## Tous les messages réseau passent par ici (WebSocket, port 8000 par défaut).
## WebSocket est utilisé pour tous les clients (exe, apk, et plus tard le web).
## Préfixe c_ : envoyé par un client au serveur. Préfixe s_ : envoyé par le serveur.

signal connecte
signal echec(raison: String)
signal deconnecte(raison: String)
signal accueil(infos: Dictionary)
signal etat_recu(etat: Dictionary)
signal joueur_arrive(id: int, infos: Dictionary)
signal joueur_parti(id: int)
signal message_recu(texte: String, genre: String)
signal reglages_recus(reglages: Dictionary)
signal teleporte(pos: Vector2)
signal evenement(genre: String, donnees: Dictionary)
signal pong(ms: int)

var serveur: Node = null # renseigné côté serveur
var raison_refus := ""
var _limite_connexion := 0.0


# ------------------------------------------------------------------ Client

func connecter(adresse: String, infos: Dictionary) -> void:
	fermer()
	raison_refus = ""
	var url := adresse_vers_url(adresse)
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		echec.emit("Adresse invalide : %s" % url)
		return
	multiplayer.multiplayer_peer = peer
	_limite_connexion = Time.get_ticks_msec() + 8000
	if not multiplayer.connected_to_server.is_connected(_sur_connecte):
		multiplayer.connected_to_server.connect(_sur_connecte)
		multiplayer.connection_failed.connect(_sur_echec)
		multiplayer.server_disconnected.connect(_sur_deconnexion)
	set_meta("infos", infos)


static func adresse_vers_url(adresse: String) -> String:
	adresse = adresse.strip_edges()
	if adresse.begins_with("ws://") or adresse.begins_with("wss://"):
		return adresse
	if adresse == "":
		adresse = "localhost"
	if not ":" in adresse:
		adresse += ":%d" % Config.PORT_DEFAUT
	return "ws://" + adresse


func fermer() -> void:
	_limite_connexion = 0.0
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func est_connecte() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not p is OfflineMultiplayerPeer \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(_delta: float) -> void:
	if _limite_connexion > 0.0 and Time.get_ticks_msec() > _limite_connexion:
		_limite_connexion = 0.0
		if not est_connecte():
			fermer()
			echec.emit("Le serveur ne répond pas. Vérifie l'adresse et que le serveur est lancé.")


func _sur_connecte() -> void:
	_limite_connexion = 0.0
	c_bonjour.rpc_id(1, get_meta("infos", {}))
	connecte.emit()


func _sur_echec() -> void:
	_limite_connexion = 0.0
	fermer()
	echec.emit("Connexion impossible.")


func _sur_deconnexion() -> void:
	fermer()
	deconnecte.emit(raison_refus if raison_refus != "" else "Connexion au serveur perdue.")


# ------------------------------------------------------------------ Client vers serveur

@rpc("any_peer", "call_remote", "reliable")
func c_bonjour(infos: Dictionary) -> void:
	if serveur: serveur.sur_bonjour(multiplayer.get_remote_sender_id(), infos)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func c_entree(seq: int, dir: Vector2, boutons: int) -> void:
	if serveur: serveur.sur_entree(multiplayer.get_remote_sender_id(), seq, dir, boutons)


@rpc("any_peer", "call_remote", "reliable")
func c_action(genre: String, cible: Vector2, charge: float) -> void:
	if serveur: serveur.sur_action(multiplayer.get_remote_sender_id(), genre, cible, charge)


@rpc("any_peer", "call_remote", "reliable")
func c_role(role: String) -> void:
	if serveur: serveur.sur_role(multiplayer.get_remote_sender_id(), role)


@rpc("any_peer", "call_remote", "reliable")
func c_chat(texte: String) -> void:
	if serveur: serveur.sur_chat(multiplayer.get_remote_sender_id(), texte)


@rpc("any_peer", "call_remote", "unreliable")
func c_ping(t: int) -> void:
	if serveur: s_pong.rpc_id(multiplayer.get_remote_sender_id(), t)


# ------------------------------------------------------------------ Serveur vers client

@rpc("authority", "call_remote", "reliable")
func s_accueil(infos: Dictionary) -> void:
	accueil.emit(infos)


@rpc("authority", "call_remote", "reliable")
func s_refus(raison: String) -> void:
	raison_refus = raison


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func s_etat(etat: Dictionary) -> void:
	etat_recu.emit(etat)


@rpc("authority", "call_remote", "reliable")
func s_joueur(id: int, infos: Dictionary) -> void:
	joueur_arrive.emit(id, infos)


@rpc("authority", "call_remote", "reliable")
func s_depart(id: int) -> void:
	joueur_parti.emit(id)


@rpc("authority", "call_remote", "reliable")
func s_message(texte: String, genre: String) -> void:
	message_recu.emit(texte, genre)


@rpc("authority", "call_remote", "reliable")
func s_reglages(reglages: Dictionary) -> void:
	reglages_recus.emit(reglages)


@rpc("authority", "call_remote", "reliable")
func s_teleport(pos: Vector2) -> void:
	teleporte.emit(pos)


@rpc("authority", "call_remote", "reliable")
func s_evenement(genre: String, donnees: Dictionary) -> void:
	evenement.emit(genre, donnees)


@rpc("authority", "call_remote", "unreliable")
func s_pong(t: int) -> void:
	pong.emit(Time.get_ticks_msec() - t)
