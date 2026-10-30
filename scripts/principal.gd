extends Node
## Point d'entrée : lance le serveur (option --serveur ou export « Serveur ») ou le jeu.


func _ready() -> void:
	if Config.est_serveur:
		var serveur: Node = preload("res://scripts/serveur/serveur.gd").new()
		serveur.name = "Serveur"
		add_child(serveur)
		if not Config.sans_affichage:
			get_window().title = "Craftclans - Serveur %s" % Config.version
			var panneau: Control = preload("res://scripts/serveur/panneau_admin.gd").new(serveur)
			add_child(panneau)
	else:
		get_window().title = "Craftclans %s" % Config.version
		aller_au_menu("")
	if Config.capture != "":
		_capturer.call_deferred(Config.capture.get_slice(":", 0), float(Config.capture.get_slice(":", 1)))


## Outil de test : capture d'écran après un délai, puis fermeture.
func _capturer(fichier: String, delai: float) -> void:
	await get_tree().create_timer(delai).timeout
	get_viewport().get_texture().get_image().save_png(fichier)
	print("Capture enregistrée : ", fichier)
	get_tree().quit()


func aller_au_menu(message: String) -> void:
	for enfant in get_children():
		enfant.queue_free()
	var menu: Node = preload("res://scripts/client/menu.gd").new()
	menu.message_initial = message
	add_child(menu)


func aller_au_jeu(infos: Dictionary) -> void:
	for enfant in get_children():
		enfant.queue_free()
	var jeu: Node = preload("res://scripts/client/jeu.gd").new()
	jeu.infos = infos
	add_child(jeu)
