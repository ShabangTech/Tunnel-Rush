extends Node3D
## Big Head Panda: the racer's character, built entirely from code shapes.
## It rides sideways like a real skater (body faces +x, head looks down the course),
## and every peer animates it each frame from the skater's synced state:
## kick, lean, crouch, ollie tuck, landing squash, every flip, spin, grab and style
## trick in the trick book, bail,
## plus a springy big head that wobbles on landings and kicks.

const WHITE := Color("f2efe9")
const BLACK := Color("1b1b1d")
const HIP_Y := 0.72
const LEG_LENGTH := 0.58

var _spin: Node3D        # whole character + board (360s)
var _board: Node3D       # the board alone (kickflips)
var _rig: Node3D         # the panda (lean, bail)
var _upper: Node3D       # everything above the hips (crouch)
var _leg_front: Node3D
var _leg_back: Node3D
var _arm_front: Node3D
var _arm_back: Node3D
var _head: Node3D

var _t := 0.0
var _crouch := 0.0
var _land_squash := 0.0
var _was_air := false
var _lean := 0.0
var _head_angle := Vector2.ZERO
var _head_speed := Vector2.ZERO
var _last_phase := 0.0


func build(board_color: Color) -> void:
	_spin = _node(self, Vector3.ZERO)
	_build_board(board_color)
	_rig = _node(_spin, Vector3.ZERO)
	_upper = _node(_rig, Vector3.ZERO)

	# Legs (pivot at the hip, along the board: front foot at -z).
	_leg_front = _limb(_upper, Vector3(0, HIP_Y, -0.14), 0.09, LEG_LENGTH, BLACK)
	_leg_back = _limb(_upper, Vector3(0, HIP_Y, 0.14), 0.09, LEG_LENGTH, BLACK)

	# Torso: white body with the black shoulder band.
	_part(_upper, _capsule(0.25, 0.66), Vector3(0, 1.02, 0), WHITE)
	var band := _part(_upper, _capsule(0.17, 0.66), Vector3(0, 1.22, 0), BLACK)
	band.rotation.x = PI / 2.0
	_part(_upper, _cylinder(0.2, 0.09), Vector3(0, 1.42, 0), board_color)       # bandana

	# Arms out for balance (pivot at the shoulder).
	_arm_front = _limb(_upper, Vector3(0, 1.24, -0.29), 0.075, 0.5, BLACK)
	_arm_back = _limb(_upper, Vector3(0, 1.24, 0.29), 0.075, 0.5, BLACK)

	# The big head, looking down the course (-z).
	_head = _node(_upper, Vector3(0, 1.46, 0))
	var skull := _part(_head, _sphere(0.44), Vector3(0, 0.4, 0), WHITE)
	skull.scale = Vector3(1.0, 0.94, 0.96)
	for side in [-1.0, 1.0]:
		_part(_head, _sphere(0.14), Vector3(side * 0.31, 0.75, 0.04), BLACK)               # ear
		var patch := _part(_head, _sphere(0.11), Vector3(side * 0.16, 0.44, -0.37), BLACK)  # eye patch
		patch.scale = Vector3(0.9, 1.35, 0.5)
		patch.rotation.z = side * 0.5
		_part(_head, _sphere(0.05), Vector3(side * 0.16, 0.47, -0.43), WHITE)              # eye
		_part(_head, _sphere(0.028), Vector3(side * 0.16, 0.47, -0.475), BLACK)            # pupil
	var muzzle := _part(_head, _sphere(0.16), Vector3(0, 0.27, -0.33), WHITE.lightened(0.3))
	muzzle.scale = Vector3(1.1, 0.8, 0.8)
	var nose := _part(_head, _sphere(0.055), Vector3(0, 0.33, -0.48), BLACK)
	nose.scale = Vector3(1.3, 0.8, 0.8)


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


## s: kick_phase, lean, spin, roll, yaw, pitch, pose, pose_t, air, bail
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


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
