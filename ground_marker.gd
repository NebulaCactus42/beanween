extends MeshInstance3D

const MIN_SCALE = 1.0
const MAX_SCALE = 3.0
const HEIGHT_THRESHOLD = 10.0 # Height at which scale is maxed

func _ready():
	set_as_top_level(true)
	material_override = StandardMaterial3D.new()

func _physics_process(_delta):
	var parent = get_parent()
	if parent is RigidBody3D and not parent.freeze and parent.linear_velocity.length() > 0.1:
		visible = true
		update_ground_position(parent.global_position)
	else:
		visible = false

func update_ground_position(pos: Vector3):
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 50.0)
	query.exclude = [get_parent().get_rid()]
	
	var result = space.intersect_ray(query)
	if result:
		global_position = result.position + result.normal * 0.02
		
		# 1. Calculate distance and scale
		var distance = pos.distance_to(result.position)
		var height_ratio = clamp(distance / HEIGHT_THRESHOLD, 0.0, 1.0)
		var current_scale = lerp(MIN_SCALE, MAX_SCALE, height_ratio)
		scale = Vector3(current_scale, 1, current_scale)

		# 3. Handle rotation
		var up_vec = Vector3.UP if abs(result.normal.y) < 0.99 else Vector3.FORWARD
		look_at(global_position + result.normal, up_vec)
		rotation.x += PI / 2
