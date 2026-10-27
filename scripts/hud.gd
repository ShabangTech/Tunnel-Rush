extends CanvasLayer
## In-race display: speed, kick rhythm, race clock, live position, countdown,
## finish announcements, the freestyle timer and score, trick callouts, the trick
## list (Tab) and the results board.

const Race := preload("res://scripts/race.gd")
const Tricks := preload("res://scripts/tricks.gd")
const CALLOUT_COLORS := {
	"trick": Color("7cff6b"), "bail": Color("ff5a36"), "freestyle": Color("d38cff"),
	"boost": Color("ffd23f"), "info": Color("e8e2d4"), "token": Color("ffcf3a"),
	"shield": Color("35d0ff"),
}

var main
var _speed: Label
var _kicks: Label
var _clock: Label
var _place: Label
var _center: Label
var _feed: Label
var _results: Label
var _hint: Label
var _center_hold := 0.0
var _freestyle: Label
var _callout: Label
var _callout_hold := 0.0
var _trick_list: Label
var _listening_to: Node
var _tokens: Label
var _powers: Label


func _ready() -> void:
	_speed = _label(Vector2(24, 620), 34, HORIZONTAL_ALIGNMENT_LEFT)
	_kicks = _label(Vector2(24, 664), 22, HORIZONTAL_ALIGNMENT_LEFT)
	_clock = _label(Vector2(1056, 20), 34, HORIZONTAL_ALIGNMENT_RIGHT)
	_place = _label(Vector2(1056, 64), 26, HORIZONTAL_ALIGNMENT_RIGHT)
	_center = _label(Vector2(340, 250), 96, HORIZONTAL_ALIGNMENT_CENTER)
	_center.size = Vector2(600, 140)
	_feed = _label(Vector2(24, 20), 20, HORIZONTAL_ALIGNMENT_LEFT)
	_results = _label(Vector2(390, 170), 28, HORIZONTAL_ALIGNMENT_LEFT)
	_results.size = Vector2(500, 400)
	_hint = _label(Vector2(330, 680), 16, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.size = Vector2(620, 30)
	_hint.text = "W kick  A/D steer  S brake  Space ollie  |  In the air: E flip  F grab  R style  Q spin  (+W/A/S/D, Shift)  |  Tab tricks"
	_hint.position = Vector2(140, 690)
	_hint.size = Vector2(1000, 24)
	_freestyle = _label(Vector2(390, 96), 30, HORIZONTAL_ALIGNMENT_CENTER)
	_freestyle.size = Vector2(500, 40)
	_freestyle.modulate = Color("d38cff")
	_callout = _label(Vector2(240, 400), 34, HORIZONTAL_ALIGNMENT_CENTER)
	_callout.size = Vector2(800, 50)
	_trick_list = _label(Vector2(24, 110), 16, HORIZONTAL_ALIGNMENT_LEFT)
	_trick_list.size = Vector2(360, 560)
	_trick_list.text = "TRICK BOOK (in the air)\n\n" + "\n".join(Tricks.trick_list())
	_trick_list.visible = false
	_tokens = _label(Vector2(24, 584), 22, HORIZONTAL_ALIGNMENT_LEFT)
	_tokens.size = Vector2(320, 30)
	_tokens.modulate = Color("ffcf3a")
	_powers = _label(Vector2(856, 108), 22, HORIZONTAL_ALIGNMENT_RIGHT)
	_powers.size = Vector2(400, 100)
	_hint.modulate = Color(1, 1, 1, 0.6)
	main.race.racer_finished.connect(_on_racer_finished)
	main.race.results_ready.connect(_on_results)
	main.race.state_changed.connect(_on_state_changed)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	var race = main.race
	var me = main.local_skater()
	_trick_list.visible = Input.is_action_pressed("trick_list")
	if me and me != _listening_to:
		me.trick_event.connect(_on_trick_event)
		_listening_to = me
	if me:
		_freestyle.text = "FREESTYLE  %.1fs   %d pts" % [maxf(me.freestyle_left, 0.0), roundi(me.freestyle_score)] if me.freestyle_active else ""
		_speed.text = "%d km/h" % roundi(me.speed * 3.6)
		var pips := ""
		for i in 3:
			pips += "● " if i < mini(me.kicks, 3) else "○ "
		_kicks.text = "KICK  " + pips
		_place.text = _place_text(me)
		var meter := ""
		for i in me.GOLD_FOR_TURBO:
			meter += "◆" if i < me.gold else "◇"
		_tokens.text = "TOKENS %s  (%d)" % [meter, me.gold_total]
		var active := PackedStringArray()
		if me.turbo_on:
			active.append("TURBO %.1f" % me.turbo_left)
		if me.shield_on:
			active.append("SHIELD %.0f" % me.shield_left)
		if me.mega_air_on:
			active.append("MEGA AIR %.0f" % me.mega_air_left)
		_powers.text = "\n".join(active)
	_clock.text = Race.format_time(race.race_time)
	if _callout_hold > 0.0:
		_callout_hold -= delta
		_callout.modulate.a = clampf(_callout_hold * 2.0, 0.0, 1.0)
	if race.state == Race.State.COUNTDOWN:
		_center.text = str(ceili(race.countdown))
	elif _center_hold > 0.0:
		_center_hold -= delta
		if _center_hold <= 0.0:
			_center.text = ""


func _place_text(me) -> String:
	var field: Array = main.players.get_children()
	var ahead := 0
	for other in field:
		if other == me:
			continue
		if other.finished and not me.finished:
			ahead += 1
		elif other.finished == me.finished and other.global_position.z < me.global_position.z:
			ahead += 1
	return "POS %d / %d" % [ahead + 1, field.size()]


func _on_state_changed(state: int) -> void:
	if state == Race.State.COUNTDOWN:
		_results.text = ""
		_feed.text = ""
	elif state == Race.State.RACING:
		_center.text = "GO!"
		_center_hold = 1.0


func _on_trick_event(text: String, kind: String) -> void:
	_callout.text = text
	_callout.modulate = CALLOUT_COLORS.get(kind, Color.WHITE)
	_callout_hold = 2.0 if kind == "boost" else 1.4


func _on_racer_finished(racer_name: String, place: int, time: float) -> void:
	_feed.text += "%d. %s  %s\n" % [place, racer_name, Race.format_time(time)]
	var me = main.local_skater()
	if me and me.racer_name == racer_name:
		_center.text = ["1ST!", "2ND", "3RD", "4TH"][mini(place, 4) - 1]
		_center_hold = 2.5


func _on_results(results: Array) -> void:
	var text := "RESULTS\n\n"
	for i in results.size():
		text += "%d.  %-14s %s\n" % [i + 1, results[i].name, Race.format_time(results[i].time)]
	_results.text = text


func _label(pos: Vector2, font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = Vector2(200, 40)
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	add_child(label)
	return label
