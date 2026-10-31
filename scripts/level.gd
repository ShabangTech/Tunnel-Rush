extends Node3D
## The race course, built in code from greybox shapes. Every peer builds the same one.
##
##   START (dry) -> wet straight -> THE DROP: an 8-second freestyle slope with three
##   kickers -> crate field (dry) -> plank over the pit -> DOWN TUNNEL 1 -> THE BAY BRIDGE
##   (open air over blue water) -> DOWN TUNNEL 2 -> FINISH PLAZA
##
## Everything after the pit is built by city.gd.
##
## Wet floors keep your speed, dry floors drag. Zombies claw up out of the floor and
## shamble into the lane (they block you), and bats swoop down at head height.
##
## Tokens: gold tokens fill a meter (every 5 fires a Turbo), and rarer power tokens
## give a Turbo, a Shield or Mega Air straight away. The host decides who grabbed a
## token and tells everyone, so a token can only be taken once.
##
## Hazards move on the shared race clock, so every peer sees them in the same place
## without sending any network traffic.

const City := preload("res://scripts/city.gd")

const LANE_HALF_WIDTH := 4.0
const DRAG_DRY := 1.2            # m/s lost per second while coasting
const DRAG_WET := 0.3

# The freestyle slope ("The Drop").
const SLOPE_START := -55.0
const SLOPE_END := -140.0
const SLOPE_DROP := 11.0
const LOW_TOP := -SLOPE_DROP     # floor height after the slope
const FREESTYLE_SECONDS := 8.0
const KICKER_Z: Array[float] = [-64.0, -84.0, -104.0]   # where each kicker starts
const KICKER_LENGTH := 3.2
const KICKER_RISE := 1.4

const GAP_START := -190.0
const GAP_END := -196.0

# After the pit (city.gd): two wet down tunnels that build and hold top speed, with an
# open-air bridge over the bay between them, then the finish plaza.
const TUN1_START := -206.0
const TUN1_END := -266.0
const H_TUN1 := LOW_TOP - 6.0          # floor height at the bottom of down tunnel 1
const BRIDGE_END := -346.0
const H_BRIDGE := H_TUN1 - 1.2         # the bridge falls just enough to hold your speed
const TUN2_END := -406.0
const H_TUN2 := H_BRIDGE - 6.0
const FINISH_Z := -426.0
const COURSE_END := -440.0
const FALL_LIMIT := LOW_TOP - 9.0      # the pit (see fall_limit() for the whole course)

## Respawn points, in course order. A skater respawns at the last one it passed.
const CHECKPOINTS: Array[Vector3] = [
	Vector3(0, 0.2, -2), Vector3(0, 0.2, -48), Vector3(0, LOW_TOP + 0.2, -145),
	Vector3(0, LOW_TOP + 0.2, -182), Vector3(0, LOW_TOP + 0.2, -200),
	Vector3(0, H_TUN1 + 0.3, -270), Vector3(0, H_TUN1 - 0.6, -306), Vector3(0, H_BRIDGE + 0.3, -348),
	Vector3(0, H_TUN2 + 0.3, -410),
]

## Crates in the dry section (x, z). Hit one hard enough and it smashes.
const CRATES: Array[Vector2] = [
	Vector2(-2.4, -150), Vector2(1.0, -154), Vector2(2.6, -160), Vector2(-0.8, -164),
	Vector2(-2.8, -170), Vector2(1.6, -173), Vector2(-1.8, -184),
]

## Zombies: (x, z, time offset, walk direction). Each one rises, shambles, and sinks
## on an 8-second cycle.
const ZOMBIES: Array[Vector4] = [
	Vector4(-1.5, -40, 0.0, 1), Vector4(2.0, -47, 3.5, -1), Vector4(0.5, -157, 1.5, -1),
	Vector4(-2.5, -167, 5.0, 1), Vector4(2.6, -181, 2.5, -1), Vector4(-1.0, -208, 4.0, 1),
	Vector4(1.8, -216, 0.5, -1), Vector4(-2.2, -223, 6.0, 1),
	Vector4(-2.0, -296, 1.0, 1), Vector4(2.2, -322, 4.5, -1), Vector4(-1.5, -414, 2.0, 1),
]
const ZOMBIE_CYCLE := 8.0
## Bat flocks: (center z, half length of the stretch they patrol).
const BAT_ZONES: Array[Vector2] = [
	Vector2(-15, 8), Vector2(-42, 9), Vector2(-80, 12), Vector2(-112, 12), Vector2(-215, 12),
]
const BAT_COUNT := 15

## Token kinds.
enum Token { GOLD, TURBO, SHIELD, MEGA_AIR, SIGNAL }
const TOKEN_COLORS := {
	Token.GOLD: Color("ffcf3a"), Token.TURBO: Color("ff7a1a"),
	Token.SHIELD: Color("35d0ff"), Token.MEGA_AIR: Color("c46bff"), Token.SIGNAL: Color("6ff6ff"),
}
const TOKEN_LETTERS := {Token.TURBO: "T", Token.SHIELD: "S", Token.MEGA_AIR: "A", Token.SIGNAL: "?"}

## Easter eggs (a few things in this tunnel aren't from this tunnel). The hidden SIGNAL token floats
## high over the last kicker's landing: you need Mega Air and full speed to reach it, and it doesn't
## come back once someone has it.
const SIGNAL_TOKEN_HEIGHT := 6.6

const TOKEN_RADIUS := 1.15
const GOLD_RESPAWN := 8.0
const POWER_RESPAWN := 12.0

var _tokens: Array[Node3D] = []
var _token_kind: Array[int] = []
var _token_back_at: Array[float] = []      # local clock time a taken token reappears (-1 = present)
var _crates: Array[StaticBody3D] = []
var _zombies: Array[AnimatableBody3D] = []
var _bats: Array[Node3D] = []
var _local_clock := 0.0
var _blinkers: Array[OmniLight3D] = []
var _blink_t := 0.0
var _glow_light: OmniLight3D
var _glow_mat: StandardMaterial3D
var _env: Environment

var _mat_dry := _material(Color("6b6157"), 0.9)
var _mat_wet := _material(Color("34434a"), 0.15, 0.3)
var _mat_wall := _material(Color("3d3a35"), 1.0)
var _mat_plank := _material(Color("8a6239"), 0.8)
var _mat_crate := _material(Color("a0743f"), 0.85)
var _mat_kicker := _material(Color("d9822b"), 0.6)


func _ready() -> void:
	_build_environment()
	_build_course()
	_build_lights()
	_build_props()
	_build_drain_glow()
	_build_easter_eggs()
	_build_zombies()
	_build_bats()
	_build_tokens()
	var city := City.new()
	city.name = "City"
	add_child(city)
	city.build(self, _env)


func _process(delta: float) -> void:
	_blink_t += delta
	var on := fmod(_blink_t, 0.8) < 0.4
	for light in _blinkers:
		light.light_energy = 3.0 if on else 0.2
	_pulse_drain_glow()
	var t := clock()
	for i in _bats.size():
		_place_bat(i, t)
	for i in _tokens.size():
		var token := _tokens[i]
		if _token_back_at[i] >= 0.0 and _local_clock >= _token_back_at[i]:
			_token_back_at[i] = -1.0
			token.visible = true
		token.rotation.y = _local_clock * (2.5 if _token_kind[i] == Token.GOLD else 1.6)
		token.get_child(0).position.y = 0.12 * sin(_local_clock * 3.0 + i)


func _physics_process(delta: float) -> void:
	_local_clock += delta
	var t := clock()
	for i in _zombies.size():
		_place_zombie(i, t)
	if multiplayer.is_server():
		_check_token_pickups()


# ------------------------------------------------------------------- tokens

## Host only: hand out any token a racer is touching.
func _check_token_pickups() -> void:
	var race = get_node_or_null("/root/Main/Race")
	var players = get_node_or_null("/root/Main/Players")
	if race == null or players == null or not race.is_racing():
		return
	for i in _tokens.size():
		if _token_back_at[i] >= 0.0:
			continue
		var at: Vector3 = _tokens[i].position
		for skater in players.get_children():
			if skater.finished:
				continue
			# The rider's body is a ~2 m tall capsule standing on its feet.
			var feet: Vector3 = skater.global_position
			var rise := at.y - feet.y
			if Vector2(at.x - feet.x, at.z - feet.z).length() < TOKEN_RADIUS and rise > -0.4 and rise < 2.3:
				_take_token.rpc(i)
				skater.rpc_id(skater.get_multiplayer_authority(), "grant_token", _token_kind[i])
				break


@rpc("authority", "call_local", "reliable")
func _take_token(index: int) -> void:
	if index < 0 or index >= _tokens.size():
		return
	_tokens[index].visible = false
	var wait := GOLD_RESPAWN if _token_kind[index] == Token.GOLD else POWER_RESPAWN
	if _token_kind[index] == Token.SIGNAL:
		wait = 1e9                                   # one per race
	_token_back_at[index] = _local_clock + wait


func reset_tokens() -> void:
	for i in _tokens.size():
		_tokens[i].visible = true
		_token_back_at[i] = -1.0


func _build_tokens() -> void:
	# Gold rows along the straights, a gold arc over each kicker's landing, gold
	# between the crates and down the final sprint.
	for z in range(-8, -30, -3):
		_token(Token.GOLD, Vector3(-1.6 if (z / 3) % 2 == 0 else 1.6, 0, z))
	for z in range(-33, -52, -3):
		_token(Token.GOLD, Vector3(0.0, 0, z))
	for kz in KICKER_Z:
		for k in 3:
			var z: float = kz - KICKER_LENGTH - 4.0 - k * 2.5
			_token(Token.GOLD, Vector3(0, 2.0 + (1.0 if k == 1 else 0.0), z))
	for z in [-157.0, -167.0, -177.0, -187.0]:
		_token(Token.GOLD, Vector3(0.6 if int(z) % 2 == 0 else -0.6, 0, z))
	for z in range(-200, -262, -3):                          # down tunnel 1
		_token(Token.GOLD, Vector3(-2.0 if (z / 3) % 2 == 0 else 2.0, 0, z))
	for z in range(-272, -342, -5):                          # the bridge
		_token(Token.GOLD, Vector3(1.4 * sin(z * 0.3), 0, z))
	for z in range(-352, -402, -4):                          # down tunnel 2
		_token(Token.GOLD, Vector3(0.0, 0, z))
	# Power tokens where they matter.
	_token(Token.MEGA_AIR, Vector3(-1.5, 0, -52))       # right before The Drop
	_token(Token.MEGA_AIR, Vector3(1.5, 0, -52))
	_token(Token.SHIELD, Vector3(-2.2, 0, -36))         # zombies on the wet straight
	_token(Token.SHIELD, Vector3(2.4, 0, -146))         # zombies + crates ahead
	_token(Token.TURBO, Vector3(-2.4, 0, -146))
	_token(Token.TURBO, Vector3(0, 0, -199))            # after the pit: sprint home
	_token(Token.SHIELD, Vector3(-2.6, 0, -205))
	_token(Token.SHIELD, Vector3(2.6, 0, -280))              # people crossing the bridge
	_token(Token.TURBO, Vector3(-2.4, 0, -340))              # into down tunnel 2
	_token(Token.TURBO, Vector3(2.4, 0, -340))
	# The hidden one.
	_token(Token.SIGNAL, Vector3(0, SIGNAL_TOKEN_HEIGHT, KICKER_Z[2] - KICKER_LENGTH - 5.5))


## A token floating at (x, height above the floor, z).
func _token(kind: int, at: Vector3) -> void:
	var root := Node3D.new()
	root.position = Vector3(at.x, floor_y(at.z) + 1.0 + at.y, at.z)
	var bob := Node3D.new()
	root.add_child(bob)                                                  # child 0: bobs up and down
	var color: Color = TOKEN_COLORS[kind]
	var mat := _material(color, 0.25, 0.6, 2.2 if kind == Token.GOLD else 3.0)
	if kind == Token.GOLD:
		var coin := CylinderMesh.new()
		coin.top_radius = 0.28
		coin.bottom_radius = 0.28
		coin.height = 0.07
		_mesh(bob, coin, Vector3.ZERO, mat).rotation.x = PI / 2.0
	else:
		var gem := BoxMesh.new()
		gem.size = Vector3(0.42, 0.42, 0.42)
		var g := _mesh(bob, gem, Vector3.ZERO, mat)
		g.rotation = Vector3(PI / 4.0, 0, PI / 4.0)
		var letter := Label3D.new()
		letter.text = TOKEN_LETTERS[kind]
		letter.font_size = 72
		letter.outline_size = 14
		letter.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		letter.no_depth_test = true
		letter.position.y = 0.55
		letter.modulate = color.lightened(0.4)
		bob.add_child(letter)
	add_child(root)
	_tokens.append(root)
	_token_kind.append(kind)
	_token_back_at.append(-1.0)


## The shared clock hazards run on: the race clock during a race, a local one otherwise.
func clock() -> float:
	var race = get_node_or_null("/root/Main/Race")
	if race and race.state != 0:
		return race.race_time
	return _local_clock


## True when a bat is close enough to this point to spook a rider.
func bat_hits(point: Vector3) -> bool:
	for bat in _bats:
		if bat.position.distance_to(point) < 0.75:
			return true
	return false


## Floor height of the main course at a given z (ignores kickers and the pit).
static func floor_y(z: float) -> float:
	if z > SLOPE_START:
		return 0.0
	if z >= SLOPE_END:
		return -SLOPE_DROP * (SLOPE_START - z) / (SLOPE_START - SLOPE_END)
	if z > TUN1_START:
		return LOW_TOP
	if z >= TUN1_END:
		return lerpf(LOW_TOP, H_TUN1, (TUN1_START - z) / (TUN1_START - TUN1_END))
	if z >= BRIDGE_END:
		return lerpf(H_TUN1, H_BRIDGE, (TUN1_END - z) / (TUN1_END - BRIDGE_END))
	if z >= TUN2_END:
		return lerpf(H_BRIDGE, H_TUN2, (BRIDGE_END - z) / (BRIDGE_END - TUN2_END))
	return H_TUN2


## Below this height at z you've fallen off the course and respawn.
static func fall_limit(z: float) -> float:
	return floor_y(z) - 9.0


static func in_freestyle_zone(z: float) -> bool:
	return z <= SLOPE_START and z > SLOPE_END


## The checkpoint to respawn at for a skater at this position.
func checkpoint_for(pos: Vector3) -> Vector3:
	var best := CHECKPOINTS[0]
	for cp in CHECKPOINTS:
		if pos.z <= cp.z + 0.5:
			best = cp
	return best


## How much drag a floor applies (wet floors carry speed a long way).
static func drag_of(collider: Object) -> float:
	if collider and collider.has_meta("drag"):
		return collider.get_meta("drag")
	return DRAG_DRY


@rpc("any_peer", "call_local", "reliable")
func break_crate(index: int) -> void:
	if index < 0 or index >= _crates.size():
		return
	var crate := _crates[index]
	crate.visible = false
	crate.process_mode = Node.PROCESS_MODE_DISABLED
	crate.collision_layer = 0


func reset_crates() -> void:
	for crate in _crates:
		crate.visible = true
		crate.process_mode = Node.PROCESS_MODE_INHERIT
		crate.collision_layer = 1


# ------------------------------------------------------------------ hazards

func _place_zombie(i: int, t: float) -> void:
	var d := ZOMBIES[i]
	var p := fmod(t + d.z, ZOMBIE_CYCLE)
	var rise := 0.0
	var walk := 0.0
	if p < 1.2:
		rise = p / 1.2
	elif p < 5.2:
		rise = 1.0
		walk = sin((p - 1.2) / 4.0 * PI) * 1.4                  # out into the lane and back
	elif p < 6.4:
		rise = 1.0 - (p - 5.2) / 1.2
	var zombie := _zombies[i]
	zombie.position = Vector3(d.x + d.w * walk, floor_y(d.y) - 1.9 * (1.0 - rise), d.y)
	zombie.collision_layer = 1 if rise > 0.6 else 0
	var model: Node3D = zombie.get_child(0)
	model.rotation.z = sin(t * 2.7 + i) * 0.12 * rise
	model.rotation.x = -0.25 * (1.0 - rise)                     # claws up leaning forward


func _place_bat(i: int, t: float) -> void:
	var zone := BAT_ZONES[i % BAT_ZONES.size()]
	var phase := i * 1.7
	var w := 0.9 + 0.13 * (i % 5)
	var z := zone.x + zone.y * sin(0.37 * w * t + 2.0 * phase)
	var swoop := pow(maxf(sin(0.5 * w * t + phase * 3.0), 0.0), 6.0)
	var pos := Vector3(3.0 * sin(w * t + phase), floor_y(z) + 3.2 + 0.5 * sin(2.0 * w * t + phase) - swoop * 1.9, z)
	var bat := _bats[i]
	var ahead := pos + Vector3(3.0 * w * cos(w * t + phase), 0, zone.y * 0.37 * w * cos(0.37 * w * t + 2.0 * phase)) * 0.05
	bat.position = pos
	if not ahead.is_equal_approx(pos):
		bat.look_at(ahead, Vector3.UP)
	var flap := sin(t * 24.0 + i) * 0.9
	bat.get_child(1).rotation.z = flap
	bat.get_child(2).rotation.z = -flap


func _build_zombies() -> void:
	var skin := _material(Color("7d9471"), 0.9)
	var shirt := _material(Color("5c4a3a"), 1.0)
	var pants := _material(Color("2f3540"), 1.0)
	var eyes := _material(Color("ff2a1a"), 0.4, 0.0, 3.0)
	var hole := _material(Color("0a0807"), 1.0)
	for d in ZOMBIES:
		# The broken floor it climbs out of.
		var crack := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.6
		disc.bottom_radius = 0.6
		disc.height = 0.03
		crack.mesh = disc
		crack.material_override = hole
		crack.position = Vector3(d.x, floor_y(d.y) + 0.016, d.y)
		add_child(crack)
		for k in 4:
			_box(Vector3(0.25, 0.12, 0.2), crack.position + Vector3(cos(k * 1.6) * 0.75, 0.05, sin(k * 1.6) * 0.75),
				_mat_dry, false).rotation.y = k * 0.7

		var body := AnimatableBody3D.new()
		body.set_meta("zombie", true)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.32
		capsule.height = 1.7
		shape.shape = capsule
		shape.position.y = 0.85
		var model := Node3D.new()
		body.add_child(model)                                        # child 0: the model
		body.add_child(shape)
		_mesh(model, _capsule_mesh(0.11, 0.8), Vector3(-0.12, 0.4, 0), pants)
		_mesh(model, _capsule_mesh(0.11, 0.8), Vector3(0.12, 0.4, 0), pants)
		_mesh(model, _capsule_mesh(0.25, 0.75), Vector3(0, 1.05, 0), shirt)
		for side in [-1.0, 1.0]:
			var arm := _mesh(model, _capsule_mesh(0.08, 0.6), Vector3(side * 0.3, 1.3, 0.28), skin)
			arm.rotation.x = PI / 2.0                                # arms reaching for the riders
		var head := _mesh(model, _sphere_mesh(0.22), Vector3(0, 1.6, 0.04), skin)
		head.scale = Vector3(1.0, 1.1, 1.0)
		for side in [-1.0, 1.0]:
			_mesh(model, _sphere_mesh(0.04), Vector3(side * 0.08, 1.65, 0.24), eyes)
		add_child(body)
		_zombies.append(body)


func _build_bats() -> void:
	var fur := _material(Color("16120f"), 1.0)
	var wing := _material(Color("2b201a"), 1.0)
	var eyes := _material(Color("ff3b2f"), 0.4, 0.0, 4.0)
	for i in BAT_COUNT:
		var bat := Node3D.new()
		bat.scale = Vector3.ONE * 1.6
		var torso := _mesh(bat, _sphere_mesh(0.08), Vector3.ZERO, fur)          # child 0
		torso.scale = Vector3(1.0, 0.8, 1.5)
		for side in [-1.0, 1.0]:                                                  # children 1, 2
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.05, 0, 0)
			bat.add_child(pivot)
			var membrane := _mesh(pivot, null, Vector3(side * 0.17, 0, 0), wing)
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.32, 0.01, 0.17)
			membrane.mesh = mesh
		for side in [-1.0, 1.0]:
			_mesh(bat, _sphere_mesh(0.018), Vector3(side * 0.03, 0.02, -0.11), eyes)
		add_child(bat)
		_bats.append(bat)


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	parent.add_child(instance)
	return instance


static func _capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	return m


static func _sphere_mesh(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	return m


# ------------------------------------------------------------------ building

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0d0c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("5a6660")
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color("1c2421")
	env.fog_density = 0.02
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env = env
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_course() -> void:
	_floor(Vector3(0, 0, -12), 36.0, _mat_dry, DRAG_DRY)                       # start straight
	_floor(Vector3(0, 0, (-30.0 + SLOPE_START) / 2.0), -30.0 - SLOPE_START, _mat_wet, DRAG_WET)
	_ramp(SLOPE_START, SLOPE_END, 0.0, LOW_TOP)                                # The Drop
	for z in KICKER_Z:
		_kicker(z)
	_floor(Vector3(0, LOW_TOP, (SLOPE_END + GAP_START) / 2.0), SLOPE_END - GAP_START, _mat_dry, DRAG_DRY)
	_floor(Vector3(0, LOW_TOP, (GAP_END + TUN1_START) / 2.0), GAP_END - TUN1_START, _mat_wet, DRAG_WET)

	# The plank across the pit.
	var plank := _box(Vector3(1.4, 0.15, GAP_START - GAP_END + 0.6),
		Vector3(0, LOW_TOP - 0.075, (GAP_START + GAP_END) / 2.0), _mat_plank)
	plank.set_meta("drag", DRAG_DRY)

	# Side walls, back wall and the roof of the old tunnel (down tunnel 1 carries on from it).
	var length := 6.0 - TUN1_START
	for side in [-1, 1]:
		_box(Vector3(1, 22, length), Vector3(side * (LANE_HALF_WIDTH + 0.5), -7, 6 - length / 2.0), _mat_wall)
	_box(Vector3(10, 22, 1), Vector3(0, -7, 6.5), _mat_wall)
	_box(Vector3(LANE_HALF_WIDTH * 2.0 + 2.0, 1, length), Vector3(0, 4.5, 6 - length / 2.0), _material(Color("1d1f22"), 0.9))
	# A step down from the old tunnel's roof to down tunnel 1's.
	_box(Vector3(LANE_HALF_WIDTH * 2.0 + 2.0, 16, 1), Vector3(0, LOW_TOP + 14.0, TUN1_START - 0.5), _mat_wall, false)


func _floor(center_top: Vector3, length: float, mat: Material, drag: float) -> void:
	var body := _box(Vector3(LANE_HALF_WIDTH * 2, 1, length), center_top - Vector3(0, 0.5, 0), mat)
	body.set_meta("drag", drag)


func _ramp(z_from: float, z_to: float, y_from: float, y_to: float) -> void:
	var run := absf(z_to - z_from)
	var drop := y_from - y_to
	var angle := atan2(drop, run)
	var length := sqrt(run * run + drop * drop) + 0.4
	var normal := Vector3(0, cos(angle), -sin(angle))
	var mid_top := Vector3(0, (y_from + y_to) / 2.0, (z_from + z_to) / 2.0)
	var body := _box(Vector3(LANE_HALF_WIDTH * 2, 1, length), mid_top - normal * 0.5, _mat_wet)
	body.rotation.x = -angle
	body.set_meta("drag", DRAG_WET)


## A wedge on the slope that launches you into the air.
func _kicker(z_start: float) -> void:
	var slope_angle := atan2(SLOPE_DROP, SLOPE_START - SLOPE_END)
	var rise_angle := atan2(KICKER_RISE, KICKER_LENGTH)
	var tilt := rise_angle - slope_angle                    # kicker surface vs. horizontal
	var length := sqrt(KICKER_LENGTH * KICKER_LENGTH + KICKER_RISE * KICKER_RISE)
	var direction := Vector3(0, sin(tilt), -cos(tilt))
	var normal := Vector3(0, cos(tilt), sin(tilt))
	var start := Vector3(0, floor_y(z_start) - 0.02, z_start)
	var thickness := 1.4
	var body := _box(Vector3(5.0, thickness, length),
		start + direction * (length / 2.0) - normal * (thickness / 2.0), _mat_kicker)
	body.rotation.x = tilt
	body.set_meta("drag", DRAG_WET)
	body.set_meta("kicker", true)


func _build_lights() -> void:
	var z := -6.0
	var side := 1
	while z > TUN1_START:
		var light := OmniLight3D.new()
		light.light_color = Color("ffb36b")
		light.light_energy = 1.6
		light.omni_range = 11.0
		light.position = Vector3(side * 3.6, floor_y(z) + 3.0, z)
		add_child(light)
		_box(Vector3(0.2, 0.5, 0.2), light.position + Vector3(side * 0.3, -0.3, 0), _material(Color("ffcf8a"), 0.5, 0.0, 2.0), false)
		side = -side
		z -= 14.0

	# Flashing construction lights at the pit.
	for x in [-3.6, 3.6]:
		var amber := OmniLight3D.new()
		amber.light_color = Color("ff9a1a")
		amber.omni_range = 8.0
		amber.position = Vector3(x, LOW_TOP + 1.0, GAP_START + 1.0)
		add_child(amber)
		_blinkers.append(amber)

	# Neon strips mark the freestyle slope.
	for nz in [SLOPE_START - 1.0, SLOPE_END + 1.0]:
		var neon := OmniLight3D.new()
		neon.light_color = Color("c46bff")
		neon.light_energy = 2.5
		neon.omni_range = 10.0
		neon.position = Vector3(0, floor_y(nz) + 3.5, nz)
		add_child(neon)


func _build_props() -> void:
	for i in CRATES.size():
		var c := CRATES[i]
		var crate := _box(Vector3(1.2, 1.2, 1.2), Vector3(c.x, LOW_TOP + 0.6, c.y), _mat_crate)
		crate.set_meta("crate", i)
		crate.rotation.y = 0.3 * (i % 3 - 1)
		_crates.append(crate)

	_sign("START", Vector3(0, 3.4, -1.5), Color("7cff6b"))
	_sign("THE DROP", Vector3(0, 3.6, SLOPE_START + 1.0), Color("d38cff"), 120)
	_sign("FREESTYLE  Q spin   E flip   F grab", Vector3(0, 2.6, SLOPE_START + 1.0), Color("f0dcff"), 48)
	_sign("FINISH", Vector3(0, floor_y(FINISH_Z) + 3.4, FINISH_Z), Color("ffd23f"))
	_finish_strip()

	# Signs and numbered doors along the walls.
	_wall_sign("NO TRESPASSING", Vector3(LANE_HALF_WIDTH - 0.02, LOW_TOP + 1.8, GAP_START + 3.0), -1, Color("ff3b30"))
	_wall_sign("NO TRESPASSING", Vector3(-LANE_HALF_WIDTH + 0.02, LOW_TOP + 1.8, GAP_START + 3.0), 1, Color("ff3b30"))
	var door := 1
	for z in [-20.0, -45.0, -152.0, -176.0, -201.0]:
		var top := floor_y(z)
		var x := -LANE_HALF_WIDTH + 0.05 if door % 2 == 1 else LANE_HALF_WIDTH - 0.05
		_box(Vector3(0.1, 2.4, 1.4), Vector3(x, top + 1.2, z), _material(Color("2a1f17"), 0.9), false)
		_wall_sign("DOOR %02d" % door, Vector3(x * 0.99, top + 2.7, z), 1 if x < 0 else -1, Color("e8e2d4"))
		door += 1


## Something down there is awake. A faint glow breathes behind one storm-drain
## grate low on the wall in the crate field. No sign, no name: just the color.
const DRAIN_GLOW_Z := -164.0
const DRAIN_GLOW_COLOR := Color(0.05, 0.85, 1.0)


func _build_drain_glow() -> void:
	var x := -LANE_HALF_WIDTH + 0.02
	var y := LOW_TOP + 0.45
	# Dark opening in the wall.
	_box(Vector3(0.04, 0.7, 1.3), Vector3(x, y, DRAIN_GLOW_Z), _material(Color("050707"), 1.0), false)
	# The glow, set back behind the bars.
	_glow_mat = _material(DRAIN_GLOW_COLOR, 1.0, 0.0, 1.5)
	_box(Vector3(0.02, 0.5, 1.0), Vector3(x + 0.01, y, DRAIN_GLOW_Z), _glow_mat, false)
	# Rusty bars in front of it.
	var rust := _material(Color("3b2a20"), 0.7, 0.6)
	for i in 7:
		_box(Vector3(0.06, 0.72, 0.06), Vector3(x + 0.05, y, DRAIN_GLOW_Z - 0.6 + i * 0.2), rust, false)
	for dy in [-0.36, 0.36]:
		_box(Vector3(0.07, 0.07, 1.36), Vector3(x + 0.05, y + dy, DRAIN_GLOW_Z), rust, false)
	# Light that spills onto the wet floor.
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = DRAIN_GLOW_COLOR
	_glow_light.omni_range = 3.5
	_glow_light.position = Vector3(x + 0.6, y, DRAIN_GLOW_Z)
	add_child(_glow_light)


## A slow breath, about every 5 seconds, with a rare brighter flare.
func _pulse_drain_glow() -> void:
	if _glow_light == null:
		return
	var breath := 0.5 + 0.5 * sin(_blink_t * TAU / 5.0)
	var flare := 1.0 if fmod(_blink_t, 37.0) < 0.6 else 0.0
	_glow_light.light_energy = 0.35 + 0.9 * breath + 2.0 * flare
	_glow_mat.emission_energy_multiplier = 0.6 + 1.6 * breath + 3.0 * flare


func _finish_strip() -> void:
	for i in 8:
		var tile := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, 0.02, 1.0)
		tile.mesh = mesh
		tile.material_override = _material(Color.WHITE if i % 2 == 0 else Color.BLACK, 0.6)
		tile.position = Vector3(-3.5 + i, floor_y(FINISH_Z) + 0.01, FINISH_Z)
		add_child(tile)


## Easter eggs: POPDAT tags sprayed on the walls (the cyan glow is the storm-drain grate above).
func _build_easter_eggs() -> void:
	_tag("POPDAT", Vector3(LANE_HALF_WIDTH - 0.02, 1.7, -18.0), -1, Color("ff4fc8"))
	_tag("POPDAT", Vector3(-LANE_HALF_WIDTH + 0.02, LOW_TOP + 2.0, -150.0), 1, Color("35f0ff"))
	_tag("POPDAT", Vector3(LANE_HALF_WIDTH - 0.02, floor_y(-200.0) + 1.8, -200.0), -1, Color("ffd23f"))


func _tag(text: String, pos: Vector3, facing_x: int, color: Color) -> void:
	var label := Label3D.new()
	label.name = "Tag_" + text
	label.text = text
	label.font_size = 150
	label.pixel_size = 0.006
	label.outline_size = 30
	label.outline_modulate = Color("101014")
	label.modulate = color
	label.position = pos
	var yaw := 0.0 if facing_x == 0 else (PI / 2.0 if facing_x > 0 else -PI / 2.0)    # 0: faces +z
	label.rotation = Vector3(0, yaw, 0.08 * sin(pos.z))
	label.add_to_group("popdat_tags")
	add_child(label)


func _sign(text: String, pos: Vector3, color: Color, font_size := 160) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.outline_size = maxi(font_size / 7, 8)
	label.modulate = color
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y                # always reads the right way
	add_child(label)


func _wall_sign(text: String, pos: Vector3, facing_x: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.outline_size = 12
	label.modulate = color
	label.position = pos
	label.rotation.y = PI / 2.0 if facing_x > 0 else -PI / 2.0
	add_child(label)


func _box(size: Vector3, pos: Vector3, mat: Material, solid := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)
	if solid:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
	add_child(body)
	return body


static func _material(color: Color, roughness: float, metallic := 0.0, emission := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat
