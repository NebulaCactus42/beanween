class_name TrajectoryPredictor
extends MeshInstance3D

var immediate_mesh: ImmediateMesh
var landing_marker: MeshInstance3D

func _ready():
	_setup_trajectory_line()
	_setup_landing_marker()

func _setup_trajectory_line():
	immediate_mesh = ImmediateMesh.new()
	mesh = immediate_mesh
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.YELLOW
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.7  # Slight transparency
	material_override = mat

func _setup_landing_marker():
	landing_marker = MeshInstance3D.new()
	add_child(landing_marker)
	
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.15
	cylinder.bottom_radius = 0.15
	cylinder.height = 0.02
	landing_marker.mesh = cylinder
	
	var marker_mat = StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = Color.YELLOW
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.albedo_color.a = 0.8
	landing_marker.material_override = marker_mat
	landing_marker.visible = false

func update_path(
	start_pos: Vector3, 
	initial_vel: Vector3, 
	gravity: float = -9.8, 
	dt: float = 0.05, 
	ignore_obj: CollisionObject3D = null
):
	var points: Array[Vector3] = []
	var pos = start_pos
	var vel = initial_vel
	var space_state = get_world_3d().direct_space_state
	
	# Simulate trajectory with collision detection
	for i in range(50):
		points.append(to_local(pos))
		
		# Apply gravity
		vel.y += gravity * dt
		var next_pos = pos + vel * dt
		
		# Check for collision
		var query = PhysicsRayQueryParameters3D.create(pos, next_pos)
		if ignore_obj:
			query.exclude = [ignore_obj.get_rid()]
		
		var result = space_state.intersect_ray(query)
		
		if result:
			# Hit something - show landing marker and stop
			points.append(to_local(result.position))
			_position_landing_marker(result.position, result.normal)
			break
		
		# Continue trajectory
		pos = next_pos
		
		# Safety check - stop if too far below world
		if pos.y < -10:
			landing_marker.visible = false
			break
	
	_draw_line(points)

func _position_landing_marker(hit_pos: Vector3, hit_normal: Vector3):
	landing_marker.global_position = hit_pos + hit_normal * 0.01
	
	# Align marker to surface normal
	var up_vec = Vector3.UP if abs(hit_normal.y) < 0.99 else Vector3.FORWARD
	landing_marker.look_at(hit_pos + hit_normal, up_vec)
	landing_marker.visible = true

func _draw_line(points: Array[Vector3]):
	immediate_mesh.clear_surfaces()
	if points.size() < 2:
		return
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		immediate_mesh.surface_add_vertex(p)
	immediate_mesh.surface_end()

func clear():
	immediate_mesh.clear_surfaces()
	landing_marker.visible = false
