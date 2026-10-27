extends CharacterBody3D
## One racer: a Big Head animal on a skateboard. The peer that owns it simulates it
## (bots belong to the host); every other peer sees a synced copy and animates it.
##
## Kick rhythm: holding kick makes the 1st kick-off start you, the 2nd follow, and the
## 3rd and every kick after hold top speed. Wet floors keep your speed, dry floors drag,
## downhills speed you up without kicking. Hit a wall head-on and you lose most of your
## speed; hit a crate hard enough and it smashes.
##
## Freestyle: entering The Drop opens an 8-second window. Hit the kickers and pull
## tricks from the trick book (tricks.gd): 25 air tricks plus spins from 180 to 1080.
## Land clean to bank points; land mid-trick and you bail. When the window closes your
## points turn into a speed boost. Land an odd number of half spins and you ride fakie.
##
## Hazards: zombies climb out of the ground (they block you like a wall), and bats
## swoop low enough to spook you.
##
## Tokens (handed out by the host): every 5 gold tokens fire a Turbo; power tokens
## give a Turbo (burst of speed), a Shield (shrugs off the next zombie, bat or crash)
## or Mega Air (bigger ollies, so bigger tricks).

signal trick_event(text: String, kind: String)   # local feedback for the HUD

const Level := preload("res://scripts/level.gd")
const Rider := preload("res://scripts/rider.gd")
const Tricks := preload("res://scripts/tricks.gd")

const TOP_SPEED := 8.0
const KICK_TIERS: Array[float] = [0.38, 0.72, 1.0]     # share of top speed each kick reaches
const KICK_TIMES: Array[float] = [1.1, 0.63, 0.63]     # seconds per kick
const PUSH_SHARE := 0.6                                # the push is done by 60% of the kick
const SLOPE_GAIN := 0.5
const OVERSPEED := 1.35
const MAX_BOOST := 3.0
const BRAKE := 8.0
const TURN_RATE := 2.4
const OLLIE_VELOCITY := 5.2
const GRAVITY := 14.0
const CRASH_KEEP := 0.35          # share of speed kept after a head-on crash
const CRATE_SMASH_SPEED := 6.0
const GRID_X: Array[float] = [-2.4, -0.8, 0.8, 2.4]

const SPIN_RATE := TAU * 2.6       # radians per second while spinning (a 1080 needs big air)
const LAND_TOLERANCE := 0.5       # radians short of a half turn still counted as clean
const AIR_POINTS_PER_SECOND := 60.0
const POINTS_PER_BOOST := 150.0   # freestyle points per m/s of boost
const GOLD_FOR_TURBO := 5
const TURBO_TIME := 2.5
const TURBO_SPEED := TOP_SPEED * OVERSPEED + 2.5
const TURBO_ACCEL := 12.0
const SHIELD_TIME := 10.0
const MEGA_AIR_TIME := 8.0
const MEGA_AIR_FACTOR := 1.45

var peer_id := 1
var is_bot := false
var autopilot := false
var slot := 0
var racer_name := "Skater"
var color := Color.WHITE
var animal := "Panda"

# Synced to every peer (drives the animation).
var speed := 0.0
var kick_phase := 0.0
var lean := 0.0
var spin := 0.0                   # body + board yaw (a multiple of PI on the ground)
var board_roll := 0.0
var board_yaw := 0.0
var board_pitch := 0.0
var pose := 0                     # grab / style pose id (see rider.gd)
var pose_t := 0.0                 # 0..1 progress of a style trick
var airborne := false
var bail_t := 0.0
var turbo_on := false
var shield_on := false
var mega_air_on := false

# Tokens (owner only).
var gold := 0
var gold_total := 0
var turbo_left := 0.0
var shield_left := 0.0
var mega_air_left := 0.0

var heading := 0.0
var kicks := 0
var finished := false
var finish_time := 0.0
var respawns := 0

# Freestyle (owner only).
var freestyle_active := false
var freestyle_left := 0.0
var freestyle_score := 0.0
var _freestyle_done := false

var _rider: Node3D
var _kicking := false
var _kick_t := 0.0
var _kick_len := 0.0
var _kick_from := 0.0
var _kick_to := 0.0
var _kick_idle := 0.0
var _floor_drag := Level.DRAG_DRY
var _bot_lane := 0.0
var _crash_cooldown := 0.0
var _air_time := 0.0
var _spinning := false
var _spin_this_jump := 0.0        # radians spun since take-off
var _spin_target := 0.0           # where the spin stops (next half turn after Q is let go)
var _flip: Array = []             # the flip trick in progress (a trick book entry)
var _flip_t := 0.0
var _style: Array = []
var _style_t := 0.0
var _grab: Array = []
var _grab_time := 0.0
var _jump_tricks: Array[String] = []
var _jump_points := 0.0
var _hazard_cooldown := 0.0
var _crate_push := 0.0            # seconds spent shoving a crate at low speed
var _stuck_check_z := 0.0
var _stuck_timer := 0.0


## Called by the spawner on every peer with the same data.
func setup(data: Dictionary) -> void:
	peer_id = data.id
	is_bot = data.bot
	slot = data.slot
	racer_name = data.name
	color = data.color
	animal = data.get("animal", "Panda")
	name = "P%d" % peer_id
	_bot_lane = GRID_X[slot % GRID_X.size()]
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(40.0)
	_build()
	set_multiplayer_authority(1 if is_bot else peer_id)
	autopilot = is_bot
	reset_to_grid()


func reset_to_grid() -> void:
	position = grid_position(slot)
	heading = 0.0
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	speed = 0.0
	kicks = 0
	_kicking = false
	finished = false
	finish_time = 0.0
	respawns = 0
	freestyle_active = false
	freestyle_score = 0.0
	_freestyle_done = false
	_clear_tricks()
	spin = 0.0
	gold = 0
	gold_total = 0
	turbo_left = 0.0
	shield_left = 0.0
	mega_air_left = 0.0
	turbo_on = false
	shield_on = false
	mega_air_on = false


static func grid_position(grid_slot: int) -> Vector3:
	return Vector3(GRID_X[grid_slot % GRID_X.size()], 0.2, -3.0 - (grid_slot % 2) * 1.5)


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func _process(delta: float) -> void:
	if _rider:
		_rider.animate(delta, {
			"kick_phase": kick_phase, "lean": lean, "spin": spin, "roll": board_roll,
			"yaw": board_yaw, "pitch": board_pitch, "pose": pose, "pose_t": pose_t,
			"air": airborne, "bail": bail_t,
			"turbo": turbo_on, "shield": shield_on, "mega_air": mega_air_on,
		})


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var race = _race()
	if race == null or not (race.is_racing() or finished):
		return                                              # frozen on the grid
	var cmd := _bot_input() if autopilot else _player_input()
	if finished or bail_t > 0.0:
		cmd = _idle_cmd()
		cmd.brake = finished and speed > 3.0

	heading -= cmd.steer * TURN_RATE * delta
	rotation = Vector3(0.0, heading, 0.0)
	var fwd := forward()
	lean = lerpf(lean, -cmd.steer * 0.32 * clampf(speed / TOP_SPEED, 0.0, 1.0), clampf(delta * 6.0, 0.0, 1.0))
	bail_t = maxf(bail_t - delta, 0.0)
	_update_powers(delta)

	if is_on_floor():
		_update_kick(cmd.kick, delta)
		var n := get_floor_normal()
		var downhill := Vector3.DOWN.slide(n).dot(fwd) * GRAVITY
		if absf(downhill) > 0.05:
			speed += downhill * SLOPE_GAIN * delta
		if turbo_on:
			speed = move_toward(speed, TURBO_SPEED, TURBO_ACCEL * delta)
		elif not _kicking:
			speed -= _floor_drag * delta
		if cmd.brake:
			speed -= BRAKE * delta
			_kicking = false
		if speed > TOP_SPEED and downhill <= 0.05 and not turbo_on:
			speed = move_toward(speed, TOP_SPEED, 1.0 * delta)          # extra speed bleeds off
		speed = clampf(speed, 0.0, TOP_SPEED * OVERSPEED + MAX_BOOST)
		# Ride along the surface, so a kicker throws you up and a slope carries you down.
		var along := (fwd * speed).slide(n)
		velocity = along.normalized() * speed if along.length() > 0.001 else Vector3.ZERO
		if cmd.ollie:
			velocity.y += OLLIE_VELOCITY * (MEGA_AIR_FACTOR if mega_air_on else 1.0)
	else:
		velocity.x = fwd.x * speed
		velocity.z = fwd.z * speed
		velocity.y -= GRAVITY * delta
		_update_tricks(cmd, delta)

	move_and_slide()
	_after_move(fwd, delta)
	kick_phase = clampf(_kick_t / _kick_len, 0.0, 1.0) if _kicking else 0.0
	_update_freestyle(delta)

	if global_position.y < Level.FALL_LIMIT:
		_respawn()


func _after_move(fwd: Vector3, delta: float) -> void:
	_crash_cooldown = maxf(_crash_cooldown - delta, 0.0)
	var pushing_crate := false
	_hazard_cooldown = maxf(_hazard_cooldown - delta, 0.0)
	if _hazard_cooldown == 0.0 and _level().bat_hits(global_position + Vector3.UP * 1.6):
		_hazard_cooldown = 1.5
		if not _use_shield("BATS"):
			speed *= 0.85
			trick_event.emit("BATS!", "bail")
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var n := hit.get_normal()
		var collider := hit.get_collider()
		if n.y > 0.7:
			_floor_drag = Level.drag_of(collider)
			continue
		if collider and collider.has_meta("zombie"):
			if _hazard_cooldown == 0.0 and _use_shield("ZOMBIE"):
				_hazard_cooldown = 1.0
			elif _hazard_cooldown == 0.0:
				_hazard_cooldown = 1.0
				speed *= 0.6
				kicks = 0
				_kicking = false
				bail_t = 0.5
				trick_event.emit("ZOMBIE!", "bail")
			continue
		# Shoving a crate slowly: it gives way after a moment, so nobody gets wedged.
		if collider and collider.has_meta("crate") and absf(n.y) < 0.5:
			pushing_crate = true
			if _crate_push > 0.6:
				_level().rpc("break_crate", collider.get_meta("crate"))
				_crate_push = 0.0
				trick_event.emit("SMASH!", "info")
				continue
		if absf(n.y) < 0.5 and n.dot(fwd) < -0.6 and speed > 2.0 and _crash_cooldown == 0.0:
			_crash_cooldown = 0.4
			if collider and collider.has_meta("crate") and speed >= CRATE_SMASH_SPEED:
				_level().rpc("break_crate", collider.get_meta("crate"))
				speed *= 0.75
				trick_event.emit("SMASH!", "info")
			elif not _use_shield("WALL"):
				speed *= CRASH_KEEP
				kicks = 0
				_kicking = false

	_crate_push = _crate_push + delta if pushing_crate else 0.0
	var on_floor := is_on_floor()
	if on_floor and airborne:
		_land()
	airborne = not on_floor
	if airborne:
		_air_time += delta


func _respawn() -> void:
	var cp: Vector3 = _level().checkpoint_for(global_position)
	global_position = cp + Vector3(GRID_X[slot % GRID_X.size()] * 0.5, 0, 0)
	heading = 0.0
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	speed = 0.0
	kicks = 0
	_kicking = false
	respawns += 1
	_clear_tricks()
	spin = 0.0
	airborne = false
	trick_event.emit("SPLASH! Back to the checkpoint", "bail")


# -------------------------------------------------------------- tokens / powers

## Sent by the host to whoever drives this racer when it touches a token.
@rpc("any_peer", "call_local", "reliable")
func grant_token(kind: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1 and not (sender == 0 and multiplayer.is_server()):
		return                                             # only the host hands out tokens
	match kind:
		Level.Token.GOLD:
			gold += 1
			gold_total += 1
			if gold >= GOLD_FOR_TURBO:
				gold = 0
				turbo_left = TURBO_TIME
				trick_event.emit("TOKEN TURBO!", "boost")
			else:
				trick_event.emit("+1 TOKEN  (%d/%d)" % [gold, GOLD_FOR_TURBO], "token")
		Level.Token.TURBO:
			turbo_left = TURBO_TIME
			trick_event.emit("TURBO!", "boost")
		Level.Token.SHIELD:
			shield_left = SHIELD_TIME
			trick_event.emit("SHIELD UP!", "shield")
		Level.Token.MEGA_AIR:
			mega_air_left = MEGA_AIR_TIME
			trick_event.emit("MEGA AIR!", "freestyle")


func _update_powers(delta: float) -> void:
	turbo_left = maxf(turbo_left - delta, 0.0)
	shield_left = maxf(shield_left - delta, 0.0)
	mega_air_left = maxf(mega_air_left - delta, 0.0)
	turbo_on = turbo_left > 0.0
	shield_on = shield_left > 0.0
	mega_air_on = mega_air_left > 0.0


## Spends the shield on a hit, if there is one. Returns true when it saved you.
func _use_shield(what: String) -> bool:
	if shield_left <= 0.0:
		return false
	shield_left = 0.0
	shield_on = false
	trick_event.emit("SHIELD BLOCKED %s!" % what, "shield")
	return true


# ------------------------------------------------------------------- tricks

func _update_tricks(cmd: Dictionary, delta: float) -> void:
	# Start tricks (one flip, and either a grab or a style trick, at a time).
	if cmd.flip and _flip.is_empty():
		_flip = Tricks.lookup("flip", cmd.shift, cmd.dir)
		_flip_t = 0.0
	if cmd.style and _style.is_empty() and _grab.is_empty():
		_style = Tricks.lookup("style", cmd.shift, cmd.dir)
		_style_t = 0.0
	if cmd.grab_pressed and _grab.is_empty() and _style.is_empty():
		_grab = Tricks.lookup("grab", cmd.shift, cmd.dir)
		_grab_time = 0.0

	# Flip: the board turns its whole turns over the trick's time.
	if not _flip.is_empty():
		_flip_t += delta
		var k := clampf(_flip_t / _flip[2], 0.0, 1.0)
		board_roll = TAU * _flip[3] * k
		board_yaw = TAU * _flip[4] * k
		board_pitch = TAU * _flip[5] * k
		if k >= 1.0:
			_bank_trick(_flip[0], _flip[1])
			_flip = []
			board_roll = 0.0
			board_pitch = 0.0
			board_yaw = 0.0

	# Style trick: a timed pose.
	if not _style.is_empty():
		_style_t += delta
		pose = _style[6]
		pose_t = clampf(_style_t / _style[2], 0.0, 1.0)
		if pose_t >= 1.0:
			_bank_trick(_style[0], _style[1])
			_style = []
			pose = 0
			pose_t = 0.0

	# Grab: held for points per second.
	if not _grab.is_empty():
		if cmd.grab_held:
			_grab_time += delta
			pose = _grab[6]
		else:
			_end_grab()

	# Spin: keeps going while held, then finishes to the next half turn.
	if cmd.spin_held:
		_spinning = true
		_spin_target = INF
	elif _spinning and _spin_target == INF:
		_spin_target = ceilf((_spin_this_jump + 0.01) / PI) * PI
	if _spinning:
		var limit := float(Tricks.MAX_HALF_TURNS) * PI
		var target := minf(_spin_target, limit)
		var step := minf(SPIN_RATE * delta, target - _spin_this_jump)
		_spin_this_jump += step
		spin -= step
		if _spin_this_jump >= target - 0.001:
			_spinning = false


func _end_grab() -> void:
	if _grab.is_empty():
		return
	if _grab_time >= _grab[2]:
		_bank_trick(_grab[0], _grab[1] * _grab_time)
	_grab = []
	pose = 0


func _bank_trick(trick_name: String, points: float) -> void:
	_jump_tricks.append(trick_name)
	_jump_points += points


func _land() -> void:
	_end_grab()
	var spin_short := 0.0
	if _spin_this_jump > 0.3:
		var nearest := roundf(_spin_this_jump / PI) * PI
		spin_short = absf(_spin_this_jump - nearest)
	var unfinished: bool = (not _flip.is_empty() and _flip_t < _flip[2] * 0.85) \
		or (not _style.is_empty() and _style_t < _style[2] * 0.8) or spin_short > LAND_TOLERANCE
	if unfinished:
		speed *= 0.4
		bail_t = 0.9
		kicks = 0
		trick_event.emit("BAIL!", "bail")
		spin = roundf(spin / PI) * PI
		_clear_tricks()
		return

	if not _flip.is_empty():
		_bank_trick(_flip[0], _flip[1])
	if not _style.is_empty():
		_bank_trick(_style[0], _style[1])
	var half_turns := mini(roundi(_spin_this_jump / PI), Tricks.MAX_HALF_TURNS)
	if half_turns > 0:
		_bank_trick(Tricks.spin_name(half_turns), Tricks.SPIN_POINTS[half_turns])
	spin = roundf(spin / PI) * PI                                     # fakie if odd half turns
	if not _jump_tricks.is_empty():
		var points := (_jump_points + _air_time * AIR_POINTS_PER_SECOND) * (1.0 + 0.5 * (_jump_tricks.size() - 1))
		var label := " + ".join(_jump_tricks)
		if freestyle_active:
			freestyle_score += points
			trick_event.emit("%s  +%d" % [label, roundi(points)], "trick")
		else:
			trick_event.emit(label, "trick")
	_clear_tricks()


func _clear_tricks() -> void:
	_spinning = false
	_spin_this_jump = 0.0
	_spin_target = 0.0
	_flip = []
	_style = []
	_grab = []
	_flip_t = 0.0
	_style_t = 0.0
	_grab_time = 0.0
	board_roll = 0.0
	board_yaw = 0.0
	board_pitch = 0.0
	pose = 0
	pose_t = 0.0
	_air_time = 0.0
	_jump_points = 0.0
	_jump_tricks.clear()


func _update_freestyle(delta: float) -> void:
	var z := global_position.z
	if not freestyle_active and not _freestyle_done and Level.in_freestyle_zone(z):
		freestyle_active = true
		freestyle_left = Level.FREESTYLE_SECONDS
		freestyle_score = 0.0
		trick_event.emit("FREESTYLE!", "freestyle")
	if freestyle_active:
		freestyle_left -= delta
		if freestyle_left <= 0.0 or z <= Level.SLOPE_END:
			freestyle_active = false
			_freestyle_done = true
			var boost := minf(freestyle_score / POINTS_PER_BOOST, MAX_BOOST)
			speed += boost
			trick_event.emit("FREESTYLE %d   BOOST +%d km/h" % [roundi(freestyle_score), roundi(boost * 3.6)], "boost")


# --------------------------------------------------------------- kick rhythm

func _update_kick(holding: bool, delta: float) -> void:
	if _kicking:
		_kick_t += delta
		var pushed := lerpf(_kick_from, _kick_to, clampf(_kick_t / (_kick_len * PUSH_SHARE), 0.0, 1.0))
		speed = maxf(speed, pushed)
		if _kick_t >= _kick_len:
			_kicking = false
		return
	if holding:
		_kick_idle = 0.0
		if kicks == 0:
			kicks = _kicks_for_speed(speed)
		var target := KICK_TIERS[mini(kicks, KICK_TIERS.size() - 1)] * TOP_SPEED
		if speed < target * 0.95:
			_kicking = true
			_kick_t = 0.0
			_kick_len = KICK_TIMES[mini(kicks, KICK_TIMES.size() - 1)]
			_kick_from = speed
			_kick_to = target
			kicks += 1
	else:
		_kick_idle += delta
		if speed < 0.5 or _kick_idle > 1.5:
			kicks = 0


## A kick after a downhill or an ollie maintains speed instead of starting over.
static func _kicks_for_speed(s: float) -> int:
	var f := s / TOP_SPEED
	if f >= KICK_TIERS[1] * 0.95:
		return 2
	if f >= KICK_TIERS[0] * 0.95:
		return 1
	return 0


# --------------------------------------------------------------------- input

func _player_input() -> Dictionary:
	return {
		"kick": Input.is_action_pressed("kick"),
		"brake": Input.is_action_pressed("brake"),
		"steer": Input.get_axis("steer_left", "steer_right"),
		"ollie": Input.is_action_just_pressed("ollie"),
		"flip": Input.is_action_just_pressed("trick_flip"),
		"style": Input.is_action_just_pressed("trick_style"),
		"grab_pressed": Input.is_action_just_pressed("trick_grab"),
		"grab_held": Input.is_action_pressed("trick_grab"),
		"spin_held": Input.is_action_pressed("trick_spin"),
		"shift": Input.is_action_pressed("trick_mod"),
		"dir": _held_direction(),
	}


## The direction held when a trick button is pressed picks the variation.
static func _held_direction() -> String:
	if Input.is_action_pressed("kick"):
		return "W"
	if Input.is_action_pressed("brake"):
		return "S"
	if Input.is_action_pressed("steer_left"):
		return "A"
	if Input.is_action_pressed("steer_right"):
		return "D"
	return ""


static func _idle_cmd() -> Dictionary:
	return {"kick": false, "brake": false, "steer": 0.0, "ollie": false, "flip": false,
		"style": false, "grab_pressed": false, "grab_held": false, "spin_held": false,
		"shift": false, "dir": ""}


## Racing line: hold a lane, swerve around crates, hit the kickers with a trick,
## and line up for the plank.
func _bot_input() -> Dictionary:
	var pos := global_position
	var target_x := _bot_lane
	var cmd := _idle_cmd()
	cmd.kick = true

	# Unstick: if a bot hasn't made progress for a second, swap to the other side.
	_stuck_timer += get_physics_process_delta_time()
	if _stuck_timer > 1.0:
		if pos.z > _stuck_check_z - 1.0:
			_bot_lane = -2.4 if pos.x > 0.0 else 2.4
		_stuck_check_z = pos.z
		_stuck_timer = 0.0

	if Level.in_freestyle_zone(pos.z + 3.0):
		target_x = clampf(_bot_lane, -1.2, 1.2)                     # stay on the kickers
		for kz in Level.KICKER_Z:
			var lip := kz - Level.KICKER_LENGTH
			if is_on_floor() and pos.z < lip + 0.7 and pos.z > lip - 0.2:
				cmd.ollie = true
		# Each bot has a signature move, with a different variation on each kicker.
		if airborne and velocity.y > 1.5:
			var variation: String = ["", "W", "A", "S", "D"][(int(-pos.z) / 24 + slot) % 5]
			cmd.dir = variation
			cmd.shift = slot == 3
			match slot % 4:
				0, 3:
					cmd.flip = _air_time < 0.1
				1:
					cmd.spin_held = _air_time < 0.25
				2:
					cmd.grab_pressed = _air_time < 0.1
					cmd.grab_held = _air_time < 0.7
	elif pos.z < Level.GAP_START + 14.0 and pos.z > Level.GAP_END - 2.0:
		target_x = 0.0
	else:
		var space := get_world_3d().direct_space_state
		var from := pos + Vector3(0, 0.6, 0)
		var query := PhysicsRayQueryParameters3D.create(from, from + forward() * 7.0)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit and (hit.collider.has_meta("crate") or hit.collider.has_meta("zombie")):
			var crate_x: float = hit.collider.global_position.x
			_bot_lane = clampf(crate_x + (1.9 if pos.x >= crate_x else -1.9), -3.3, 3.3)
			target_x = _bot_lane
	var desired := atan2(-(target_x - pos.x), 6.0)
	cmd.steer = clampf((heading - desired) * 3.0, -1.0, 1.0)
	return cmd


# --------------------------------------------------------------------- build

func _build() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.95
	add_child(shape)

	_rider = Rider.new()
	_rider.name = "Rider"
	add_child(_rider)
	_rider.build(color, animal)

	var label := Label3D.new()
	label.text = racer_name
	label.position.y = _rider.head_top + 0.45
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 10
	label.modulate = color.lightened(0.3)
	add_child(label)

	# The owner sends position, facing and animation state to everyone else.
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for prop in [":position", ":rotation", ":speed", ":kick_phase", ":lean", ":spin",
			":board_roll", ":board_yaw", ":board_pitch", ":pose", ":pose_t", ":airborne", ":bail_t",
			":turbo_on", ":shield_on", ":mega_air_on"]:
		var path := NodePath("." + prop)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	add_child(sync)


func _race():
	return get_node_or_null("/root/Main/Race")


func _level():
	return get_node_or_null("/root/Main/Level")
