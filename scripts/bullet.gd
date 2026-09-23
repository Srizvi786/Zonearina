extends Node3D
## Visible tracer bullet - raycast hit + bright trail.

var dir := Vector3.FORWARD
var speed := 90.0
var damage := 12.0
var shooter = null
var life := 0.0
var active := false
var trail: MeshInstance3D


func _ready() -> void:
	visible = false
	# Tracer core
	trail = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 2.2)
	trail.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 8.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail.material_override = mat
	add_child(trail)
	# Outer glow
	var glow := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.22, 0.22, 2.4)
	glow.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(1.0, 0.7, 0.2, 0.35)
	gmat.emission_enabled = true
	gmat.emission = Color(1.0, 0.6, 0.1)
	gmat.emission_energy_multiplier = 3.0
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.material_override = gmat
	add_child(glow)


func setup(d: Vector3, dmg: float, s) -> void:
	dir = d.normalized()
	damage = dmg
	shooter = s
	life = 0.55
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
		var arena := get_tree().current_scene
		var mine := shooter != null and shooter is Fighter and (shooter as Fighter).is_player
		if collider != null and collider.has_method("take_damage"):
			collider.take_damage(damage, shooter)
			if arena != null and arena.has_method("spark"):
				arena.spark(hit["position"])
			if arena != null and arena.has_method("damage_number"):
				arena.damage_number(hit["position"], damage, mine)
			if mine and arena != null and arena.has_method("hit_feedback"):
				arena.hit_feedback()
		elif arena != null and arena.has_method("spark"):
			arena.spark(hit["position"])
		deactivate()
		return
	global_position = to
	life -= delta
	if life <= 0.0 or global_position.y < -2.0:
		deactivate()
