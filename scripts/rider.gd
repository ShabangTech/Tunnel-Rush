extends Node3D
## A Big Head animal rider, built entirely from code shapes: Panda, Zebra, Bear,
## Giraffe, Alligator or Peacock. It rides sideways like a real skater (body faces
## +x, head looks down the course), and every peer animates it each frame from the
## skater's synced state: kick, lean, crouch, ollie tuck, landing squash, every flip,
## spin, grab and style trick in the trick book, bail, power-up effects (turbo flame,
## shield bubble, mega-air glow), plus a springy big head that wobbles on landings
## and kicks.

const ANIMALS: Array[String] = ["Panda", "Zebra", "Bear", "Giraffe", "Alligator", "Peacock"]

const WHITE := Color("f2efe9")
const BLACK := Color("1b1b1d")
const HIP_Y := 0.72
const LEG_LENGTH := 0.58

## Body colors per animal: torso, shoulder band (or null), limbs.
const BODY := {
	"Panda": [Color("f2efe9"), Color("1b1b1d"), Color("1b1b1d")],
	"Zebra": [Color("f4f2ec"), null, Color("f4f2ec")],
	"Bear": [Color("6b4426"), null, Color("5a381f")],
	"Giraffe": [Color("e8b94a"), null, Color("e0b048")],
	"Alligator": [Color("4f7a3a"), null, Color("456b33")],
	"Peacock": [Color("1f5fa8"), null, Color("17406f")],
}

var animal := "Panda"
var head_top := 2.3               # height of the top of the head (for the name tag)

var _spin: Node3D        # whole character + board (360s)
var _board: Node3D       # the board alone (kickflips)
var _rig: Node3D         # the rider (lean, bail)
var _upper: Node3D       # everything above the hips (crouch)
var _leg_front: Node3D
var _leg_back: Node3D
var _arm_front: Node3D
var _arm_back: Node3D
var _head: Node3D
var _fan: Node3D         # peacock tail fan
var _flame: MeshInstance3D
var _bubble: MeshInstance3D
var _air_ring: MeshInstance3D

var _t := 0.0
var _crouch := 0.0
var _land_squash := 0.0
var _was_air := false
var _lean := 0.0
var _head_angle := Vector2.ZERO
var _head_speed := Vector2.ZERO
var _last_phase := 0.0


func build(board_color: Color, animal_name := "Panda") -> void:
	animal = animal_name if BODY.has(animal_name) else "Panda"
	var colors: Array = BODY[animal]
	var torso_color: Color = colors[0]
	var limb_color: Color = colors[2]

	_spin = _node(self, Vector3.ZERO)
	_build_board(board_color)
	_rig = _node(_spin, Vector3.ZERO)
	_upper = _node(_rig, Vector3.ZERO)

	# Legs (pivot at the hip, along the board: front foot at -z).
	_leg_front = _limb(_upper, Vector3(0, HIP_Y, -0.14), 0.09, LEG_LENGTH, limb_color)
	_leg_back = _limb(_upper, Vector3(0, HIP_Y, 0.14), 0.09, LEG_LENGTH, limb_color)

	# Torso, with the animal's markings.
	var torso := _part(_upper, _capsule(0.25, 0.66), Vector3(0, 1.02, 0), torso_color)
	if colors[1] != null:
		var band := _part(_upper, _capsule(0.17, 0.66), Vector3(0, 1.22, 0), colors[1])
		band.rotation.x = PI / 2.0
	_body_markings(torso)
	_part(_upper, _cylinder(0.2, 0.09), Vector3(0, 1.42, 0), board_color)       # bandana

	# Arms out for balance (pivot at the shoulder).
	_arm_front = _limb(_upper, Vector3(0, 1.24, -0.29), 0.075, 0.5, limb_color)
	_arm_back = _limb(_upper, Vector3(0, 1.24, 0.29), 0.075, 0.5, limb_color)

	# The big head, looking down the course (-z).
	_head = _node(_upper, Vector3(0, 1.46, 0))
	match animal:
		"Zebra": _zebra_head()
		"Bear": _bear_head()
		"Giraffe": _giraffe_head()
		"Alligator": _alligator_head()
		"Peacock": _peacock_head()
		_: _panda_head()
	_build_effects()


# -------------------------------------------------------------------- heads

func _panda_head() -> void:
	var skull := _part(_head, _sphere(0.44), Vector3(0, 0.4, 0), WHITE)
	skull.scale = Vector3(1.0, 0.94, 0.96)
	for side in [-1.0, 1.0]:
		_part(_head, _sphere(0.14), Vector3(side * 0.31, 0.75, 0.04), BLACK)               # ear
		var patch := _part(_head, _sphere(0.11), Vector3(side * 0.16, 0.44, -0.37), BLACK)  # eye patch
		patch.scale = Vector3(0.9, 1.35, 0.5)
		patch.rotation.z = side * 0.5
		_eye(Vector3(side * 0.16, 0.47, -0.43), 0.05)
	var muzzle := _part(_head, _sphere(0.16), Vector3(0, 0.27, -0.33), WHITE.lightened(0.3))
	muzzle.scale = Vector3(1.1, 0.8, 0.8)
	var nose := _part(_head, _sphere(0.055), Vector3(0, 0.33, -0.48), BLACK)
	nose.scale = Vector3(1.3, 0.8, 0.8)


func _zebra_head() -> void:
	var skull := _part(_head, _sphere(0.4), Vector3(0, 0.42, 0), WHITE)
	skull.scale = Vector3(0.9, 1.0, 1.1)
	# Stripes: thin black rings that hug the skull at different heights.
	for i in 7:
		var h := -0.3 + i * 0.1
		var ring := _part(skull, _cylinder(sqrt(maxf(0.16 - h * h, 0.0)) + 0.008, 0.035), Vector3(0, h, 0), BLACK)
		ring.rotation.x = 0.25 * (1 if i % 2 == 0 else -1)
	var snout := _part(_head, _capsule(0.15, 0.5), Vector3(0, 0.24, -0.4), Color("2b2b2e"))
	snout.rotation.x = PI / 2.0 - 0.35
	for side in [-1.0, 1.0]:
		_part(_head, _sphere(0.035), Vector3(side * 0.07, 0.17, -0.62), BLACK)            # nostril
		_eye(Vector3(side * 0.24, 0.52, -0.26), 0.055)
		var ear := _part(_head, _cone(0.08, 0.26), Vector3(side * 0.22, 0.86, 0.05), WHITE)
		ear.rotation.z = -side * 0.35
		_part(ear, _cone(0.05, 0.1), Vector3(0, 0.1, 0), BLACK)                          # ear tip
	# Mohawk mane from forehead to neck.
	for i in 7:
		var tuft := _part(_head, _box(Vector3(0.05, 0.16, 0.08)), Vector3(0, 0.82 - i * 0.03, -0.12 + i * 0.09), BLACK if i % 2 == 0 else WHITE)
		tuft.rotation.x = 0.2 + i * 0.12
	head_top = 2.45


func _bear_head() -> void:
	var fur := Color("6b4426")
	var tan := Color("c9a06a")
	var skull := _part(_head, _sphere(0.45), Vector3(0, 0.4, 0), fur)
	skull.scale = Vector3(1.05, 0.95, 0.95)
	for side in [-1.0, 1.0]:
		_part(_head, _sphere(0.13), Vector3(side * 0.32, 0.76, 0.02), fur)                # ear
		var inner := _part(_head, _sphere(0.075), Vector3(side * 0.32, 0.76, -0.07), tan)
		inner.scale = Vector3(1.0, 1.0, 0.4)
		_eye(Vector3(side * 0.15, 0.5, -0.4), 0.045)
	var muzzle := _part(_head, _sphere(0.19), Vector3(0, 0.27, -0.33), tan)
	muzzle.scale = Vector3(1.1, 0.85, 0.95)
	var nose := _part(_head, _sphere(0.07), Vector3(0, 0.34, -0.51), BLACK)
	nose.scale = Vector3(1.4, 0.9, 0.8)


func _giraffe_head() -> void:
	var hide := Color("e8b94a")
	var spot := Color("8a4f1f")
	# A long neck lifts the big head up.
	var neck := _part(_head, _capsule(0.13, 0.8), Vector3(0, 0.3, 0.02), hide)
	for i in 4:
		var s := _part(neck, _sphere(0.06), Vector3(0.11 * (1 if i % 2 == 0 else -1), -0.2 + i * 0.13, -0.06), spot)
		s.scale = Vector3(0.4, 1.0, 1.0)
	var skull := _part(_head, _sphere(0.36), Vector3(0, 0.86, -0.05), hide)
	skull.scale = Vector3(0.9, 0.95, 1.15)
	var spots := [Vector3(0.2, 0.15, 0.12), Vector3(-0.22, 0.05, 0.1), Vector3(0.1, 0.25, 0.25),
		Vector3(-0.12, 0.28, 0.2), Vector3(0.25, -0.05, -0.1), Vector3(-0.26, -0.08, -0.05)]
	for v in spots:
		var d: Vector3 = (v as Vector3).normalized() * 0.355
		var s := _part(skull, _sphere(0.07), d, spot)
		s.basis = Basis.looking_at(d, Vector3.UP)                              # flat against the skull
		s.scale = Vector3(1.0, 1.0, 0.35)
	var muzzle := _part(_head, _capsule(0.15, 0.36), Vector3(0, 0.74, -0.38), Color("f0d08a"))
	muzzle.rotation.x = PI / 2.0
	for side in [-1.0, 1.0]:
		_part(_head, _sphere(0.03), Vector3(side * 0.06, 0.74, -0.56), spot)              # nostril
		_eye(Vector3(side * 0.22, 0.95, -0.2), 0.05)
		var ear := _part(_head, _cone(0.06, 0.2), Vector3(side * 0.33, 1.04, 0.02), hide)
		ear.rotation.z = -side * 1.1
		var horn := _part(_head, _cylinder(0.03, 0.22), Vector3(side * 0.12, 1.25, 0.02), hide)
		horn.rotation.z = -side * 0.15
		_part(horn, _sphere(0.055), Vector3(0, 0.12, 0), spot)                            # ossicone tip
	head_top = 3.0


func _alligator_head() -> void:
	var scales := Color("4f7a3a")
	var belly := Color("b9c77a")
	var skull := _part(_head, _sphere(0.4), Vector3(0, 0.36, 0.05), scales)
	skull.scale = Vector3(1.0, 0.75, 1.0)
	# Long flat snout with a lower jaw and teeth.
	_part(_head, _box(Vector3(0.36, 0.14, 0.62)), Vector3(0, 0.32, -0.5), scales)
	_part(_head, _box(Vector3(0.32, 0.08, 0.58)), Vector3(0, 0.2, -0.48), belly)
	for side in [-1.0, 1.0]:
		for i in 6:
			var tooth := _part(_head, _cone(0.022, 0.06), Vector3(side * 0.16, 0.235, -0.27 - i * 0.09), WHITE)
			tooth.rotation.x = PI
		_part(_head, _sphere(0.04), Vector3(side * 0.07, 0.4, -0.78), scales.darkened(0.2))  # nostril bump
		# Eyes sit in bumps on top of the head.
		_part(_head, _sphere(0.11), Vector3(side * 0.15, 0.6, -0.12), scales)
		_part(_head, _sphere(0.07), Vector3(side * 0.15, 0.63, -0.19), Color("e8d43a"))
		_part(_head, _box(Vector3(0.012, 0.09, 0.02)), Vector3(side * 0.15, 0.63, -0.255), BLACK)  # slit pupil
	# Ridges down the back of the head.
	for i in 4:
		_part(_head, _cone(0.04, 0.08), Vector3(0, 0.62 - i * 0.04, 0.1 + i * 0.1), scales.darkened(0.25))
	head_top = 2.25


func _peacock_head() -> void:
	var blue := Color("1f5fa8")
	var skull := _part(_head, _sphere(0.36), Vector3(0, 0.4, 0), blue)
	skull.scale = Vector3(0.95, 1.05, 1.0)
	var beak := _part(_head, _cone(0.08, 0.26), Vector3(0, 0.34, -0.42), Color("d9b76a"))
	beak.rotation.x = -PI / 2.0
	for side in [-1.0, 1.0]:
		var patch := _part(_head, _sphere(0.08), Vector3(side * 0.17, 0.46, -0.27), WHITE)
		patch.scale = Vector3(1.0, 0.6, 0.5)
		_eye(Vector3(side * 0.17, 0.47, -0.31), 0.04)
	# Crest: five thin stalks with blue-green tips.
	for i in 5:
		var a := (i - 2) * 0.22
		var stalk := _part(_head, _cylinder(0.012, 0.3), Vector3(sin(a) * 0.12, 0.85, -0.02 + absf(a) * 0.05), Color("2b6e5f"))
		stalk.rotation.z = -a * 0.9
		_part(stalk, _sphere(0.04), Vector3(0, 0.16, 0), Color("27c2a0"))
	# The tail fan, behind the rider at the tail of the board, fanned out like a peacock.
	_fan = _node(_upper, Vector3(0, 0.95, 0.32))
	var feathers := 13
	for i in feathers:
		var a := lerpf(-1.25, 1.25, float(i) / (feathers - 1))
		var pivot := _node(_fan, Vector3.ZERO)
		pivot.rotation = Vector3(0.55, 0.0, -a)          # leans back, out of the camera's way
		var length := 0.85 - absf(a) * 0.1
		_part(pivot, _box(Vector3(0.05, length, 0.012)), Vector3(0, length / 2.0, 0), Color("2e8b57"))
		var tip := _node(pivot, Vector3(0, length, 0))
		var outer := _part(tip, _sphere(0.11), Vector3.ZERO, Color("c9a227"))
		outer.scale = Vector3(1.0, 1.35, 0.2)
		for face in [-1.0, 1.0]:                               # the eye shows from both sides
			var mid := _part(tip, _sphere(0.075), Vector3(0, 0.0, 0.012 * face), Color("1c9c8f"))
			mid.scale = Vector3(1.0, 1.3, 0.2)
			var core := _part(tip, _sphere(0.045), Vector3(0, 0.0, 0.024 * face), Color("1a2a8c"))
			core.scale = Vector3(1.0, 1.25, 0.2)
	head_top = 2.35


func _eye(pos: Vector3, radius: float) -> void:
	_part(_head, _sphere(radius), pos, WHITE)
	_part(_head, _sphere(radius * 0.56), pos + Vector3(0, 0, -radius * 0.9), BLACK)


func _body_markings(torso: MeshInstance3D) -> void:
	match animal:
		"Zebra":
			for i in 6:
				var ring := _part(torso, _cylinder(0.258, 0.04), Vector3(0, -0.2 + i * 0.09, 0), BLACK)
				ring.rotation.x = 0.3 * (1 if i % 2 == 0 else -1)
		"Giraffe":
			var spots := [Vector3(1, 0.1, 0.3), Vector3(1, -0.15, -0.3), Vector3(-1, 0.05, 0.2),
				Vector3(0.3, 0.2, 1), Vector3(-0.3, -0.1, -1), Vector3(0.6, -0.2, 0.8)]
			for v in spots:
				var d: Vector3 = (v as Vector3).normalized()
				var s := _part(torso, _sphere(0.08), Vector3(d.x * 0.245, d.y * 0.3, d.z * 0.245), Color("8a4f1f"))
				s.basis = Basis.looking_at(Vector3(d.x, 0, d.z), Vector3.UP)
				s.scale = Vector3(1.0, 1.0, 0.3)
		"Bear", "Alligator":
			var belly := _part(torso, _sphere(0.2), Vector3(0.12, -0.05, 0), Color("c9a06a") if animal == "Bear" else Color("b9c77a"))
			belly.scale = Vector3(0.6, 1.3, 1.0)
		"Peacock":
			var chest := _part(torso, _sphere(0.2), Vector3(0.1, 0.1, 0), Color("1c9c8f"))
			chest.scale = Vector3(0.7, 1.2, 1.0)


# ------------------------------------------------------------------ effects

func _build_effects() -> void:
	_flame = MeshInstance3D.new()
	_flame.mesh = _cone(0.14, 0.7)
	_flame.material_override = _glow(Color("ff7a1a"), 0.85)
	_flame.rotation.x = PI / 2.0
	_flame.position = Vector3(0, 0.14, 0.75)
	_flame.visible = false
	_spin.add_child(_flame)

	_bubble = MeshInstance3D.new()
	_bubble.mesh = _sphere(1.25)
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.albedo_color = Color(0.3, 0.85, 1.0, 0.18)
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.emission_enabled = true
	bubble_mat.emission = Color("35d0ff")
	bubble_mat.emission_energy_multiplier = 0.6
	bubble_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bubble.material_override = bubble_mat
	_bubble.position.y = 1.15
	_bubble.visible = false
	add_child(_bubble)

	_air_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.52
	_air_ring.mesh = ring
	_air_ring.material_override = _glow(Color("c46bff"), 1.0)
	_air_ring.position.y = 0.05
	_air_ring.visible = false
	_spin.add_child(_air_ring)


## Trick poses. Each: arm_front / arm_back rotation (x swing, z out), leg_front /
## leg_back swing (x), crouch 0..1, board tilt (x) and how far the board is pulled
## toward a hand (y offset). Style tricks (11+) also animate over pose_t.
const POSES := {
	1: {"af": Vector2(0.2, 0.2), "ab": Vector2(-1.2, 1.2), "crouch": 0.85, "board_y": 0.12},   # Indy
	2: {"af": Vector2(1.4, 0.6), "ab": Vector2(-0.9, 0.3), "crouch": 0.8, "tilt": 0.45},       # Nosegrab
	3: {"af": Vector2(0.4, -1.1), "ab": Vector2(-0.8, 0.3), "crouch": 0.8, "board_y": 0.1},    # Melon
	4: {"af": Vector2(0.9, 0.3), "ab": Vector2(-1.4, 0.6), "crouch": 0.8, "tilt": -0.45},      # Tailgrab
	5: {"af": Vector2(0.3, -1.2), "ab": Vector2(-1.0, 0.8), "crouch": 0.6, "tilt": -0.3, "board_y": 0.35, "lb": 0.9},  # Method
	6: {"af": Vector2(0.9, 0.4), "ab": Vector2(-0.5, -1.3), "crouch": 0.85, "board_y": 0.1},   # Stalefish
	7: {"af": Vector2(1.2, 0.2), "ab": Vector2(1.0, -0.2), "crouch": 0.2, "tilt": -1.3, "board_y": 0.45},  # Rocket Air
	8: {"af": Vector2(0.4, 0.8), "ab": Vector2(-1.0, 0.4), "crouch": 0.5, "lb": -1.1},          # Benihana
	9: {"af": Vector2(0.5, 1.0), "ab": Vector2(-1.4, 0.3), "crouch": 0.5, "lf": 1.0, "tilt": -0.35},  # Madonna
	10: {"af": Vector2(0.3, 1.6), "ab": Vector2(-0.3, 1.6), "crouch": 0.1, "board_y": 0.5, "tilt": 0.3},  # Christ Air
	11: {"af": Vector2(1.2, 0.3), "ab": Vector2(-1.2, 0.3), "lf": 0.9, "lb": -0.9, "crouch": 0.2},  # Airwalk
	12: {"af": Vector2(1.0, 0.6), "ab": Vector2(-0.8, 0.4), "lf": 1.1, "crouch": 0.3, "tilt": -0.3},  # Ollie North
	13: {"af": Vector2(2.6, 0.2), "ab": Vector2(-0.6, 0.4), "lf": 1.2, "crouch": 0.4},          # Judo
	14: {"af": Vector2(0.7, 0.4), "ab": Vector2(-0.7, 0.4), "crouch": 0.4, "body_spin": true},  # Body Varial
	15: {"af": Vector2(2.9, 0.1), "ab": Vector2(2.9, -0.1), "lf": -0.6, "lb": -1.2, "crouch": 0.0, "board_y": 0.2, "lay": true},  # Superman
}


## s: kick_phase, lean, spin, roll, yaw, pitch, pose, pose_t, air, bail,
##    turbo, shield, mega_air
func animate(delta: float, s: Dictionary) -> void:
	_t += delta
	_spin.rotation.y = s.spin
	var pose: Dictionary = POSES.get(s.pose, {})
	var pose_t: float = s.pose_t
	var style_curve := sin(pose_t * PI) if s.pose >= 11 else 1.0   # style tricks go out and back
	var follow := clampf(delta * 14.0, 0.0, 1.0)

	# Board: flips plus any grab tilt / pull toward the hand.
	_board.rotation = Vector3(s.pitch + pose.get("tilt", 0.0) * style_curve, s.yaw, s.roll)
	_board.position.y = lerpf(_board.position.y, 0.12 + pose.get("board_y", 0.0) * style_curve, follow)

	# Landing: squash the body and bump the head.
	var air: bool = s.air
	if _was_air and not air:
		_land_squash = 0.28
		_head_speed.x += 4.0
	_was_air = air
	_land_squash = maxf(_land_squash - delta, 0.0)

	# Crouch: tuck in the air (or the pose's crouch), squash on landing.
	var target := 0.0
	if air:
		target = lerpf(0.45, pose.get("crouch", 0.45), style_curve) if not pose.is_empty() else 0.45
	target = maxf(target, _land_squash / 0.28 * 0.7)
	_crouch = lerpf(_crouch, target, follow)
	var drop := _crouch * 0.22
	_upper.position.y = -drop + sin(_t * 2.6) * 0.008
	var flipping: bool = absf(s.roll) + absf(s.pitch) + absf(s.yaw) > 0.01
	_rig.position.y = lerpf(_rig.position.y, 0.2 if air and flipping else 0.0, follow)

	# Kick: the back foot swings down and back, then returns.
	var phase: float = s.kick_phase
	var swing := sin(phase * PI) if phase > 0.0 else 0.0
	if phase > 0.0 and _last_phase == 0.0:
		_head_speed.x += 1.2
	_last_phase = phase

	# Legs: kick swing, or the trick pose.
	var leg_front_x: float = pose.get("lf", 0.0) * style_curve
	var leg_back_x: float = pose.get("lb", 0.0) * style_curve - swing * 0.75
	_leg_front.rotation.x = lerpf(_leg_front.rotation.x, leg_front_x, follow)
	_leg_back.rotation.x = lerpf(_leg_back.rotation.x, leg_back_x, follow)
	for leg in [_leg_front, _leg_back]:
		leg.scale.y = (LEG_LENGTH - drop) / LEG_LENGTH
	_leg_back.scale.y *= 1.0 + swing * 0.12

	# Arms: balance, or the trick pose.
	var sway := sin(_t * 2.0) * 0.08
	var af: Vector2 = pose.get("af", Vector2(0.7 + sway, 0.25))
	var ab: Vector2 = pose.get("ab", Vector2(-0.7 + sway + swing * 0.4, 0.25))
	_arm_front.rotation.x = lerpf(_arm_front.rotation.x, af.x, follow)
	_arm_front.rotation.z = lerpf(_arm_front.rotation.z, af.y, follow)
	_arm_back.rotation.x = lerpf(_arm_back.rotation.x, ab.x, follow)
	_arm_back.rotation.z = lerpf(_arm_back.rotation.z, ab.y, follow)

	# Lean into turns; Superman lays flat; Body Varial spins the panda over the board.
	_lean = lerpf(_lean, s.lean, clampf(delta * 8.0, 0.0, 1.0))
	_rig.rotation.z = _lean
	_rig.rotation.y = pose_t * TAU if pose.get("body_spin", false) else 0.0
	var lay := -1.2 * style_curve if pose.get("lay", false) else 0.0

	# Bail: wobble and tip over for a moment.
	var bail: float = s.bail
	_rig.rotation.x = (sin(bail * 22.0) * 0.35 * bail if bail > 0.0 else 0.0) + lay

	# The big head: a spring that wobbles, and it looks into the turn.
	var stiffness := 70.0
	var damping := 7.0
	_head_speed += (-_head_angle * stiffness - _head_speed * damping) * delta
	_head_angle += _head_speed * delta
	_head.rotation.x = clampf(_head_angle.x, -0.5, 0.5) * 0.4
	_head.rotation.z = clampf(_head_angle.y + _lean * 0.6, -0.5, 0.5)
	_head.rotation.y = -_lean * 0.8

	# Peacock fan: spreads wide in the air, sways with the lean and the head.
	if _fan:
		var spread := 1.15 if air else 1.0
		_fan.scale = _fan.scale.lerp(Vector3(spread, spread, 1.0), follow)
		_fan.rotation.z = -_lean * 0.6 + sin(_t * 3.0) * 0.04
		_fan.rotation.x = -clampf(_head_angle.x, -0.5, 0.5) * 0.3

	# Power-up effects.
	_flame.visible = s.get("turbo", false)
	if _flame.visible:
		_flame.scale = Vector3(1.0, 0.8 + 0.35 * absf(sin(_t * 31.0)), 1.0)
	_bubble.visible = s.get("shield", false)
	if _bubble.visible:
		_bubble.scale = Vector3.ONE * (1.0 + 0.03 * sin(_t * 6.0))
	_air_ring.visible = s.get("mega_air", false)
	if _air_ring.visible:
		_air_ring.rotation.y += delta * 4.0


# ------------------------------------------------------------------- shapes

func _build_board(board_color: Color) -> void:
	_board = _node(_spin, Vector3(0, 0.12, 0))
	_part(_board, _box(Vector3(0.28, 0.05, 0.9)), Vector3.ZERO, board_color)
	_part(_board, _box(Vector3(0.27, 0.01, 0.86)), Vector3(0, 0.03, 0), Color("101010"))   # grip tape
	for z in [-0.3, 0.3]:
		_part(_board, _box(Vector3(0.2, 0.04, 0.06)), Vector3(0, -0.045, z), Color("9aa0a6"))  # truck
		for x in [-0.11, 0.11]:
			var wheel := _part(_board, _cylinder(0.035, 0.04), Vector3(x, -0.08, z), Color("f4f1de"))
			wheel.rotation.z = PI / 2.0


func _limb(parent: Node3D, pivot: Vector3, radius: float, length: float, color: Color) -> Node3D:
	var joint := _node(parent, pivot)
	_part(joint, _capsule(radius, length), Vector3(0, -length / 2.0, 0), color)
	return joint


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	part.material_override = mat
	part.position = pos
	parent.add_child(part)
	return part


static func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 24
	m.rings = 12
	return m


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	return m


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	return m


static func _cone(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = radius
	m.height = height
	return m


static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = energy
	return mat


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
