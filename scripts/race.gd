extends Node
## Race flow. The host is the referee: it starts the countdown, decides who crossed
## the finish line and when, and announces the results to everyone.

signal state_changed(state: int)
signal racer_finished(racer_name: String, place: int, time: float)
signal results_ready(results: Array)

enum State { LOBBY, COUNTDOWN, RACING, RESULTS }

const COUNTDOWN_SECONDS := 3.0
const FINISH_GRACE := 15.0      # seconds the field gets after the winner crosses

const Level := preload("res://scripts/level.gd")

var main
var state := State.LOBBY
var countdown := 0.0
var race_time := 0.0
var results: Array = []         # [{name, time}] in finishing order
var _first_finish := -1.0


func is_racing() -> bool:
	return state == State.RACING


## Host only: start (or restart) a race with everyone currently on the grid.
func host_start() -> void:
	if not multiplayer.is_server() or state == State.COUNTDOWN or state == State.RACING:
		return
	_begin_countdown.rpc()


@rpc("authority", "call_local", "reliable")
func _begin_countdown() -> void:
	results.clear()
	_first_finish = -1.0
	race_time = 0.0
	countdown = COUNTDOWN_SECONDS
	main.level.reset_crates()
	main.level.reset_tokens()
	for skater in main.players.get_children():
		skater.finished = false
		if skater.is_multiplayer_authority():
			skater.reset_to_grid()
	_set_state(State.COUNTDOWN)


func _process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			countdown -= delta
			if countdown <= 0.0:
				_set_state(State.RACING)
		State.RACING:
			race_time += delta


func _physics_process(_delta: float) -> void:
	if state != State.RACING or not multiplayer.is_server():
		return
	var still_racing := 0
	for skater in main.players.get_children():
		if skater.finished:
			continue
		if skater.global_position.z <= Level.FINISH_Z:
			_mark_finished.rpc(skater.name, race_time)
		else:
			still_racing += 1
	var grace_over := _first_finish >= 0.0 and race_time - _first_finish > FINISH_GRACE
	if main.players.get_child_count() > 0 and (still_racing == 0 or grace_over):
		_show_results.rpc(_final_results())


@rpc("authority", "call_local", "reliable")
func _mark_finished(node_name: String, time: float) -> void:
	var skater = main.players.get_node_or_null(node_name)
	if skater == null or skater.finished:
		return
	skater.finished = true
	skater.finish_time = time
	results.append({"name": skater.racer_name, "time": time})
	if _first_finish < 0.0:
		_first_finish = time
	racer_finished.emit(skater.racer_name, results.size(), time)


func _final_results() -> Array:
	var out := results.duplicate(true)
	for skater in main.players.get_children():
		if not skater.finished:
			out.append({"name": skater.racer_name, "time": -1.0})
	return out


@rpc("authority", "call_local", "reliable")
func _show_results(final: Array) -> void:
	results = final
	_set_state(State.RESULTS)
	results_ready.emit(final)


func _set_state(new_state: int) -> void:
	state = new_state
	state_changed.emit(new_state)


static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "DNF"
	var minutes := int(seconds) / 60
	return "%d:%05.2f" % [minutes, seconds - minutes * 60]
