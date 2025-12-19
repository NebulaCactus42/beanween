extends CharacterBody3D

# --- Constants ---
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003
const THROW_BASE_FORCE = 10.0
const MAX_CHARGE = 2.0
const CHARGE_RATE = 2
const SPRINT_SPEED_MULTIPLIER = 2.0

# --- Nodes ---
@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var ray = $Head/Camera3D/InteractionRay
@onready var hand = $Head/Camera3D/Hand
@onready var crosshair = $HUD/Crosshair
@onready var trajectory_predictor = $TrajectoryLine

# --- State ---
var held_object: RigidBody3D = null
var is_charging_throw = false
var throw_charge = 0.0
var trajectory_line: ImmediateMesh = null

# Object property storage
var original_state = {}

# --- Core Loops ---

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(_delta):
	update_visuals()

func _physics_process(delta):
	handle_movement(delta)
	handle_throwing_logic(delta)
	move_and_slide()

# --- Input Handling ---

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotate_camera(event.relative)

	if event.is_action_pressed("mouse1"):
		if held_object: start_charging()
		else: pick_up_object()

	elif event.is_action_released("mouse1"):
		if is_charging_throw: execute_throw()

func rotate_camera(relative):
	head.rotate_y(-relative.x * SENSITIVITY)
	camera.rotate_x(-relative.y * SENSITIVITY)
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

# --- Interaction Logic ---

func pick_up_object():
	if not ray.is_colliding(): return
	var obj = ray.get_collider()

	if obj is RigidBody3D and obj != get_last_slide_collision():
		hold_object(obj)

func hold_object(obj):
	held_object = obj
	# Store state for restoration
	original_state = {
		"layer": obj.collision_layer,
		"mask": obj.collision_mask,
		"mass": obj.mass,
		"freeze": obj.freeze_mode
	}

	obj.freeze = true
	obj.collision_layer = 0
	obj.collision_mask = 0
	obj.reparent(hand)
	obj.position = Vector3.ZERO
	obj.linear_velocity = Vector3.ZERO

func release_object() -> RigidBody3D:
	var obj = held_object
	obj.reparent(get_tree().current_scene)

	# Restore physics
	obj.collision_layer = original_state.layer
	obj.collision_mask = original_state.mask
	obj.mass = original_state.mass
	obj.freeze_mode = original_state.freeze
	obj.freeze = false
	obj.sleeping = false

	held_object = null
	return obj

# --- Throwing Logic ---

func start_charging():
	is_charging_throw = true
	throw_charge = 0.0

func handle_throwing_logic(delta):
	if is_charging_throw and held_object:
		throw_charge = min(throw_charge + CHARGE_RATE * delta, MAX_CHARGE)
		
		# Pass global hand position and the calculated velocity
		trajectory_predictor.update_path(hand.global_position, calculate_throw_velocity(), -9.8, 0.05, held_object)
	else:
		trajectory_predictor.clear()
		clear_trajectory()

func execute_throw():
	var impulse = calculate_throw_velocity()
	var obj = release_object()
	obj.apply_central_impulse(impulse)
	is_charging_throw = false

func calculate_throw_velocity() -> Vector3:
	var dir = -camera.global_transform.basis.z
	var force = max(THROW_BASE_FORCE * throw_charge, 5.0)
	var upward = 0.5 if camera.rotation.x < 0 else 0.1 # Lob vs Toss
	return (dir * force) + (Vector3.UP * force * upward)

# --- Movement & Physics Helpers ---

func handle_movement(delta):
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		var current_speed = SPEED
		if Input.is_action_pressed("sprint"):
			current_speed *= SPRINT_SPEED_MULTIPLIER
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

# --- Visuals ---

func update_visuals():
	if is_charging_throw and held_object:
		# ratio goes from 0.0 to 1.0 as the throw charges
		var ratio = throw_charge / MAX_CHARGE
		
		# --- 1. Ball Orientation Correction ---
		# We want the ball to face 'forward' (90 deg) regardless of how it was grabbed.
		# Adjust 'Vector3.UP' or '90' if your model's nose points a different way.
		var target_rotation = Basis().rotated(Vector3.UP, deg_to_rad(0))
		held_object.basis = held_object.basis.slerp(target_rotation, ratio)

		# --- 2. Hand Position (The Wind-up) ---
		# Default resting position is (0, 0, -0.4)
		hand.position.x = ratio * 0.4         # Shifts slightly right (sidearm)
		hand.position.y = ratio * 0.1         # Raises ball toward eye level
		hand.position.z = -0.4 + (ratio * 0.2) # Pulls back toward the player (lower = less pullback)
		
		# --- 3. Hand Rotation (The Cocking Motion) ---
		hand.rotation.y = deg_to_rad(ratio * 90) # Twists wrist outward
		hand.rotation.x = deg_to_rad(ratio * 0) # Tilts nose of the ball up slightly
		
		# --- 4. UI Feedback ---
		crosshair.scale = Vector2.ONE * (1.0 + ratio)
		crosshair.color = Color(1, 1 - ratio, 0) # Fades from yellow to red
	else:
		# Smoothly interpolate back to the default "carrying" position when not charging
		hand.position = hand.position.lerp(Vector3(0, 0, -0.4), 0.2)
		hand.rotation = hand.rotation.lerp(Vector3.ZERO, 0.2)
		
		# Reset Crosshair
		crosshair.scale = Vector2.ONE
		crosshair.color = Color.RED if ray.is_colliding() else Color.WHITE


# --- Trajectory (Simplified for refactor) ---

func update_trajectory():
	var start_pos = hand.global_position
	var initial_vel = calculate_throw_velocity()
	var gravity = get_gravity()
	trajectory_predictor.update_path(start_pos, initial_vel, gravity)

func clear_trajectory():

	trajectory_predictor.clear()
