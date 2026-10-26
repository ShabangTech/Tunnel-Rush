extends CanvasLayer
## In-race display: speed, kick rhythm, race clock, live position, countdown,
## finish announcements and the results board.

const Race := preload("res://scripts/race.gd")

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
	_hint.text = "W kick   A/D steer   S brake   Space ollie   Esc menu"
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
	if me:
		_speed.text = "%d km/h" % roundi(me.speed * 3.6)
		var pips := ""
		for i in 3:
			pips += "● " if i < mini(me.kicks, 3) else "○ "
		_kicks.text = "KICK  " + pips
		_place.text = _place_text(me)
	_clock.text = Race.format_time(race.race_time)
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
