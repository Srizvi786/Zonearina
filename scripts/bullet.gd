extends Node3D
## Raycast tracer bullet - no tunneling.

var dir := Vector3.FORWARD
var speed := 70.0
var damage := 12.0
var shooter = null
var life := 0.0
var active := false


func _ready() -> void:
	visible = false
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.14, 1.4)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.65, 0.15)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	add_child(mesh)


func setup(d: Vector3, dmg: float, s) -> void:
	dir = d.normalized()
	damage = dmg
	shooter = s
	life = 1.6
	active = true
	visible = true
	if dir.length() > 0.01:
		basis = Basis.looking_at(dir)


func deactivate() -> void:
	active = false
	visible = false
	global_position = Vector3(0, -100, 0)


func _physics_process(delta: float) -> void:
	if not active:
		return
	var from := global_position
	var to: Vector3 = from + dir * speed * delta
	var excl := []
	if shooter != null and shooter is CollisionObject3D:
		excl.append((shooter as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, excl)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("take_damage"):
			collider.take_damage(damage, shooter)
			var arena := get_tree().current_scene
			if arena != null and arena.has_method("spark"):
				arena.spark(hit["position"])
			if arena != null and arena.has_method("damage_number"):
				var mine := shooter != null and shooter is Fighter and (shooter as Fighter).is_player
				arena.damage_number(hit["position"], damage, mine)
		deactivate()
		return
	global_position = to
	life -= delta
	if life <= 0.0 or global_position.y < -2.0:
		deactivate()
