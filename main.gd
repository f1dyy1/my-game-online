extends Node2D

# После запуска сервера на Render впиши сюда его адрес (Этап Б).
const SERVER_URL := "ws://127.0.0.1:7777"
const SPEED := 350.0

var players := {}            # id игрока -> его квадрат
var target := Vector2.ZERO   # куда мы идём
var last_sent := Vector2.INF # последняя отправленная позиция
var server_clients := 0      # сколько игроков подключено (считает сервер)

var panel: VBoxContainer
var url_input: LineEdit
var status: Label


func _ready() -> void:
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Таймер: раз в 25 секунд шлём серверу "я жив", чтобы он не засыпал
	var beat := Timer.new()
	beat.wait_time = 25.0
	beat.autostart = true
	beat.timeout.connect(_on_beat)
	add_child(beat)

	# Если игра запущена без экрана (так будет на хостинге) — сразу становимся сервером
	if DisplayServer.get_name() == "headless":
		_start_server()


# ---------- Интерфейс ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	status = Label.new()
	status.position = Vector2(20, 20)
	status.add_theme_font_size_override("font_size", 26)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(500, 0)
	layer.add_child(status)

	panel = VBoxContainer.new()
	panel.position = Vector2(40, 250)
	panel.custom_minimum_size = Vector2(460, 0)
	panel.add_theme_constant_override("separation", 20)
	layer.add_child(panel)

	url_input = LineEdit.new()
	url_input.text = SERVER_URL
	url_input.add_theme_font_size_override("font_size", 24)
	panel.add_child(url_input)

	var join_btn := _make_button("Играть")
	join_btn.pressed.connect(_on_join_pressed)

	var test_btn := _make_button("Тест: запустить сервер здесь")
	test_btn.pressed.connect(_start_server)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 90)
	b.add_theme_font_size_override("font_size", 28)
	panel.add_child(b)
	return b


# ---------- Сервер ----------

func _start_server() -> void:
	var port := 7777
	if OS.has_environment("PORT"):  # хостинг сам говорит, какой порт использовать
		port = int(OS.get_environment("PORT"))
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		status.text = "Не удалось запустить сервер (код %d)" % err
		print("Server start failed: ", err)
		return
	multiplayer.multiplayer_peer = peer
	panel.hide()
	_update_status()
	print("Сервер запущен, порт ", port)


# ---------- Подключение игрока ----------

func _on_join_pressed() -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url_input.text.strip_edges())
	if err != OK:
		status.text = "Неверный адрес (код %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	status.text = "Подключаюсь... Если сервер спал, это может занять минуту."
	panel.hide()
	get_tree().create_timer(75.0).timeout.connect(_check_connect_timeout)


func _check_connect_timeout() -> void:
	var p := multiplayer.multiplayer_peer
	if p != null and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		_on_connection_failed()


func _on_connected_to_server() -> void:
	_add_player(multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	status.text = "Не получилось подключиться. Сервер мог спать: подожди минуту и нажми «Играть» ещё раз."
	panel.show()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		server_clients += 1
		print("Подключился игрок ", id)
		_update_status()
	elif id != 1:  # номер 1 — это сервер, он не игрок
		_add_player(id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		server_clients -= 1
		print("Отключился игрок ", id)
		_update_status()
	else:
		_remove_player(id)


func _on_beat() -> void:
	if not multiplayer.is_server() and players.has(multiplayer.get_unique_id()):
		_heartbeat.rpc_id(1)


@rpc("any_peer", "reliable")
func _heartbeat() -> void:
	pass


# ---------- Игроки ----------

func _add_player(id: int) -> void:
	if players.has(id):
		return
	var p := Node2D.new()
	var body := ColorRect.new()
	body.size = Vector2(60, 60)
	body.position = Vector2(-30, -30)
	body.color = Color.from_hsv(fmod(id * 0.137, 1.0), 0.8, 1.0)
	p.add_child(body)
	p.position = Vector2(randf_range(100, 440), randf_range(200, 800))
	add_child(p)
	players[id] = p
	if id == multiplayer.get_unique_id():
		target = p.position
	_update_status()


func _remove_player(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
	_update_status()


func _update_status() -> void:
	if multiplayer.is_server():
		status.text = "Сервер работает. Подключено: %d" % server_clients
	else:
		status.text = "Игроков: %d" % players.size()


# ---------- Управление (мышь на ПК = касание на телефоне) ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		target = get_global_mouse_position()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		target = get_global_mouse_position()


func _process(delta: float) -> void:
	var my_id := multiplayer.get_unique_id()
	if not players.has(my_id):
		return
	var me: Node2D = players[my_id]
	me.position = me.position.move_toward(target, SPEED * delta)
	if me.position != last_sent:
		last_sent = me.position
		_sync_position.rpc(me.position)


@rpc("any_peer", "unreliable")
func _sync_position(pos: Vector2) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].position = pos
