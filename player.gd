extends CharacterBody3D

# --- Constants ---
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003
const THROW_BASE_FORCE = 10.0
const MAX_CHARGE = 2.0
const CHARGE_STEP = 0.15  # How much each scroll changes charge
const SPRINT_SPEED_MULTIPLIER = 2.0

# Wind-up animation constants
const WINDUP_SIDE_OFFSET = 0.4
const WINDUP_HEIGHT_OFFSET = 0.1
const WINDUP_PULLBACK = 0.2
const WINDUP_WRIST_TWIST = 90

# Carry position (lower right, out of crosshair)
const CARRY_OFFSET = Vector3(0.3, -0.2, -0.4)  # Right, Down, Back

# Upward throw values
const UPWARD_LOB = 0.5
const UPWARD_TOSS = 0.1

# --- Nodes ---
@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var ray = $Head/Camera3D/InteractionRay
@onready var hand = $Head/Camera3D/Hand
@onready var crosshair = $HUD/Crosshair
@onready var trajectory_predictor = $TrajectoryLine

# --- State ---
var held_object: RigidBody3D = null
var throw_charge = 0.0  # Now persistent until thrown

# Object property storage
var original_state = {}

# --- Core Loops ---

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(_delta):
	update_visuals()

func _physics_process(delta):
	handle_movement(delta)
	update_trajectory_display()
	move_and_slide()

# --- Input Handling ---

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotate_camera(event.relative)

	# Left Click: Pick up OR Throw
	if event.is_action_pressed("mouse1"):
		if held_object:
			execute_throw()
		else:
			pick_up_object()

	# Mouse Wheel: Adjust throw power
	if event is InputEventMouseButton:
		if held_object:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				adjust_charge(CHARGE_STEP)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				adjust_charge(-CHARGE_STEP)

func rotate_camera(relative):
	head.rotate_y(-relative.x * SENSITIVITY)
	camera.rotate_x(-relative.y * SENSITIVITY)
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

# --- Interaction Logic ---

func pick_up_object():
	if not ray.is_colliding(): return
	var obj = ray.get_collider()

	if obj is RigidBody3D:
		hold_object(obj)

func hold_object(obj):
	held_object = obj
	throw_charge = 1.0  # Start at half power
	
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
	# Position object to the lower right, out of crosshair view
	obj.position = CARRY_OFFSET
	obj.linear_velocity = Vector3.ZERO

func release_object() -> RigidBody3D:
	if not held_object: return null
	var obj = held_object
	obj.reparent(get_tree().current_scene)
	obj.global_position = hand.global_position

	# Restore physics
	obj.collision_layer = original_state.layer
	obj.collision_mask = original_state.mask
	obj.mass = original_state.mass
	obj.freeze_mode = original_state.freeze
	obj.freeze = false
	obj.sleeping = false

	held_object = null
	original_state.clear()
	return obj

# --- Throwing Logic ---

func adjust_charge(delta: float):
	throw_charge = clamp(throw_charge + delta, 0.0, MAX_CHARGE)

func update_trajectory_display():
	if held_object:
		# Continuously show trajectory based on current charge
		trajectory_predictor.update_path(
			hand.global_position, 
			calculate_throw_velocity(), 
			get_gravity().y, 
			0.05, 
			held_object
		)
	else:
		trajectory_predictor.clear()

func execute_throw():
	if not held_object: return
	
	var impulse = calculate_throw_velocity()
	var obj = release_object()
	obj.apply_central_impulse(impulse)
	
	# Reset charge for next pickup
	throw_charge = 0.0

func calculate_throw_velocity() -> Vector3:
	var dir = -camera.global_transform.basis.z
	var force = max(THROW_BASE_FORCE * throw_charge, 5.0)
	var upward = UPWARD_LOB if camera.rotation.x < 0 else UPWARD_TOSS  # Lob vs Toss
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
	if held_object:
		# Charge ratio (0.0 to 1.0)
		var ratio = throw_charge / MAX_CHARGE
		
		# --- 1. Ball Orientation Correction ---
		var target_rotation = Basis.IDENTITY
		held_object.basis = held_object.basis.slerp(target_rotation, ratio)

		# --- 2. Hand Position (The Wind-up) ---
		# Interpolate from carry position to wind-up position
		var windup_pos = Vector3(
			CARRY_OFFSET.x + (ratio * WINDUP_SIDE_OFFSET),      # More to the right
			CARRY_OFFSET.y + (ratio * WINDUP_HEIGHT_OFFSET),    # Raises up
			CARRY_OFFSET.z + (ratio * WINDUP_PULLBACK)          # Pulls back
		)
		hand.position = hand.position.lerp(windup_pos, 0.15)
		
		# --- 3. Hand Rotation (The Cocking Motion) ---
		hand.rotation.y = deg_to_rad(ratio * WINDUP_WRIST_TWIST)
		hand.rotation.x = deg_to_rad(ratio * -2)
		
		# --- 4. UI Feedback ---
		crosshair.scale = Vector2.ONE * (1.0 + ratio)
		crosshair.color = Color(1, 1 - ratio, 0)  # Yellow to red gradient
	else:
		# Smoothly return to idle position
		hand.position = hand.position.lerp(CARRY_OFFSET, 0.2)
		hand.rotation = hand.rotation.lerp(Vector3.ZERO, 0.2)
		
		# Reset crosshair
		crosshair.scale = Vector2.ONE
		crosshair.color = Color.RED if ray.is_colliding() else Color.WHITE
