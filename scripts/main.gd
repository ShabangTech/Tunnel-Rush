extends Node
## Tunnel Rush entry point. Builds the course, runs the menu and lobby, and handles
## hosting, joining and spawning racers (up to 4, players or bots).
##
## Command line (after --), handy for testing:
##   --solo | --host | --join=IP     how to start
##   --name=NAME  --bots=N           your name; bots the host adds
##   --expect=N                      host starts the race once N racers are in
##   --autopilot                     your skater drives itself
##   --quit-after-race               print the results and quit
##   --log-tricks                    print every trick, bail and hazard hit
##   --shots=4,10,16                 save screenshots (shot_<seconds>.png) at those times

const PORT := 7777
const MAX_RACERS := 4
const Level := preload("res://scripts/level.gd")
const Skater := preload("res://scripts/skater.gd")
const Race := preload("res://scripts/race.gd")
const Hud := preload("res://scripts/hud.gd")
const COLORS: Array[Color] = [Color("ff5a36"), Color("2fb8ff"), Color("ffd23f"), Color("7cff6b")]
const BOT_NAMES: Array[String] = ["Drip", "Grate", "Rat King", "Splash"]

var level
var players: Node3D
var spawner: MultiplayerSpawner
var race
var hud
var camera: Camera3D

var _opts := {}
var _in_session := false
var _orbit := 0.0
var _next_bot := 0
var _menu: CanvasLayer
var _main_panel: PanelContainer
var _lobby_panel: PanelContainer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _roster: Label
var _waiting: Label
var _start_button: Button
var _bot_button: Button


func _ready() -> void:
	_parse_args()
	_setup_input()

	level = Level.new()
	level.name = "Level"
	add_child(level)
	players = Node3D.new()
	players.name = "Players"
	add_child(players)
	spawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	add_child(spawner)
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_racer
	race = Race.new()
	race.name = "Race"
	race.main = self
	add_child(race)

	camera = Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.position = Vector3(0, 3.0, 5.0)
	camera.look_at(Vector3(0, 1.0, -20.0))

	hud = Hud.new()
	hud.main = self
	add_child(hud)
	_build_menu()

	race.state_changed.connect(_on_race_state)
	race.racer_finished.connect(func(n, p, t): print("[finish] %d. %s %s" % [p, n, Race.format_time(t)]))
	race.results_ready.connect(_on_results)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _status.text = "Could not connect.")
	multiplayer.server_disconnected.connect(func(): _leave("The host left the race."))
	_run_cli()
	if _opts.has("shots"):
		_take_shots(str(_opts["shots"]).split(","))


func _take_shots(times: PackedStringArray) -> void:
	var elapsed := 0.0
	for t in times:
		await get_tree().create_timer(float(t) - elapsed).timeout
		elapsed = float(t)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://shot_%s.png" % t)
		print("[shot] " + ProjectSettings.globalize_path("user://shot_%s.png" % t))


func _process(delta: float) -> void:
	var me = local_skater()
	if me:
		if _opts.has("autopilot"):
			me.autopilot = true
		_follow_camera(me, delta)
	if _lobby_panel.visible:
		_update_roster()
	if multiplayer.is_server() and _opts.has("expect") and race.state == Race.State.LOBBY:
		if players.get_child_count() >= int(_opts["expect"]):
			race.host_start()


## Camera flow: a face-to-face look at your panda in the lobby, a swoop around to
## behind during the countdown, a wider, higher view on The Drop, and a slow orbit
## once you cross the finish.
func _follow_camera(me, delta: float) -> void:
	var back: Vector3 = me.global_basis.z
	var pos: Vector3 = me.global_position
	var target: Vector3
	var look: Vector3 = pos + Vector3.UP * 1.3 - back * 4.0
	var rate := 6.0
	match race.state:
		Race.State.LOBBY:
			target = pos - back * 3.6 + Vector3.UP * 1.9
			look = pos + Vector3.UP * 1.6
		Race.State.COUNTDOWN:
			var k := clampf(1.0 - race.countdown / Race.COUNTDOWN_SECONDS, 0.0, 1.0)
			var angle := PI * (1.0 - k)                                 # from in front to behind
			var around := back.rotated(Vector3.UP, angle)
			target = pos + around * lerpf(3.6, 5.0, k) + Vector3.UP * lerpf(1.9, 2.6, k)
			look = pos + Vector3.UP * lerpf(1.6, 1.2, k) - back * 4.0 * k
			rate = 10.0
		_:
			if me.finished:
				_orbit += delta * 0.5
				target = pos + back.rotated(Vector3.UP, _orbit) * 4.5 + Vector3.UP * 2.2
				look = pos + Vector3.UP * 1.4
				rate = 3.0
			elif me.freestyle_active:
				target = pos + back * 5.4 + Vector3.UP * 3.3
				look = pos + Vector3.UP * 1.0 - back * 3.0
				rate = 8.0
			else:
				_orbit = 0.0
				target = pos + back * 5.0 + Vector3.UP * 2.6
				rate = 8.0
	camera.global_position = camera.global_position.lerp(target, clampf(delta * rate, 0.0, 1.0))
	if not camera.global_position.is_equal_approx(look):
		camera.look_at(look)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _in_session:
		_leave("")


## The skater this computer controls (not a bot), or null.
func local_skater():
	var me := multiplayer.get_unique_id()
	for skater in players.get_children():
		if not skater.is_bot and skater.peer_id == me:
			return skater
	return null


# ---------------------------------------------------------------- sessions

func start_solo() -> void:
	_in_session = true
	_spawn_for(1, _name())
	for i in MAX_RACERS - 1:
		add_bot()
	_show_lobby()
	race.host_start()


func start_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_RACERS - 1)
	if err != OK:
		_status.text = "Could not host on port %d (error %d)." % [PORT, err]
		return
	multiplayer.multiplayer_peer = peer
	_in_session = true
	_spawn_for(1, _name())
	print("[host] listening on port %d" % PORT)
	_show_lobby()


func start_join(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		_status.text = "Could not start connecting (error %d)." % err
		return
	multiplayer.multiplayer_peer = peer
	_status.text = "Connecting to %s..." % address


func add_bot() -> void:
	if not multiplayer.is_server() or _free_slot() < 0 or race.state != Race.State.LOBBY and race.state != Race.State.RESULTS:
		return
	_spawn_for(1001 + _next_bot, BOT_NAMES[_next_bot % BOT_NAMES.size()], true)
	_next_bot += 1


func _on_connected() -> void:
	_in_session = true
	_register.rpc_id(1, _name())
	print("[client] connected as peer %d" % multiplayer.get_unique_id())
	_show_lobby()


## A joining player tells the host their name; the host gives them a spot on the grid.
@rpc("any_peer", "reliable")
func _register(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var in_race: bool = race.state == Race.State.COUNTDOWN or race.state == Race.State.RACING
	if in_race or _free_slot() < 0:
		var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if peer:
			peer.disconnect_peer(id)
		return
	_spawn_for(id, player_name.strip_edges().left(14))
	print("[host] %s joined (peer %d)" % [player_name, id])


func _spawn_for(id: int, racer_name: String, bot := false) -> void:
	var grid_slot := _free_slot()
	spawner.spawn({
		"id": id, "bot": bot, "slot": grid_slot,
		"name": racer_name if racer_name != "" else "Skater %d" % (grid_slot + 1),
		"color": COLORS[grid_slot],
	})


func _spawn_racer(data: Dictionary) -> Node:
	var skater := Skater.new()
	skater.setup(data)
	if _opts.has("log-tricks"):
		skater.trick_event.connect(func(text, _kind): print("  [%s] %s" % [skater.racer_name, text]))
	return skater


func _free_slot() -> int:
	var taken := []
	for skater in players.get_children():
		taken.append(skater.slot)
	for i in MAX_RACERS:
		if i not in taken:
			return i
	return -1


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		var skater := players.get_node_or_null("P%d" % id)
		if skater:
			skater.queue_free()


func _leave(message: String) -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if message != "":
		print("[session] " + message)
	if _opts.has("quit-after-race"):
		get_tree().quit()
		return
	get_tree().reload_current_scene()


func _on_race_state(state: int) -> void:
	var racing: bool = state == Race.State.COUNTDOWN or state == Race.State.RACING
	hud.visible = state != Race.State.LOBBY
	_lobby_panel.visible = not racing and _in_session
	_start_button.text = "Race again" if state == Race.State.RESULTS else "Start race"
	if racing:
		get_viewport().gui_release_focus()


func _on_results(results: Array) -> void:
	print("[results]")
	for i in results.size():
		print("  %d. %s %s" % [i + 1, results[i].name, Race.format_time(results[i].time)])
	if _opts.has("quit-after-race"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


# --------------------------------------------------------------- menu & lobby

func _show_lobby() -> void:
	_main_panel.visible = false
	_lobby_panel.visible = true
	var host := multiplayer.is_server()
	_start_button.visible = host
	_bot_button.visible = host
	_waiting.visible = not host


func _update_roster() -> void:
	var text := ""
	for skater in players.get_children():
		text += "%s%s\n" % [skater.racer_name, "  (bot)" if skater.is_bot else ""]
	_roster.text = text
	_bot_button.disabled = _free_slot() < 0


func _build_menu() -> void:
	_menu = CanvasLayer.new()
	_menu.layer = 10
	add_child(_menu)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)
	_main_panel = PanelContainer.new()
	center.add_child(_main_panel)
	var box := _vbox(_main_panel)
	_text(box, "TUNNEL RUSH", 48)
	_text(box, "Online skateboard race through a flooded tunnel", 16)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.text = _opts.get("name", "")
	_name_edit.max_length = 14
	box.add_child(_name_edit)
	_button(box, "Race the bots", start_solo)
	_button(box, "Host an online race", start_host)
	var row := HBoxContainer.new()
	box.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ip_edit)
	_button(row, "Join", func(): start_join(_ip_edit.text.strip_edges()))
	_status = _text(box, "", 14)

	_lobby_panel = PanelContainer.new()
	_lobby_panel.position = Vector2(920, 110)
	_lobby_panel.custom_minimum_size = Vector2(320, 0)
	_lobby_panel.visible = false
	_menu.add_child(_lobby_panel)
	var lobby := _vbox(_lobby_panel)
	_text(lobby, "RACERS", 24)
	_roster = _text(lobby, "", 18)
	_bot_button = _button(lobby, "Add a bot", add_bot)
	_start_button = _button(lobby, "Start race", race.host_start)
	_waiting = _text(lobby, "Waiting for the host to start...", 14)
	_button(lobby, "Leave", func(): _leave(""))


func _vbox(parent: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	parent.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(320, 0)
	margin.add_child(box)
	return box


func _text(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _name() -> String:
	return _name_edit.text.strip_edges() if _name_edit else ""


# ----------------------------------------------------------------- setup

func _setup_input() -> void:
	if InputMap.has_action("kick"):
		return                                       # already set up (scene reloaded)
	var keys := {
		"kick": [KEY_W, KEY_UP], "brake": [KEY_S, KEY_DOWN],
		"steer_left": [KEY_A, KEY_LEFT], "steer_right": [KEY_D, KEY_RIGHT], "ollie": [KEY_SPACE],
		"trick_flip": [KEY_E], "trick_grab": [KEY_F], "trick_style": [KEY_R], "trick_spin": [KEY_Q],
		"trick_mod": [KEY_SHIFT], "trick_list": [KEY_TAB],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	# Gamepad: right trigger kicks, left trigger brakes, left stick steers, A ollies.
	_pad_axis("kick", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_pad_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_pad_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_pad_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	# A ollies, X flips, Y grabs, B style, RB spins, LB is Shift, Back shows the trick list.
	var pad_buttons := {
		"ollie": JOY_BUTTON_A, "trick_flip": JOY_BUTTON_X, "trick_grab": JOY_BUTTON_Y,
		"trick_style": JOY_BUTTON_B, "trick_spin": JOY_BUTTON_RIGHT_SHOULDER,
		"trick_mod": JOY_BUTTON_LEFT_SHOULDER, "trick_list": JOY_BUTTON_BACK,
	}
	for action in pad_buttons:
		var button := InputEventJoypadButton.new()
		button.button_index = pad_buttons[action]
		InputMap.action_add_event(action, button)


func _pad_axis(action: String, axis: JoyAxis, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	InputMap.action_add_event(action, motion)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_opts[parts[0]] = parts[1] if parts.size() > 1 else true


func _run_cli() -> void:
	if _opts.has("solo"):
		start_solo()
	elif _opts.has("host"):
		start_host()
		for i in int(_opts.get("bots", 0)):
			add_bot()
	elif _opts.has("join"):
		start_join(str(_opts["join"]))
