extends Node3D
## The race course, built in code from greybox shapes: a flooded tunnel that runs
## dry -> wet -> downhill -> crate field -> plank over a pit -> wet sprint -> finish.
## Wet floors keep your speed; dry floors drag. Every peer builds the same course.

const FINISH_Z := -175.0
const LANE_HALF_WIDTH := 4.0
const LOW_TOP := -6.0            # floor height after the downhill
const GAP_START := -140.0
const GAP_END := -146.0
const DRAG_DRY := 1.2            # m/s lost per second while coasting
const DRAG_WET := 0.3

## Respawn points, in course order. A skater respawns at the last one it passed.
const CHECKPOINTS: Array[Vector3] = [
	Vector3(0, 0.2, -2), Vector3(0, LOW_TOP + 0.2, -95), Vector3(0, LOW_TOP + 0.2, -132),
	Vector3(0, LOW_TOP + 0.2, -150),
]

## Crates in the dry section (x, z). Hit one hard enough and it smashes.
const CRATES: Array[Vector2] = [
	Vector2(-2.4, -100), Vector2(1.0, -104), Vector2(2.6, -110), Vector2(-0.8, -114),
	Vector2(-2.8, -120), Vector2(1.6, -123), Vector2(-1.8, -134),
]

var _crates: Array[StaticBody3D] = []
var _blinkers: Array[OmniLight3D] = []
var _blink_t := 0.0

var _mat_dry := _material(Color("6b6157"), 0.9)
var _mat_wet := _material(Color("34434a"), 0.15, 0.3)
var _mat_wall := _material(Color("3d3a35"), 1.0)
var _mat_plank := _material(Color("8a6239"), 0.8)
var _mat_crate := _material(Color("a0743f"), 0.85)


func _ready() -> void:
	_build_environment()
	_build_course()
	_build_lights()
	_build_props()


func _process(delta: float) -> void:
	_blink_t += delta
	var on := fmod(_blink_t, 0.8) < 0.4
	for light in _blinkers:
		light.light_energy = 3.0 if on else 0.2


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


# ------------------------------------------------------------------ building

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0d0c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("5a6660")
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color("1c2421")
	env.fog_density = 0.025
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_course() -> void:
	# Floors: top surface at y = 0 before the downhill, LOW_TOP after it.
	_floor(Vector3(0, 0, -12), 36.0, _mat_dry, DRAG_DRY)              # start straight (dry)
	_floor(Vector3(0, 0, -45), 30.0, _mat_wet, DRAG_WET)              # wet straight
	_ramp(-60.0, -90.0, 0.0, LOW_TOP)                                 # wet downhill
	_floor(Vector3(0, LOW_TOP, -115), 50.0, _mat_dry, DRAG_DRY)       # crate field (dry)
	_floor(Vector3(0, LOW_TOP, -168), 44.0, _mat_wet, DRAG_WET)       # wet sprint to the finish

	# The plank across the pit.
	var plank := _box(Vector3(1.4, 0.15, GAP_START - GAP_END + 0.6),
		Vector3(0, LOW_TOP - 0.075, (GAP_START + GAP_END) / 2.0), _mat_plank)
	plank.set_meta("drag", DRAG_DRY)

	# Side walls, back wall, end wall.
	var length := 196.0
	for side in [-1, 1]:
		_box(Vector3(1, 14, length), Vector3(side * (LANE_HALF_WIDTH + 0.5), -3, 6 - length / 2.0), _mat_wall)
	_box(Vector3(10, 14, 1), Vector3(0, -3, 6.5), _mat_wall)
	_box(Vector3(10, 14, 1), Vector3(0, -3, 6 - length - 0.5), _mat_wall)


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


func _build_lights() -> void:
	var z := -6.0
	var side := 1
	while z > -190.0:
		var top := 0.0 if z > -75.0 else LOW_TOP
		var light := OmniLight3D.new()
		light.light_color = Color("ffb36b")
		light.light_energy = 1.6
		light.omni_range = 11.0
		light.position = Vector3(side * 3.6, top + 3.0, z)
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


func _build_props() -> void:
	for i in CRATES.size():
		var c := CRATES[i]
		var crate := _box(Vector3(1.2, 1.2, 1.2), Vector3(c.x, LOW_TOP + 0.6, c.y), _mat_crate)
		crate.set_meta("crate", i)
		crate.rotation.y = 0.3 * (i % 3 - 1)
		_crates.append(crate)

	_sign("START", Vector3(0, 3.4, -1.5), Color("7cff6b"))
	_sign("FINISH", Vector3(0, LOW_TOP + 3.4, FINISH_Z), Color("ffd23f"))
	_finish_strip()

	# Signs and numbered doors along the walls.
	_wall_sign("NO TRESPASSING", Vector3(LANE_HALF_WIDTH - 0.02, LOW_TOP + 1.8, GAP_START + 3.0), -1, Color("ff3b30"))
	_wall_sign("NO TRESPASSING", Vector3(-LANE_HALF_WIDTH + 0.02, LOW_TOP + 1.8, GAP_START + 3.0), 1, Color("ff3b30"))
	var door := 1
	for z in [-20.0, -52.0, -102.0, -126.0, -158.0]:
		var top := 0.0 if z > -75.0 else LOW_TOP
		var x := -LANE_HALF_WIDTH + 0.05 if door % 2 == 1 else LANE_HALF_WIDTH - 0.05
		_box(Vector3(0.1, 2.4, 1.4), Vector3(x, top + 1.2, z), _material(Color("2a1f17"), 0.9), false)
		_wall_sign("DOOR %02d" % door, Vector3(x * 0.99, top + 2.7, z), 1 if x < 0 else -1, Color("e8e2d4"))
		door += 1


func _finish_strip() -> void:
	for i in 8:
		var tile := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, 0.02, 1.0)
		tile.mesh = mesh
		tile.material_override = _material(Color.WHITE if i % 2 == 0 else Color.BLACK, 0.6)
		tile.position = Vector3(-3.5 + i, LOW_TOP + 0.01, FINISH_Z)
		add_child(tile)


func _sign(text: String, pos: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 160
	label.outline_size = 24
	label.modulate = color
	label.position = pos
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
