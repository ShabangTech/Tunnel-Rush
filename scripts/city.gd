extends Node3D
## The second half of the course, after the pit (2026-10-30):
##
##   DOWN TUNNEL 1 (a wet downhill tube with neon speed rings) -> THE BAY BRIDGE (open air:
##   blue water, sky, skyline, a crowd running from zombies, people dashing across the road)
##   -> DOWN TUNNEL 2 (a cinder-block stairwell tube: handrails, standpipes, wet-floor signs)
##   -> the FINISH PLAZA (herringbone pavers, round planters with trees, lamp posts).
##
## Both down tunnels are wet and steep enough that you gain speed without kicking, and the
## bridge falls just enough that the speed you built doesn't bleed away.
##
## Everything here is built in code, including the textures (pavers, cinder blocks, the
## graffiti murals). People, zombies and the boat move on the shared race clock, so every
## peer sees them in the same place with no network traffic.

const Level := preload("res://scripts/level.gd")

const HALF := Level.LANE_HALF_WIDTH
const WALK_OUT := 7.0                 # bridge sidewalks run from the lane edge out to here
const RAIL_X := 7.4
const WATER_Y := Level.H_BRIDGE - 9.0

## People fleeing along the bridge sidewalks: (side, speed m/s, offset, look seed).
const RUNNERS := 16
## Zombies chasing them down the sidewalks.
const CHASERS := 5
## People dashing across the road: (z, time offset, direction). Run into one and you lose speed.
const CROSSERS: Array[Vector3] = [Vector3(-286, 0.0, 1), Vector3(-308, 2.6, -1), Vector3(-330, 4.4, 1)]
const CROSS_CYCLE := 7.0
const CROSS_TIME := 2.6

var level: Node3D
var _runners: Array[Node3D] = []
var _runner_data: Array[Vector4] = []
var _chasers: Array[Node3D] = []
var _chaser_data: Array[Vector3] = []
var _crossers: Array[AnimatableBody3D] = []
var _boat: Node3D
var _sun: DirectionalLight3D
var _env: Environment
var _open := 0.0                      # 0 inside a tunnel, 1 out in the open (camera)

var _mat_wet := Level._material(Color("34434a"), 0.15, 0.3)
var _mat_road := Level._material(Color("3a3f44"), 0.55, 0.1)
var _mat_concrete := Level._material(Color("c9c1ad"), 0.9)
var _mat_steel := Level._material(Color("9aa1a6"), 0.35, 0.8)
var _mat_dark := Level._material(Color("1d1f22"), 0.9)


func build(owner_level: Node3D, env: Environment) -> void:
	level = owner_level
	_env = env
	_build_sky()
	_build_tunnel_one()
	_build_bridge()
	_build_water_view()
	_build_tunnel_two()
	_build_plaza()
	_build_people()


func _process(delta: float) -> void:
	var t: float = level.clock()
	_update_open(delta)
	for i in _runners.size():
		_place_runner(i, t)
	for i in _chasers.size():
		_place_chaser(i, t)
	_boat.position = Vector3(-90.0 + fmod(t * 4.0, 360.0) - 180.0, WATER_Y + 0.4, -470.0)


func _physics_process(_delta: float) -> void:
	var t: float = level.clock()
	for i in _crossers.size():
		_place_crosser(i, t)


# ----------------------------------------------------------------- light and sky

func _build_sky() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3d7fd6")
	sky_mat.sky_horizon_color = Color("a9cdee")
	sky_mat.sky_energy_multiplier = 0.85
	sky_mat.ground_horizon_color = Color("bcd8f2")
	sky_mat.ground_bottom_color = Color("1d4f80")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-30.0), 0.0)
	_sun.light_color = Color("fff1d6")
	_sun.light_energy = 0.0
	add_child(_sun)
	# A few flat clouds.
	var cloud := Level._material(Color(1, 1, 1), 1.0, 0.0, 0.6)
	for i in 14:
		var c := level._mesh(self, Level._sphere_mesh(18.0), Vector3(-260.0 + i * 40.0 + 15.0 * sin(i * 3.1),
			60.0 + 10.0 * sin(i * 1.7), -330.0 - 220.0 * cos(i * 0.9)), cloud) as MeshInstance3D
		c.scale = Vector3(2.4, 0.35, 1.2)


## Fog, sun and sky brightness follow the camera: dark and foggy in the tunnels, clear and
## sunny out on the bridge and in the plaza.
func _update_open(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var target := 0.0
	if cam:
		var z := cam.global_position.z
		if z < Level.TUN1_END + 6.0 and z > Level.BRIDGE_END - 6.0:
			target = 1.0
		elif z < Level.TUN2_END + 6.0:
			target = 1.0
	_open = move_toward(_open, target, delta * 1.5)
	_env.fog_density = lerpf(0.02, 0.0015, _open)
	_env.fog_light_color = Color("1c2421").lerp(Color("bcd8f2"), _open)
	_env.ambient_light_energy = lerpf(0.6, 0.75, _open)
	_env.ambient_light_color = Color("5a6660").lerp(Color("a9bfd6"), _open)
	_sun.light_energy = 0.9 * _open


# --------------------------------------------------------------- down tunnel 1

func _build_tunnel_one() -> void:
	var z0 := Level.TUN1_START
	var z1 := Level.TUN1_END
	_ramp(z0, z1, Level.LOW_TOP, Level.H_TUN1, _mat_wet, Level.DRAG_WET)
	_tube_walls(z0, z1, Level._material(Color("2f3236"), 1.0))
	level._sign("DOWN TUNNEL 1", Vector3(0, Level.LOW_TOP + 4.0, z0 + 2.0), Color("35f0ff"), 110)
	# Neon speed rings: a glowing arch every 6 m, alternating cyan and magenta.
	var k := 0
	var z := z0 - 4.0
	while z > z1 + 2.0:
		var color := Color("35f0ff") if k % 2 == 0 else Color("ff4fc8")
		var mat := Level._material(color, 0.4, 0.0, 3.0)
		var y := Level.floor_y(z)
		for side: float in [-1.0, 1.0]:
			level._box(Vector3(0.12, 5.0, 0.25), Vector3(side * (HALF - 0.08), y + 2.5, z), mat, false)
		level._box(Vector3(HALF * 2.0, 0.12, 0.25), Vector3(0, y + 5.0, z), mat, false)
		if k % 2 == 0:
			var light := OmniLight3D.new()
			light.light_color = color
			light.light_energy = 1.8
			light.omni_range = 9.0
			light.position = Vector3(0, y + 4.0, z)
			add_child(light)
		k += 1
		z -= 6.0
	# Graffiti murals on both walls.
	_mural(Vector3(-HALF + 0.03, 0, z0 - 18.0), 1, 1, 9.0)
	_mural(Vector3(HALF - 0.03, 0, z0 - 40.0), -1, 2, 9.0)
	level._tag("SHABANG", Vector3(HALF - 0.04, Level.floor_y(z0 - 22.0) + 2.6, z0 - 22.0), -1, Color("ffd23f"))
	level._tag("ZOO CREW", Vector3(-HALF + 0.04, Level.floor_y(z0 - 50.0) + 2.4, z0 - 50.0), 1, Color("7cff6b"))
	_portal(z1, Level.H_TUN1, Color("35f0ff"))


# ------------------------------------------------------------------- the bridge

func _build_bridge() -> void:
	var z0 := Level.TUN1_END
	var z1 := Level.BRIDGE_END
	var y0 := Level.H_TUN1
	var y1 := Level.H_BRIDGE
	# Road (smooth asphalt keeps most of your speed) and sidewalks on both sides.
	_ramp(z0, z1, y0, y1, _mat_road, Level.DRAG_WET * 1.5, HALF * 2.0)
	var pavers := _paver_material()
	for side: float in [-1.0, 1.0]:
		_ramp(z0, z1, y0, y1, pavers, Level.DRAG_DRY, WALK_OUT - HALF, side * (HALF + WALK_OUT) / 2.0)
		# Curb line, then the railing (solid) with posts.
		_slope_box(Vector3(0.2, 0.03, 1.0), side * HALF, 0.015, Level._material(Color("e8e2d4"), 0.6), false)
		_slope_box(Vector3(0.15, 1.1, 1.0), side * RAIL_X, 0.55, _mat_steel, true)
		_slope_box(Vector3(0.6, 0.6, 1.0), side * (RAIL_X + 0.3), -0.3, _mat_concrete, false)
		var z := z0 - 2.0
		while z > z1:
			level._box(Vector3(0.18, 1.2, 0.18), Vector3(side * RAIL_X, Level.floor_y(z) + 0.6, z), _mat_steel, false)
			z -= 3.0
		# Lamp posts with V heads, like the courtyard ones.
		z = z0 - 8.0
		while z > z1 + 4.0:
			_lamp(Vector3(side * (WALK_OUT - 0.6), Level.floor_y(z), z))
			z -= 16.0
	# Road center dashes.
	var z := z0 - 3.0
	while z > z1 + 1.0:
		level._box(Vector3(0.15, 0.02, 1.6), Vector3(0, Level.floor_y(z) + 0.012, z), Level._material(Color("ffd23f"), 0.6), false)
		z -= 4.0
	# Deck underside, piers into the water, and two suspension towers with cables.
	var mid := (z0 + z1) / 2.0
	var length := absf(z1 - z0)
	level._box(Vector3(RAIL_X * 2.0 + 1.0, 1.4, length), Vector3(0, (y0 + y1) / 2.0 - 1.3, mid), _mat_concrete, false)
	for pz: float in [z0 - 18.0, mid, z1 + 18.0]:
		var deck_bottom := Level.floor_y(pz) - 2.0
		level._box(Vector3(3.0, deck_bottom - WATER_Y + 2.0, 4.0), Vector3(0, (deck_bottom + WATER_Y - 2.0) / 2.0, pz), _mat_concrete, false)
	var cable := Level._material(Color("d8dde0"), 0.4, 0.7)
	for tz: float in [z0 - 22.0, z1 + 22.0]:
		var top := Level.floor_y(tz) + 24.0
		for side: float in [-1.0, 1.0]:
			level._box(Vector3(1.2, 26.0, 1.6), Vector3(side * (RAIL_X + 1.2), top - 12.0, tz), _mat_concrete, false)
			for k in 6:
				var dz := (k + 1) * 4.5
				for dir: float in [-1.0, 1.0]:
					var foot := Vector3(side * (RAIL_X + 0.5), Level.floor_y(tz + dir * dz), tz + dir * dz)
					_rod(Vector3(side * (RAIL_X + 1.2), top - 1.0, tz), foot, 0.06, cable)
		level._box(Vector3(RAIL_X * 2.0 + 4.0, 1.2, 1.6), Vector3(0, top, tz), _mat_concrete, false)
	level._sign("BAY BRIDGE", Vector3(0, Level.floor_y(z0 - 22.0) + 23.0, z0 - 21.0), Color("ffffff"), 140)


## A box that follows the bridge's gentle slope, at x, raised `lift` above the deck.
func _slope_box(size: Vector3, x: float, lift: float, mat: Material, solid: bool) -> void:
	var z0 := Level.TUN1_END
	var z1 := Level.BRIDGE_END
	var run := absf(z1 - z0)
	var drop := Level.H_TUN1 - Level.H_BRIDGE
	var angle := atan2(drop, run)
	var body := level._box(Vector3(size.x, size.y, sqrt(run * run + drop * drop)),
		Vector3(x, (Level.H_TUN1 + Level.H_BRIDGE) / 2.0 + lift, (z0 + z1) / 2.0), mat, solid) as StaticBody3D
	body.rotation.x = -angle


func _build_water_view() -> void:
	# The bay: one big plane with rolling waves.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	plane.subdivide_width = 140
	plane.subdivide_depth = 140
	water.mesh = plane
	water.material_override = _water_material()
	water.position = Vector3(0, WATER_Y, -320)
	add_child(water)
	# The skyline across the water on both sides, with lit windows.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1600
	for side: float in [-1.0, 1.0]:
		for i in 26:
			var h := rng.randf_range(18.0, 70.0)
			var w := rng.randf_range(10.0, 22.0)
			var x := side * rng.randf_range(230.0, 330.0)
			var z := -150.0 - i * 16.0 + rng.randf_range(-6.0, 6.0)
			var shade := Color("9fb1c4").darkened(rng.randf_range(0.0, 0.35))
			level._box(Vector3(w, h, w), Vector3(x, WATER_Y + h / 2.0, z), Level._material(shade, 0.7), false)
			var glass := Level._material(Color("cfe7ff"), 0.15, 0.6, 0.4)
			level._box(Vector3(w + 0.2, h * 0.7, 0.6), Vector3(x, WATER_Y + h * 0.5, z + w / 2.0), glass, false)
	# A pier with palm trees, like the one off the seawall.
	var pier_z := -300.0
	level._box(Vector3(70, 2.0, 12), Vector3(-95, WATER_Y + 0.6, pier_z), Level._material(Color("d9d2c2"), 0.9), false)
	for i in 7:
		_palm(Vector3(-120.0 + i * 8.0 + 2.0 * sin(i * 2.0), WATER_Y + 1.6, pier_z - 2.0 + 3.0 * cos(i * 1.3)))
	# A boat crossing the bay.
	_boat = Node3D.new()
	add_child(_boat)
	var hull := level._mesh(_boat, null, Vector3.ZERO, Level._material(Color("f4f4f2"), 0.4)) as MeshInstance3D
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(9, 1.6, 3)
	hull.mesh = hull_mesh
	var cabin := level._mesh(_boat, null, Vector3(-1, 1.4, 0), Level._material(Color("2b3a4a"), 0.3, 0.4)) as MeshInstance3D
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(3.5, 1.4, 2.4)
	cabin.mesh = cabin_mesh


func _water_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 deep_color : source_color = vec3(0.04, 0.27, 0.52);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.55, 0.78);
varying float height;
float wave(vec2 p, float t) {
	return sin(p.x * 0.09 + t * 1.1) * 0.35 + sin(p.y * 0.13 + t * 0.8) * 0.25
		+ sin((p.x + p.y) * 0.21 + t * 1.7) * 0.12;
}
void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float h = wave(p, TIME);
	VERTEX.y += h;
	height = h;
	float e = 0.5;
	float hx = wave(p + vec2(e, 0.0), TIME) - h;
	float hz = wave(p + vec2(0.0, e), TIME) - h;
	NORMAL = normalize(vec3(-hx / e, 1.0, -hz / e));
}
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(deep_color, shallow_color, clamp(height * 0.8 + 0.5, 0.0, 1.0));
	ALBEDO = mix(col, vec3(0.75, 0.86, 0.95), fres * 0.5);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _palm(at: Vector3) -> void:
	var trunk := Level._material(Color("8a7356"), 0.9)
	var leaf := Level._material(Color("3f7a35"), 0.8)
	var tip := at + Vector3(0.6, 9.0, 0.0)
	_rod(at, tip, 0.25, trunk)
	for k in 7:
		var a := k * TAU / 7.0
		_rod(tip, tip + Vector3(cos(a) * 3.2, -1.2, sin(a) * 3.2), 0.12, leaf)


# --------------------------------------------------------------- down tunnel 2

func _build_tunnel_two() -> void:
	var z0 := Level.BRIDGE_END
	var z1 := Level.TUN2_END
	_portal(z0, Level.H_BRIDGE, Color("ff3b30"))
	# Street art on the tunnel mouth, facing the riders coming off the bridge.
	var art := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(16, 5)
	art.mesh = quad
	art.material_override = _mural_material(1)
	art.position = Vector3(0, Level.H_BRIDGE + 9.0, z0 + 0.65)
	add_child(art)
	level._tag("TUNNEL RUSH", Vector3(0, Level.H_BRIDGE + 9.0, z0 + 0.7), 0, Color("ffd23f"))
	_ramp(z0, z1, Level.H_BRIDGE, Level.H_TUN2, _mat_wet, Level.DRAG_WET)
	var blocks := _block_material()
	_tube_walls(z0, z1, blocks)
	level._sign("DOWN TUNNEL 2", Vector3(0, Level.H_BRIDGE + 4.0, z0 - 1.0), Color("ff6b5a"), 110)
	var red := Level._material(Color("c8302a"), 0.5, 0.3)
	var z := z0 - 5.0
	var k := 0
	while z > z1 + 3.0:
		var y := Level.floor_y(z)
		var side := -1.0 if k % 2 == 0 else 1.0
		# Fluorescent ceiling light.
		level._box(Vector3(1.6, 0.08, 0.3), Vector3(0, y + 5.4, z), Level._material(Color("f2f6ff"), 0.4, 0.0, 3.0), false)
		var light := OmniLight3D.new()
		light.light_color = Color("e8eeff")
		light.light_energy = 1.4
		light.omni_range = 9.0
		light.position = Vector3(0, y + 4.8, z)
		add_child(light)
		# Red standpipe on the wall, and a yellow wet-floor sign at the edge of the lane.
		_rod(Vector3(side * (HALF - 0.2), y, z - 1.5), Vector3(side * (HALF - 0.2), y + 5.5, z - 1.5), 0.12, red)
		level._box(Vector3(0.3, 0.3, 0.3), Vector3(side * (HALF - 0.35), y + 1.2, z - 1.5), red, false)
		_wet_floor_sign(Vector3(-side * (HALF - 0.5), y, z + 1.0))
		k += 1
		z -= 10.0
	# Handrails down both walls.
	for side: float in [-1.0, 1.0]:
		var top0 := Vector3(side * (HALF - 0.12), Level.floor_y(z0) + 0.95, z0)
		var top1 := Vector3(side * (HALF - 0.12), Level.floor_y(z1) + 0.95, z1)
		_rod(top0, top1, 0.05, _mat_steel)
		var zz := z0 - 3.0
		while zz > z1:
			_rod(Vector3(side * (HALF - 0.05), Level.floor_y(zz) + 0.95, zz),
				Vector3(side * (HALF - 0.12), Level.floor_y(zz) + 0.95, zz), 0.04, _mat_steel)
			zz -= 6.0
	level._wall_sign("DANGER  FLOOR SLIPPERY WHEN WET", Vector3(-HALF + 0.03, Level.floor_y(z0 - 14.0) + 3.0, z0 - 14.0), 1, Color("ff3b30"))
	level._wall_sign("DANGER  FLOOR SLIPPERY WHEN WET", Vector3(HALF - 0.03, Level.floor_y(z0 - 44.0) + 3.0, z0 - 44.0), -1, Color("ff3b30"))
	_mural(Vector3(HALF - 0.03, 0, z0 - 26.0), -1, 3, 8.0)
	level._tag("POPDAT", Vector3(-HALF + 0.04, Level.floor_y(z0 - 32.0) + 2.4, z0 - 32.0), 1, Color("ff4fc8"))
	_portal(z1, Level.H_TUN2, Color("ffd23f"))


func _wet_floor_sign(at: Vector3) -> void:
	var yellow := Level._material(Color("ffd21a"), 0.5)
	for dz: float in [-0.12, 0.12]:
		var panel := level._box(Vector3(0.45, 0.7, 0.03), at + Vector3(0, 0.34, dz), yellow, false) as StaticBody3D
		panel.rotation.x = 0.17 * signf(dz)
	var label := Label3D.new()
	label.text = "CAUTION\nWET FLOOR"
	label.font_size = 28
	label.outline_size = 0
	label.modulate = Color("111111")
	label.position = at + Vector3(0, 0.42, 0.16)
	add_child(label)


func _cone(at: Vector3) -> void:
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.2
	mesh.height = 0.75
	cone.mesh = mesh
	cone.material_override = Level._material(Color("ff4a1a"), 0.5)
	cone.position = at + Vector3(0, 0.4, 0)
	add_child(cone)
	level._box(Vector3(0.42, 0.04, 0.42), at + Vector3(0, 0.02, 0), _mat_dark, false)
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.11
	band_mesh.bottom_radius = 0.14
	band_mesh.height = 0.12
	band.mesh = band_mesh
	band.material_override = Level._material(Color("f2f2f2"), 0.3, 0.0, 0.5)
	band.position = at + Vector3(0, 0.5, 0)
	add_child(band)


# ------------------------------------------------------------------ finish plaza

func _build_plaza() -> void:
	var z0 := Level.TUN2_END
	var z1 := Level.COURSE_END
	var y := Level.H_TUN2
	var pavers := _paver_material()
	var floor := level._box(Vector3(26, 1, absf(z1 - z0) + 1.0), Vector3(0, y - 0.5, (z0 + z1) / 2.0), pavers) as StaticBody3D
	floor.set_meta("drag", Level.DRAG_DRY)
	# Building facades all around (the courtyard), with windows and awnings.
	var facade := Level._material(Color("e6dcc8"), 0.9)
	var window := Level._material(Color("5a6f7d"), 0.2, 0.5)
	var awning := Level._material(Color("1f2a44"), 0.8)
	for side: float in [-1.0, 1.0]:
		level._box(Vector3(2, 24, absf(z1 - z0) + 2.0), Vector3(side * 13.0, y + 12.0, (z0 + z1) / 2.0), facade)
		var z := z0 - 4.0
		while z > z1 + 2.0:
			for floor_n in 4:
				var wy := y + 4.0 + floor_n * 4.5
				level._box(Vector3(0.1, 2.0, 1.6), Vector3(side * 11.95, wy, z), window, false)
				if floor_n > 0:
					level._box(Vector3(0.8, 0.12, 1.9), Vector3(side * 11.6, wy + 1.2, z), awning, false)
			z -= 5.0
	level._box(Vector3(26, 24, 2), Vector3(0, y + 12.0, z1 - 1.0), facade)
	# Round planters with trees and up-lights, keeping the racing lane clear.
	for p: Vector2 in [Vector2(-8.5, z0 - 6.0), Vector2(8.5, z0 - 14.0), Vector2(-8.5, z0 - 24.0), Vector2(8.5, z0 - 30.0)]:
		_planter(Vector3(p.x, y, p.y))
	for p: Vector2 in [Vector2(-5.6, z0 - 10.0), Vector2(5.6, z0 - 20.0), Vector2(-5.6, z0 - 28.0)]:
		_lamp(Vector3(p.x, y, p.y))
	_cone(Vector3(-3.6, y, z0 - 3.0))
	_cone(Vector3(3.6, y, z0 - 3.0))
	# A big swirl mural painted on the pavers past the finish.
	var floor_art := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(9, 9)
	floor_art.mesh = quad
	floor_art.material_override = _mural_material(4)
	floor_art.position = Vector3(0, y + 0.02, Level.FINISH_Z - 6.0)
	add_child(floor_art)


func _planter(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.2
	mesh.bottom_radius = 2.2
	mesh.height = 0.8
	ring.mesh = mesh
	ring.material_override = _mat_concrete
	ring.position = at + Vector3(0, 0.4, 0)
	add_child(ring)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.2
	cyl.height = 0.8
	shape.shape = cyl
	body.add_child(shape)
	body.position = at + Vector3(0, 0.4, 0)
	add_child(body)
	var bush := level._mesh(self, Level._sphere_mesh(2.0), at + Vector3(0, 0.85, 0), Level._material(Color("2f5a2a"), 0.9)) as MeshInstance3D
	bush.scale = Vector3(1, 0.3, 1)
	_rod(at + Vector3(0, 0.8, 0), at + Vector3(0.3, 4.5, 0), 0.18, Level._material(Color("5b4a3a"), 0.9))
	for k in 5:
		var crown := level._mesh(self, Level._sphere_mesh(1.6), at + Vector3(cos(k * 1.3) * 1.2, 5.2 + 0.4 * sin(k * 2.0), sin(k * 1.3) * 1.2),
			Level._material(Color("355f2c").lightened(0.05 * k), 0.85)) as MeshInstance3D
		crown.add_to_group("plaza_trees")
	# Warm up-lights set into the planter wall.
	for k in 3:
		var a := k * TAU / 3.0 + 0.4
		level._box(Vector3(0.18, 0.1, 0.06), at + Vector3(cos(a) * 2.21, 0.3, sin(a) * 2.21), Level._material(Color("ffd08a"), 0.4, 0.0, 3.0), false)


func _lamp(at: Vector3) -> void:
	var post := Level._material(Color("d9dde0"), 0.4, 0.5)
	_rod(at, at + Vector3(0, 5.0, 0), 0.07, post)
	var head := Level._material(Color("f4f8ff"), 0.3, 0.0, 3.0)
	for k in 3:
		var a := k * TAU / 3.0
		_rod(at + Vector3(0, 4.6, 0), at + Vector3(cos(a) * 0.45, 5.6, sin(a) * 0.45), 0.04, head)
	var cap := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.6
	mesh.height = 0.15
	cap.mesh = mesh
	cap.material_override = post
	cap.position = at + Vector3(0, 5.7, 0)
	add_child(cap)


# ------------------------------------------------------------------------ people

func _build_people() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in RUNNERS:
		var side := -1.0 if i % 2 == 0 else 1.0
		var data := Vector4(side, rng.randf_range(4.2, 6.0), rng.randf_range(0.0, 80.0), rng.randf())
		var person := _person(rng, false)
		add_child(person)
		_runners.append(person)
		_runner_data.append(data)
	for i in CHASERS:
		var side := -1.0 if i % 2 == 1 else 1.0
		var zombie := _person(rng, true)
		add_child(zombie)
		_chasers.append(zombie)
		_chaser_data.append(Vector3(side, rng.randf_range(2.6, 3.4), rng.randf_range(0.0, 80.0)))
	for c in CROSSERS:
		var body := AnimatableBody3D.new()
		body.set_meta("pedestrian", true)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.32
		capsule.height = 1.7
		shape.shape = capsule
		shape.position.y = 0.85
		body.add_child(_person(rng, false))
		body.add_child(shape)
		add_child(body)
		_crossers.append(body)


## A person (or a zombie), built from capsules. Child order: 0 left leg, 1 right leg,
## 2 left arm, 3 right arm (pivots), then the body and head.
func _person(rng: RandomNumberGenerator, zombie: bool) -> Node3D:
	var root := Node3D.new()
	var shirts := ["e04a3f", "3f7fe0", "f2c230", "2fb07a", "f2f2f2", "8a4fd0", "ff8a3d", "1d1d1d"]
	var skins := ["8d5a3b", "c68a5e", "e8bf98", "5a3a26", "f1d2b4"]
	var skin := Level._material(Color("7d9471") if zombie else Color(skins[rng.randi() % skins.size()]), 0.8)
	var shirt := Level._material(Color("5c4a3a") if zombie else Color(shirts[rng.randi() % shirts.size()]), 0.9)
	var pants := Level._material(Color("2f3540") if zombie else Color(["2a3550", "4a4a4a", "c9b48a", "1d1d1d"][rng.randi() % 4]), 0.9)
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.12, 0.85, 0)
		root.add_child(hip)
		level._mesh(hip, Level._capsule_mesh(0.1, 0.85), Vector3(0, -0.42, 0), pants)
	for side: float in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.3, 1.45, 0)
		root.add_child(shoulder)
		level._mesh(shoulder, Level._capsule_mesh(0.07, 0.6), Vector3(0, -0.28, 0), skin)
	level._mesh(root, Level._capsule_mesh(0.24, 0.7), Vector3(0, 1.2, 0), shirt)
	level._mesh(root, Level._sphere_mesh(0.2), Vector3(0, 1.72, 0), skin)
	if zombie:
		var eyes := Level._material(Color("ff2a1a"), 0.4, 0.0, 3.0)
		for side: float in [-1.0, 1.0]:
			level._mesh(root, Level._sphere_mesh(0.035), Vector3(side * 0.07, 1.76, -0.18), eyes)
	return root


## Sidewalk runners: they flee down the bridge (the same way the race goes), looping.
func _place_runner(i: int, t: float) -> void:
	var d := _runner_data[i]
	var span := absf(Level.BRIDGE_END - Level.TUN1_END) - 8.0
	var s := fmod(t * d.y + d.z, span)
	var z := Level.TUN1_END - 4.0 - s
	var x := d.x * (HALF + 1.0 + 1.8 * d.w)
	var person := _runners[i]
	person.position = Vector3(x, Level.floor_y(z), z)
	person.rotation.y = 0.0
	person.scale = Vector3.ONE * clampf(minf(s, span - s) / 3.0, 0.01, 1.0)   # fade in/out at the ends
	_animate_legs(person, t * d.y * 1.6 + i, 0.9, false)


## Zombies lurch down the sidewalks after them, arms out.
func _place_chaser(i: int, t: float) -> void:
	var d := _chaser_data[i]
	var span := absf(Level.BRIDGE_END - Level.TUN1_END) - 8.0
	var s := fmod(t * d.y + d.z, span)
	var z := Level.TUN1_END - 4.0 - s
	var zombie := _chasers[i]
	zombie.position = Vector3(d.x * (HALF + 1.6), Level.floor_y(z), z)
	zombie.rotation = Vector3(0, 0, sin(t * 3.0 + i) * 0.1)
	zombie.scale = Vector3.ONE * clampf(minf(s, span - s) / 3.0, 0.01, 1.0)
	_animate_legs(zombie, t * d.y * 1.4 + i, 0.5, true)


## People dashing across the road on a cycle. They block the lane while crossing.
func _place_crosser(i: int, t: float) -> void:
	var c := CROSSERS[i]
	var p := fmod(t + c.y, CROSS_CYCLE)
	var k := clampf(p / CROSS_TIME, 0.0, 1.0)
	var x := c.z * lerpf(-(WALK_OUT - 0.8), WALK_OUT - 0.8, k)
	var body := _crossers[i]
	body.position = Vector3(x, Level.floor_y(c.x), c.x)
	body.rotation.y = -PI / 2.0 * c.z
	var person: Node3D = body.get_child(0)
	_animate_legs(person, t * 9.0 + i, 1.0 if p < CROSS_TIME else 0.0, false)
	var in_lane := absf(x) < HALF + 0.3
	body.collision_layer = 1 if in_lane else 0


func _animate_legs(person: Node3D, phase: float, amount: float, zombie: bool) -> void:
	var swing := sin(phase * 2.0) * 0.8 * amount
	person.get_child(0).rotation.x = swing
	person.get_child(1).rotation.x = -swing
	if zombie:
		person.get_child(2).rotation.x = -PI / 2.0 + 0.1 * sin(phase)
		person.get_child(3).rotation.x = -PI / 2.0 - 0.1 * sin(phase)
	else:
		person.get_child(2).rotation.x = -swing * 1.2
		person.get_child(3).rotation.x = swing * 1.2


# ---------------------------------------------------------------------- helpers

## A floor ramp from (z_from, y_from) to (z_to, y_to), `width` wide, centered at x.
func _ramp(z_from: float, z_to: float, y_from: float, y_to: float, mat: Material, drag: float,
		width := HALF * 2.0, x := 0.0) -> void:
	var run := absf(z_to - z_from)
	var drop := y_from - y_to
	var angle := atan2(drop, run)
	var length := sqrt(run * run + drop * drop) + 0.4
	var normal := Vector3(0, cos(angle), -sin(angle))
	var mid_top := Vector3(x, (y_from + y_to) / 2.0, (z_from + z_to) / 2.0)
	var body := level._box(Vector3(width, 1, length), mid_top - normal * 0.5, mat) as StaticBody3D
	body.rotation.x = -angle
	body.set_meta("drag", drag)


## Side walls and a ceiling that follow a down tunnel's slope.
func _tube_walls(z0: float, z1: float, wall_mat: Material) -> void:
	var run := absf(z1 - z0)
	var y0 := Level.floor_y(z0)
	var y1 := Level.floor_y(z1)
	var drop := y0 - y1
	var angle := atan2(drop, run)
	var length := sqrt(run * run + drop * drop)
	var mid := Vector3(0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)
	for side: float in [-1.0, 1.0]:
		var wall := level._box(Vector3(1, 9, length), mid + Vector3(side * (HALF + 0.5), 3.0, 0), wall_mat) as StaticBody3D
		wall.rotation.x = -angle
	var roof := level._box(Vector3(HALF * 2.0 + 2.0, 1, length), mid + Vector3(0, 6.2, 0), _mat_dark) as StaticBody3D
	roof.rotation.x = -angle


## A tunnel mouth seen from outside: a wide wall with an opening for the lane.
func _portal(z: float, y: float, trim: Color) -> void:
	var stone := _mat_concrete
	level._box(Vector3(30, 14, 1.2), Vector3(0, y + 12.6, z), stone, false)
	for side: float in [-1.0, 1.0]:
		level._box(Vector3(10, 26, 1.2), Vector3(side * (HALF + 5.0), y + 6.0, z), stone, false)
	level._box(Vector3(HALF * 2.0 + 0.6, 0.35, 1.3), Vector3(0, y + 5.7, z), Level._material(trim, 0.4, 0.0, 2.5), false)


## A rod (cylinder) between two points.
func _rod(a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var rod := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 8
	rod.mesh = mesh
	rod.material_override = mat
	add_child(rod)
	var dir := (b - a) / length
	var up := Vector3.UP
	var axis := up.cross(dir)
	var basis := Basis()
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), acos(clampf(up.dot(dir), -1.0, 1.0)))
	elif dir.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	rod.global_transform = Transform3D(basis, (a + b) / 2.0)


## A painted mural on a tunnel wall at x (z, wall side), `length` m long.
func _mural(at: Vector3, facing_x: int, art: int, length: float) -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(length, length * 0.42)
	quad.mesh = mesh
	quad.material_override = _mural_material(art)
	quad.position = Vector3(at.x, Level.floor_y(at.z) + 2.1, at.z)
	quad.rotation.y = PI / 2.0 if facing_x > 0 else -PI / 2.0
	add_child(quad)


# --------------------------------------------------------------------- textures

## Herringbone brick pavers, like the courtyard and the covered walkway.
func _paver_material() -> StandardMaterial3D:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var mortar := Color("4a3d38")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var shades: Array[Color] = []
	for i in 16:
		shades.append(Color("7c5f58").lerp(Color("9a7a70"), rng.randf()).darkened(rng.randf_range(0.0, 0.15)))
	var b := 8                                     # brick width; bricks are 2b x b
	for y in size:
		for x in size:
			# Herringbone: a staircase of horizontal and vertical bricks.
			var u := posmod(x - y, 4 * b)
			var v := posmod(x + y, 4 * b)
			var horizontal := ((x + y) / (2 * b)) % 2 == 0
			var edge := (u % (2 * b) < 1) or (v % (2 * b) < 1) if horizontal else (u % (2 * b) < 1) or (v % b < 1)
			var cell := (int((x + 2 * y) / b) * 7 + int((y + 2 * x) / b) * 3) % shades.size()
			var c := mortar if edge else shades[cell]
			img.set_pixel(x, y, c.darkened(rng.randf_range(0.0, 0.05)))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	mat.roughness = 0.85
	return mat


## Painted cinder blocks, like the stairwell.
func _block_material() -> StandardMaterial3D:
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in h:
		for x in w:
			var row := y / 16
			var xs := (x + (32 if row % 2 == 1 else 0)) % 64
			var joint := (y % 16 < 1) or (xs < 1)
			var base := Color("e7ddba") if y < 40 else Color("d8cfa8")
			img.set_pixel(x, y, base.darkened(0.12 if joint else rng.randf_range(0.0, 0.06)))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	mat.roughness = 0.95
	return mat


## Swirling street-art murals: waves of blue with gold strokes and stars, plus a few
## spray drips. Original art generated from a seed.
func _mural_material(art: int) -> StandardMaterial3D:
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var palettes := [
		[Color("3fa9d9"), Color("9fd8ee"), Color("f2c230"), Color("12202b")],
		[Color("ff4fc8"), Color("35f0ff"), Color("ffd23f"), Color("1a1030")],
		[Color("e04a3f"), Color("f2c230"), Color("3fa9d9"), Color("161616")],
		[Color("4f8fd0"), Color("bfe6ff"), Color("ffcf3a"), Color("0f1a24")],
		[Color("7cff6b"), Color("35f0ff"), Color("ff7a1a"), Color("101414")],
	]
	var pal: Array = palettes[art % palettes.size()]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + art
	# Big swirls.
	for s in 6:
		var cx := rng.randf_range(20, w - 20)
		var cy := rng.randf_range(15, h - 15)
		var turns := rng.randf_range(1.5, 3.0)
		var r_max := rng.randf_range(18, 46)
		var col: Color = pal[s % 3]
		var steps := 900
		for k in steps:
			var f := float(k) / steps
			var a := f * turns * TAU
			var r := f * r_max
			var thick := 2.5 + 5.0 * (1.0 - absf(f - 0.5) * 2.0)
			_dot(img, Vector2(cx + cos(a) * r * 1.6, cy + sin(a) * r), thick, pal[3])
			_dot(img, Vector2(cx + cos(a) * r * 1.6, cy + sin(a) * r), thick - 1.2, col)
	# Flowing ribbons across the whole wall.
	for ribbon in 3:
		var y0 := rng.randf_range(20, h - 20)
		var amp := rng.randf_range(8, 22)
		var freq := rng.randf_range(0.02, 0.05)
		var col: Color = pal[(ribbon + 1) % 3]
		for x in w:
			var y := y0 + sin(x * freq + ribbon) * amp
			_dot(img, Vector2(x, y), 5.0, pal[3])
			_dot(img, Vector2(x, y), 3.6, col)
	# Stars and paint drips.
	for k in 18:
		var p := Vector2(rng.randf_range(0, w), rng.randf_range(0, h))
		_dot(img, p, 1.6, Color("fff6cf"))
	for k in 10:
		var x := rng.randi_range(0, w - 1)
		var y0 := rng.randi_range(h / 2, h - 12)
		for d in rng.randi_range(4, 12):
			_dot(img, Vector2(x, y0 + d), 0.8, pal[k % 3])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _dot(img: Image, at: Vector2, radius: float, col: Color) -> void:
	var r := int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= radius * radius:
				var x := int(at.x) + dx
				var y := int(at.y) + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, col)
