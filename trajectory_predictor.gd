class_name TrajectoryPredictor
extends MeshInstance3D

var immediate_mesh: ImmediateMesh
var landing_marker: MeshInstance3D

func _ready():
	immediate_mesh = ImmediateMesh.new()
	mesh = immediate_mesh

	# Ensure line is visible with a basic material
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.YELLOW
	material_override = mat

	# Set up landing marker
	landing_marker = MeshInstance3D.new()
	add_child(landing_marker)
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.1
	cylinder.bottom_radius = 0.1
	cylinder.height = 0.01
	landing_marker.mesh = cylinder
	var marker_mat = StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = Color.YELLOW
	landing_marker.material_override = marker_mat
	landing_marker.visible = false

func update_path(start_pos: Vector3, initial_vel: Vector3, gravity: float = -9.8, dt: float = 0.05, ignore_obj: CollisionObject3D = null):
	var points: Array[Vector3] = []
	var pos = start_pos
	var vel = initial_vel
	var space_state = get_world_3d().direct_space_state

	# Simulate for 50 steps
	for i in range(50):
		points.append(to_local(pos)) # Convert global to local space
		vel.y += gravity * dt
		var next_pos = pos + vel * dt
		# Perform raycast from current position to next position
		var query = PhysicsRayQueryParameters3D.create(pos, next_pos)
		if ignore_obj:
			query.exclude = [ignore_obj.get_rid()]
		var result = space_state.intersect_ray(query)
		if result:
			points.append(to_local(result.position))
			landing_marker.global_position = result.position + result.normal * 0.01
			var up_vec = Vector3.UP if abs(result.normal.y) < 0.99 else Vector3.FORWARD; landing_marker.look_at(result.position + result.normal, up_vec);
			landing_marker.visible = true
			break
		else:
			pos = next_pos
		if pos.y < -10: break # Safety floor

	_draw_line(points)

func _draw_line(points: Array[Vector3]):
	immediate_mesh.clear_surfaces()
	if points.size() < 2: return
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		immediate_mesh.surface_add_vertex(p)
	immediate_mesh.surface_end()

func clear():
	immediate_mesh.clear_surfaces()
	landing_marker.visible = false
