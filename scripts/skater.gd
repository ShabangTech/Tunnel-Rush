extends CharacterBody3D
## One racer on a skateboard. The peer that owns it simulates it (bots belong to the
## host); every other peer sees a synced copy.
##
## Kick rhythm: holding kick makes the 1st kick-off start you, the 2nd follow, and the
## 3rd and every kick after hold top speed. Wet floors keep your speed, dry floors drag,
## downhills speed you up without kicking. Hit a wall head-on and you lose most of your
## speed; hit a crate hard enough and it smashes.

const TOP_SPEED := 8.0
const KICK_TIERS: Array[float] = [0.38, 0.72, 1.0]     # share of top speed each kick reaches
const KICK_TIMES: Array[float] = [1.1, 0.63, 0.63]     # seconds per kick
const PUSH_SHARE := 0.6                                # the push is done by 60% of the kick
const SLOPE_GAIN := 0.5
const OVERSPEED := 1.35
const BRAKE := 8.0
const TURN_RATE := 2.4
const OLLIE_VELOCITY := 5.2
const GRAVITY := 14.0
const CRASH_KEEP := 0.35          # share of speed kept after a head-on crash
const CRATE_SMASH_SPEED := 6.0
const FALL_LIMIT := -14.0
const GRID_X: Array[float] = [-2.4, -0.8, 0.8, 2.4]
const Level := preload("res://scripts/level.gd")

var peer_id := 1
var is_bot := false
var autopilot := false
var slot := 0
var racer_name := "Skater"
var color := Color.WHITE

var speed := 0.0
var heading := 0.0
var kicks := 0
var finished := false
var finish_time := 0.0
var respawns := 0

var _kicking := false
var _kick_t := 0.0
var _kick_len := 0.0
var _kick_from := 0.0
var _kick_to := 0.0
var _kick_idle := 0.0
var _floor_drag := 1.2
var _bot_lane := 0.0
var _crash_cooldown := 0.0


## Called by the spawner on every peer with the same data.
func setup(data: Dictionary) -> void:
	peer_id = data.id
	is_bot = data.bot
	slot = data.slot
	racer_name = data.name
	color = data.color
	name = "P%d" % peer_id
	_bot_lane = GRID_X[slot % GRID_X.size()]
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(35.0)
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


static func grid_position(grid_slot: int) -> Vector3:
	return Vector3(GRID_X[grid_slot % GRID_X.size()], 0.2, -3.0 - (grid_slot % 2) * 1.5)


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var race = _race()
	if race == null or not (race.is_racing() or finished):
		return                                              # frozen on the grid
	var cmd := _bot_input() if autopilot else _player_input()
	if finished:
		cmd = {"kick": false, "brake": speed > 3.0, "steer": 0.0, "ollie": false}

	heading -= cmd.steer * TURN_RATE * delta
	rotation = Vector3(0.0, heading, 0.0)
	var fwd := forward()

	if is_on_floor():
		_update_kick(cmd.kick, delta)
		var downhill := Vector3.DOWN.slide(get_floor_normal()).dot(fwd) * GRAVITY
		if absf(downhill) > 0.05:
			speed += downhill * SLOPE_GAIN * delta
		if not _kicking:
			speed -= _floor_drag * delta
		if cmd.brake:
			speed -= BRAKE * delta
			_kicking = false
		if speed > TOP_SPEED and downhill <= 0.05:
			speed = move_toward(speed, TOP_SPEED, 2.0 * delta)
		speed = clampf(speed, 0.0, TOP_SPEED * OVERSPEED)
		velocity.y = OLLIE_VELOCITY if cmd.ollie else 0.0
	else:
		velocity.y -= GRAVITY * delta

	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	move_and_slide()
	_after_move(fwd, delta)

	if global_position.y < FALL_LIMIT:
		_respawn()


func _after_move(fwd: Vector3, delta: float) -> void:
	_crash_cooldown = maxf(_crash_cooldown - delta, 0.0)
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var n := hit.get_normal()
		var collider := hit.get_collider()
		if n.y > 0.7:
			_floor_drag = Level.drag_of(collider)
			continue
		if absf(n.y) < 0.5 and n.dot(fwd) < -0.6 and speed > 2.0 and _crash_cooldown == 0.0:
			_crash_cooldown = 0.4
			if collider and collider.has_meta("crate") and speed >= CRATE_SMASH_SPEED:
				_level().rpc("break_crate", collider.get_meta("crate"))
				speed *= 0.75
			else:
				speed *= CRASH_KEEP
				kicks = 0
				_kicking = false


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
	}


## Simple racing line: hold a lane, swerve around crates, line up for the plank.
func _bot_input() -> Dictionary:
	var pos := global_position
	var target_x := _bot_lane
	if pos.z < -126.0 and pos.z > -148.0:
		target_x = 0.0
	else:
		var space := get_world_3d().direct_space_state
		var from := pos + Vector3(0, 0.6, 0)
		var query := PhysicsRayQueryParameters3D.create(from, from + forward() * 7.0)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit and hit.collider.has_meta("crate"):
			var crate_x: float = hit.collider.global_position.x
			_bot_lane = clampf(crate_x + (1.9 if pos.x >= crate_x else -1.9), -3.3, 3.3)
			target_x = _bot_lane
	var desired := atan2(-(target_x - pos.x), 6.0)
	return {
		"kick": true,
		"brake": false,
		"steer": clampf((heading - desired) * 3.0, -1.0, 1.0),
		"ollie": false,
	}


# --------------------------------------------------------------------- build

func _build() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.95
	add_child(shape)

	var body := CapsuleMesh.new()
	body.radius = 0.32
	body.height = 1.5
	_mesh(body, Vector3(0, 1.0, 0), _flat(color, 0.5))
	_mesh(_cube(Vector3(0.4, 0.14, 0.1)), Vector3(0, 1.45, -0.28), _flat(Color("101418"), 0.3))
	_mesh(_cube(Vector3(0.26, 0.05, 0.85)), Vector3(0, 0.12, 0), _flat(Color("2b2b2b"), 0.7))
	for z in [-0.3, 0.3]:
		_mesh(_cube(Vector3(0.3, 0.08, 0.08)), Vector3(0, 0.05, z), _flat(color.lightened(0.4), 0.6))

	var label := Label3D.new()
	label.text = racer_name
	label.position.y = 2.15
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 10
	label.modulate = color.lightened(0.3)
	add_child(label)

	# Position and facing are sent from the owner to everyone else.
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for prop in [":position", ":rotation", ":speed"]:
		var path := NodePath("." + prop)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	add_child(sync)


func _mesh(mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	add_child(instance)


static func _cube(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _flat(c: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = roughness
	return mat


func _race():
	return get_node_or_null("/root/Main/Race")


func _level():
	return get_node_or_null("/root/Main/Level")
