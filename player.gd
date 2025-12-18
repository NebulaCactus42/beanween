extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var ray = $Head/Camera3D/InteractionRay
@onready var crosshair = $HUD/Crosshair
@onready var hand = $Head/Camera3D/Hand
var held_object = null
var original_mass = 1.0
var original_freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
var original_collision_layer = 1
var original_collision_mask = 1

func _process(_delta):
	if ray.is_colliding():
		crosshair.color = Color(1, 0, 0) # Red when looking at something
	else:
		crosshair.color = Color(1, 1, 1, 0.8) # Default white

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

	if event.is_action_pressed("ui_select"): # Space or custom "Interact"
		if held_object:
			drop_object()
		else:
			pick_up_object()

func _physics_process(delta):
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func pick_up_object():
	if ray.is_colliding():
		var obj = ray.get_collider()
		if obj is RigidBody3D:
			# Prevent picking up objects we're standing on
			if obj == get_last_slide_collision():
				print("Can't pick up object you're standing on")
				return

			held_object = obj

			# Store original properties for later restoration
			original_mass = held_object.mass
			original_freeze_mode = held_object.freeze_mode
			original_collision_layer = held_object.collision_layer
			original_collision_mask = held_object.collision_mask

			# COMPLETE PHYSICS ISOLATION APPROACH
			# Disable all physics processing for the held object
			held_object.mass = 0.01
			held_object.freeze = true
			held_object.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			held_object.sleeping = true

			# Disable collision layers to prevent ANY physics interaction
			held_object.collision_layer = 0
			held_object.collision_mask = 0

			held_object.reparent(hand)
			held_object.position = Vector3.ZERO # Snap to hand center

			# Reset any residual forces
			held_object.linear_velocity = Vector3.ZERO
			held_object.angular_velocity = Vector3.ZERO

func drop_object():
	if held_object:
		# Reset physics properties before dropping
		# Restore original physics properties
		held_object.mass = original_mass
		held_object.freeze_mode = original_freeze_mode
		held_object.sleeping = false
		held_object.freeze = false

		# Restore collision layers
		held_object.collision_layer = original_collision_layer
		held_object.collision_mask = original_collision_mask

		held_object.reparent(get_tree().root) # Return to world

		# Apply impulse based on player's facing direction
		var throw_direction = -head.global_transform.basis.z
		held_object.apply_central_impulse(throw_direction * 5.0)

		held_object = null
