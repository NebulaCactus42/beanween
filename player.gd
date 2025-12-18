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

# Throw mechanics variables
var is_charging_throw = false
var throw_charge = 0.0
var max_throw_charge = 2.0
var throw_charge_rate = 1.5

# Trajectory prediction variables
var trajectory_points = []
var trajectory_line = null
var gravity = -9.8

func _process(_delta):
	if ray.is_colliding():
		crosshair.color = Color(1, 0, 0) # Red when looking at something
	else:
		crosshair.color = Color(1, 1, 1, 0.8) # Default white

	# Visual feedback for throw charging
	if is_charging_throw:
		# Change crosshair color based on charge level
		var charge_ratio = throw_charge / max_throw_charge
		crosshair.color = Color(1, 1 - charge_ratio, 0) # Red to Yellow

		# Change crosshair size based on charge (using scale)
		var base_scale = 1.0
		var max_scale = 2.0
		var current_scale = base_scale + (max_scale - base_scale) * charge_ratio
		crosshair.scale = Vector2(current_scale, current_scale)
	else:
		# Reset crosshair to normal when not charging
		if !ray.is_colliding():  # Only reset if not aiming at something
			crosshair.color = Color(1, 1, 1, 0.8)  # Default white
			crosshair.scale = Vector2(1.0, 1.0)

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

		# Store vertical aim angle for throwing mechanics
		$"Head/Camera3D".set_meta("vertical_aim_angle", camera.rotation.x)

	if event.is_action_pressed("ui_select"): # E key - Pick up/Drop
		if held_object:
			if is_charging_throw:
				# Already charging, do nothing on press
				pass
			else:
				# Start charging throw
				is_charging_throw = true
				throw_charge = 0.0
		else:
			# Not holding anything, pick up on press
			pick_up_object()

	elif event.is_action_released("ui_select"):
		if is_charging_throw:
			if held_object:
				# Execute charged throw
				drop_object_with_force()
			else:
				# Quick drop (tap E instead of holding)
				drop_object()
			is_charging_throw = false

func _physics_process(delta):
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Charge throw while holding E key
	if is_charging_throw and held_object:
		throw_charge += throw_charge_rate * delta
		if throw_charge > max_throw_charge:
			throw_charge = max_throw_charge

		# Update trajectory prediction
		update_trajectory_prediction()
	else:
		# Clear trajectory when not charging
		clear_trajectory()

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

func update_trajectory_prediction():
	# Clear existing trajectory
	clear_trajectory()

	if !held_object:
		return

	# Calculate throw force
	var throw_force = 10.0 * throw_charge
	if throw_force < 5.0:
		throw_force = 5.0

	# Get starting position (hand position)
	var start_pos = hand.global_position

	# Get throw direction based on camera aim (includes vertical component)
	var camera_node = $"Head/Camera3D"
	var throw_direction = -camera_node.global_transform.basis.z

	# Get vertical aim angle (stored in meta)
	var vertical_aim = camera_node.get_meta("vertical_aim_angle", camera_node.rotation.x)

	# Calculate initial velocity with vertical aim influence
	var initial_velocity = throw_direction * throw_force

	# Adjust upward component based on vertical aim
	var upward_factor = 0.3
	if vertical_aim < 0:  # Aiming upward
		upward_factor = 0.5  # More upward force for lobbing
	elif vertical_aim > 0:  # Aiming downward
		upward_factor = 0.1  # Less upward force for tossing

	initial_velocity.y = throw_force * upward_factor

	# Store the upward factor for trajectory visualization
	camera_node.set_meta("upward_factor", upward_factor)

	# Simulate trajectory with physics
	var current_pos = start_pos
	var current_velocity = initial_velocity
	var time_step = 0.05
	var max_steps = 50

	for i in range(max_steps):
		# Apply gravity
		current_velocity.y += gravity * time_step

		# Calculate new position
		var new_pos = current_pos + current_velocity * time_step

		# Check if we hit the ground (simple plane check for now)
		if new_pos.y < 0:
			new_pos.y = 0
			break

		# Add point to trajectory
		trajectory_points.append(new_pos)

		# Prepare for next iteration
		current_pos = new_pos
		current_velocity = current_velocity

		# Stop if velocity is very low
		if current_velocity.length() < 0.1:
			break

	# Create or update trajectory line
	if trajectory_line == null:
		# Create a MeshInstance3D to hold the ImmediateMesh
		var mesh_instance = MeshInstance3D.new()
		get_tree().root.add_child(mesh_instance)
		mesh_instance.visible = true

		# Create and assign ImmediateMesh
		var immediate_mesh = ImmediateMesh.new()
		mesh_instance.mesh = immediate_mesh
		trajectory_line = immediate_mesh

	# Draw the trajectory line using ImmediateMesh
	trajectory_line.clear_surfaces()
	trajectory_line.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	# Set color based on charge level and throw type
	var charge_ratio = throw_charge / max_throw_charge
	var upward_factor = camera_node.get_meta("upward_factor", 0.3)

	var line_color
	if upward_factor >= 0.4:  # LOB (high upward factor)
		line_color = Color(1, 1 - charge_ratio * 0.5, 0)  # More red for lobs
	elif upward_factor <= 0.2:  # TOSS (low upward factor)
		line_color = Color(1, 1 - charge_ratio * 1.5, 0)  # More yellow for tosses
	else:  # BALANCED
		line_color = Color(1, 1 - charge_ratio, 0)  # Standard red to yellow

	for point in trajectory_points:
		trajectory_line.surface_set_color(line_color)
		trajectory_line.surface_add_vertex(point)

	trajectory_line.surface_end()

func clear_trajectory():
	if trajectory_line:
		# Find and remove the MeshInstance3D parent
		for child in get_tree().root.get_children():
			if child is MeshInstance3D and child.mesh == trajectory_line:
				child.queue_free()
				break
		trajectory_line = null
	trajectory_points.clear()

func drop_object_with_force():
	if held_object:
		# Calculate throw force based on charge level
		var throw_force = 10.0 * throw_charge
		if throw_force < 5.0:  # Minimum throw force
			throw_force = 5.0

		# Restore original physics properties
		held_object.mass = original_mass
		held_object.freeze_mode = original_freeze_mode
		held_object.sleeping = false
		held_object.freeze = false

		# Restore collision layers
		held_object.collision_layer = original_collision_layer
		held_object.collision_mask = original_collision_mask

		held_object.reparent(get_tree().root)

		# Apply impulse based on player's facing direction and charge level with vertical aim
		var camera_node = $"Head/Camera3D"
		var throw_direction = -camera_node.global_transform.basis.z

		# Get vertical aim angle for lob/toss mechanics
		var vertical_aim = camera_node.get_meta("vertical_aim_angle", camera_node.rotation.x)

		# Adjust upward component based on vertical aim
		var upward_factor = 0.3
		if vertical_aim < 0:  # Aiming upward - LOB
			upward_factor = 0.5  # More upward force for high arcs
		elif vertical_aim > 0:  # Aiming downward - TOSS
			upward_factor = 0.1  # Less upward force for flat throws

		held_object.apply_central_impulse(throw_direction * throw_force)
		held_object.apply_central_impulse(Vector3.UP * throw_force * upward_factor)

		held_object = null
		throw_charge = 0.0

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
