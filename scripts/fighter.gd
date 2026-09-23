class_name Fighter
extends CharacterBody3D
## PUBG-style soldier: tactical gear, reliable shooting, camera aim.

signal died(fighter: Fighter)

const SPEED := 6.5
const BOT_SPEED := 5.4
const GRAVITY := 22.0
const MAX_HP := 100.0
const BULLET_SCENE := preload("res://scenes/bullet.tscn")

const GUNS := {
	"rifle": {"dmg": 14.0, "interval": 0.16, "mag": 30, "auto": true, "spread": 0.02, "sound": "rifle", "range": 110.0},
	"smg": {"dmg": 9.0, "interval": 0.11, "mag": 40, "auto": true, "spread": 0.05, "sound": "smg", "range": 65.0},
	"sniper": {"dmg": 55.0, "interval": 1.2, "mag": 5, "auto": false, "spread": 0.0, "sound": "sniper", "range": 200.0},
}

var is_player := false
var fname := "Bot"
var personality := 0
var hp := MAX_HP
var alive := true
var kills := 0
var move_input := Vector2.ZERO
var aim_yaw := 0.0
var aim_pitch := -0.10
var fire_held := false
var fire_cd := 0.0
var body_color := Color(0.28, 0.32, 0.24)
var skin_color := Color(0.82, 0.62, 0.48)
var camo_accent := Color(0.22, 0.26, 0.18)

var gun := "rifle"
var ammo_mag := 30
var ammo_reserve := 120
var ext_mag := false
var grenades := 1
var medkits := 1
var bandages := 2
var drinks := 1
var helmet := false
var helmet_hp := 50.0
var vest := false
var vest_hp := 50.0

var reloading := 0.0
var heal_t := 0.0
var heal_total := 1.0
var heal_kind := ""
var crouching := false
var zoom_idx := 0
var last_hit_by = null

# Visuals
var visual: Node3D
var torso: MeshInstance3D
var head_m: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var muzzle: Marker3D
var flash_m: MeshInstance3D
var flash_t := 0.0
var helmet_m: MeshInstance3D
var vest_m: MeshInstance3D
var body_mat: StandardMaterial3D
var gun_root: Node3D
var walk_phase := 0.0
var col: CollisionShape3D
var cam_pivot: Node3D
var cam: Camera3D
var name_label: Label3D

var think_cd := 0.0
var wander_cd := 0.0
var burst_cd := 0.0
var strafe_sign := 1.0
var nade_cd := 8.0
var stuck_t := 0.0
var looted_upgrade := false


func mag_size() -> int:
	return int(GUNS[gun]["mag"]) + (10 if ext_mag else 0)


func _ready() -> void:
	add_to_group("fighters")
	floor_snap_length = 0.5
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_build_soldier()
	if is_player:
		_setup_camera()


func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## PUBG-inspired operator: helmet, plate carrier, camo fatigues, boots, gloves.
func _build_soldier() -> void:
	visual = Node3D.new()
	add_child(visual)

	var camo := _mat(body_color, 0.92)
	var camo_dark := _mat(camo_accent, 0.9)
	var skin := _mat(skin_color, 0.7)
	var vest_c := _mat(Color(0.18, 0.2, 0.16), 0.75)
	var gear := _mat(Color(0.12, 0.13, 0.11), 0.7)
	var boot := _mat(Color(0.1, 0.09, 0.08), 0.65)
	var glove := _mat(Color(0.15, 0.14, 0.12), 0.8)
	var metal := _mat(Color(0.18, 0.18, 0.2), 0.35, 0.7)
	var gun_c := _mat(Color(0.1, 0.1, 0.11), 0.45, 0.55)
	var wood := _mat(Color(0.28, 0.18, 0.1), 0.7)
	body_mat = camo

	# --- Torso: fatigues + plate carrier ---
	torso = _box(visual, Vector3(0.52, 0.68, 0.30), Vector3(0, 1.18, 0), camo)
	# Plate carrier over torso
	vest_m = _box(visual, Vector3(0.58, 0.52, 0.36), Vector3(0, 1.22, 0), vest_c)
	vest_m.visible = vest
	# Mag pouches (front)
	if vest:
		for i in 3:
			_box(visual, Vector3(0.12, 0.14, 0.08), Vector3(-0.16 + i * 0.16, 1.18, 0.2), gear)
	# Radio on shoulder
	_box(visual, Vector3(0.08, 0.16, 0.06), Vector3(0.22, 1.38, -0.05), gear)
	# Belt
	_box(visual, Vector3(0.5, 0.08, 0.32), Vector3(0, 0.86, 0), gear)

	# --- Head: skull + face + helmet ---
	head_m = _sphere(visual, 0.22, 0.44, Vector3(0, 1.72, 0), skin)
	# Nose / jaw hint
	_box(visual, Vector3(0.1, 0.08, 0.1), Vector3(0, 1.68, -0.2), skin)
	# Eyes
	var eye := _mat(Color(0.06, 0.06, 0.07), 0.4)
	_box(visual, Vector3(0.05, 0.04, 0.03), Vector3(-0.08, 1.74, -0.2), eye)
	_box(visual, Vector3(0.05, 0.04, 0.03), Vector3(0.08, 1.74, -0.2), eye)
	# Balaclava lower face
	_box(visual, Vector3(0.28, 0.14, 0.24), Vector3(0, 1.62, -0.04), _mat(Color(0.14, 0.14, 0.13), 0.9))

	# Helmet (Level-3 style dome + brim + NVG mount)
	helmet_m = MeshInstance3D.new()
	var hd := SphereMesh.new()
	hd.radius = 0.28
	hd.height = 0.36
	hd.radial_segments = 16
	hd.rings = 8
	helmet_m.mesh = hd
	helmet_m.material_override = _mat(Color(0.2, 0.24, 0.16), 0.7)
	helmet_m.position = Vector3(0, 1.80, 0.02)
	helmet_m.scale = Vector3(1.0, 0.85, 1.1)
	helmet_m.visible = helmet
	visual.add_child(helmet_m)
	# Helmet rails
	_box(visual, Vector3(0.5, 0.04, 0.06), Vector3(0, 1.86, -0.1), gear)
	# Ear pro
	_sphere(visual, 0.07, 0.12, Vector3(-0.22, 1.72, 0), gear)
	_sphere(visual, 0.07, 0.12, Vector3(0.22, 1.72, 0), gear)

	# --- Arms: shoulder pivot ---
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.34 * side, 1.42, 0)
		visual.add_child(sh)
		# Upper arm (camo sleeve)
		_box(sh, Vector3(0.16, 0.42, 0.16), Vector3(0, -0.22, 0), camo)
		# Elbow pad
		_box(sh, Vector3(0.17, 0.1, 0.17), Vector3(0, -0.44, 0), gear)
		# Forearm
		_box(sh, Vector3(0.14, 0.36, 0.14), Vector3(0, -0.66, 0), camo_dark)
		# Glove hand
		_box(sh, Vector3(0.13, 0.12, 0.16), Vector3(0, -0.88, -0.02), glove)
		if side < 0.0:
			arm_l = sh
		else:
			arm_r = sh

	# --- Legs ---
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.14 * side, 0.86, 0)
		visual.add_child(hip)
		_box(hip, Vector3(0.2, 0.4, 0.2), Vector3(0, -0.22, 0), camo)
		# Knee pad
		_box(hip, Vector3(0.18, 0.1, 0.2), Vector3(0, -0.44, -0.02), gear)
		_box(hip, Vector3(0.18, 0.36, 0.18), Vector3(0, -0.68, 0), camo_dark)
		# Combat boot
		_box(hip, Vector3(0.2, 0.14, 0.3), Vector3(0, -0.92, -0.04), boot)
		_box(hip, Vector3(0.2, 0.06, 0.32), Vector3(0, -0.98, -0.05), _mat(Color(0.06, 0.06, 0.06), 0.5))
		if side < 0.0:
			leg_l = hip
		else:
			leg_r = hip

	# --- Weapon held in both hands (visible rifle) ---
	gun_root = Node3D.new()
	# Aligned with aiming hand pose (hands ~y1.1 z-0.75 when arms forward)
	gun_root.position = Vector3(0.0, 1.12, -0.55)
	gun_root.rotation.x = 0.08
	gun_root.scale = Vector3(1.15, 1.15, 1.15)
	visual.add_child(gun_root)

	muzzle = Marker3D.new()
	muzzle.position = Vector3(0.0, 0.05, -1.05)
	gun_root.add_child(muzzle)

	# Muzzle flash
	flash_m = MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 0.2
	fs.height = 0.4
	flash_m.mesh = fs
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1, 0.85, 0.35)
	fm.emission_enabled = true
	fm.emission = Color(1, 0.7, 0.2)
	fm.emission_energy_multiplier = 6.0
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_m.material_override = fm
	flash_m.position = Vector3(0, 0.05, -1.1)
	flash_m.visible = false
	gun_root.add_child(flash_m)
	_build_weapon_mesh(gun_root)

	# Collision capsule (human height ~1.75)
	col = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.75
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# Floating name for enemies
	if not is_player:
		name_label = Label3D.new()
		name_label.text = fname
		name_label.font_size = 40
		name_label.pixel_size = 0.006
		name_label.outline_size = 6
		name_label.modulate = Color(1, 0.4, 0.35)
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.position = Vector3(0, 2.25, 0)
		visual.add_child(name_label)


func _build_weapon_mesh(root: Node3D) -> void:
	# Brighter metals so gun reads clearly on mobile
	var gun_c := _mat(Color(0.18, 0.18, 0.2), 0.4, 0.5)
	var metal := _mat(Color(0.45, 0.45, 0.5), 0.3, 0.85)
	var wood := _mat(Color(0.4, 0.26, 0.14), 0.65)
	var black := _mat(Color(0.08, 0.08, 0.09), 0.5, 0.4)
	# Clear old mesh parts only (keep muzzle/flash markers)
	for c in root.get_children():
		if c is MeshInstance3D or c is Marker3D:
			if c != muzzle and c != flash_m:
				c.queue_free()
	match gun:
		"sniper":
			_box(root, Vector3(0.09, 0.12, 1.45), Vector3(0, 0.05, -0.4), gun_c)
			_box(root, Vector3(0.08, 0.1, 0.4), Vector3(0, 0.05, 0.4), wood)
			_cyl(root, 0.03, 0.03, 0.7, Vector3(0, 0.06, -1.15), metal, Vector3(PI / 2, 0, 0))
			_cyl(root, 0.05, 0.05, 0.32, Vector3(0, 0.18, -0.15), black, Vector3(PI / 2, 0, 0))
			_box(root, Vector3(0.05, 0.09, 0.1), Vector3(0, 0.11, -0.15), metal)
		"smg":
			_box(root, Vector3(0.1, 0.14, 0.78), Vector3(0, 0.05, -0.22), gun_c)
			_box(root, Vector3(0.09, 0.12, 0.24), Vector3(0, 0.02, 0.28), black)
			_cyl(root, 0.025, 0.025, 0.3, Vector3(0, 0.06, -0.62), metal, Vector3(PI / 2, 0, 0))
			_box(root, Vector3(0.06, 0.16, 0.1), Vector3(0, -0.08, -0.05), metal)
			_box(root, Vector3(0.05, 0.08, 0.35), Vector3(0, 0.0, 0.35), black)
		_:
			# Assault rifle - larger + lighter so it's clearly in hands
			_box(root, Vector3(0.1, 0.13, 1.0), Vector3(0, 0.05, -0.3), gun_c)
			_box(root, Vector3(0.09, 0.12, 0.34), Vector3(0, 0.04, 0.38), wood)
			_cyl(root, 0.028, 0.028, 0.5, Vector3(0, 0.06, -0.9), metal, Vector3(PI / 2, 0, 0))
			# Magazine
			_box(root, Vector3(0.07, 0.22, 0.1), Vector3(0, -0.1, -0.1), metal)
			# Front + rear sights
			_box(root, Vector3(0.04, 0.1, 0.04), Vector3(0, 0.16, -0.65), metal)
			_box(root, Vector3(0.05, 0.06, 0.12), Vector3(0, 0.15, 0.05), metal)
			# Handguard ribs
			for i in 3:
				_box(root, Vector3(0.11, 0.03, 0.04), Vector3(0, 0.1, -0.45 - i * 0.1), black)


func refresh_weapon_visual() -> void:
	if gun_root != null:
		_build_weapon_mesh(gun_root)


func _setup_camera() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(0, 1.55, 0)
	add_child(cam_pivot)
	var spring := SpringArm3D.new()
	spring.spring_length = 4.5
	spring.margin = 0.35
	spring.collision_mask = 1
	cam_pivot.add_child(spring)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.far = 180.0
	cam.current = true
	spring.add_child(cam)
	_apply_aim()


func _apply_aim() -> void:
	rotation.y = aim_yaw
	if cam_pivot != null:
		cam_pivot.rotation.x = aim_pitch
		var zooms := [75.0, 50.0, 30.0]
		if cam != null:
			cam.fov = zooms[clampi(zoom_idx, 0, 2)]


func set_crouch(v: bool) -> void:
	if crouching == v:
		return
	crouching = v
	if crouching:
		visual.scale.y = 0.78
		(col.shape as CapsuleShape3D).height = 1.3
		col.position.y = 0.7
	else:
		visual.scale.y = 1.0
		(col.shape as CapsuleShape3D).height = 1.75
		col.position.y = 0.9


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if is_player:
		_player_input(delta)
	else:
		_bot_think(delta)

	var spd := SPEED * (0.55 if crouching else 1.0)
	if not is_player:
		spd = BOT_SPEED
	var local := Vector3(move_input.x, 0.0, move_input.y)
	var world_dir: Vector3 = Basis(Vector3.UP, aim_yaw) * local
	if world_dir.length() > 1.0:
		world_dir = world_dir.normalized()
	velocity.x = world_dir.x * spd
	velocity.z = world_dir.z * spd
	_apply_aim()
	move_and_slide()

	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			_finish_reload()
	_update_heal(delta)

	fire_cd -= delta
	if fire_held and fire_cd <= 0.0 and reloading <= 0.0 and heal_t <= 0.0:
		if ammo_mag > 0:
			shoot()
		else:
			start_reload()

	_animate(delta, world_dir.length())


func _animate(delta: float, speed01: float) -> void:
	var aiming := fire_held or zoom_idx > 0 or not is_player
	if speed01 > 0.3 and is_on_floor():
		walk_phase += delta * (5.5 + speed01 * 6.5)
		var s := sin(walk_phase) * (0.5 if not aiming else 0.22)
		arm_l.rotation.x = s * 0.7 - (0.95 if aiming else 0.0)
		arm_r.rotation.x = -s * 0.3 - (1.15 if aiming else 0.0)
		if aiming:
			arm_l.rotation.z = 0.32
			arm_r.rotation.z = -0.18
		leg_l.rotation.x = -s
		leg_r.rotation.x = s
		visual.position.y = abs(sin(walk_phase)) * 0.04
	elif aiming:
		# Arms forward holding weapon (matches gun_root at z-0.55)
		arm_l.rotation.x = -1.05
		arm_l.rotation.z = 0.35
		arm_r.rotation.x = -1.25
		arm_r.rotation.z = -0.2
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, delta * 8.0)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, delta * 8.0)
	else:
		arm_l.rotation.x = lerpf(arm_l.rotation.x, 0.0, delta * 8.0)
		arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.0, delta * 8.0)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.0, delta * 8.0)
		arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.0, delta * 8.0)
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, delta * 8.0)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, delta * 8.0)
	if crouching:
		leg_l.rotation.x = 0.85
		leg_r.rotation.x = -0.65
		torso.rotation.x = 0.22
	else:
		torso.rotation.x = 0.0
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			flash_m.visible = false
	# Weapon follows torso pitch slightly
	if gun_root != null:
		gun_root.rotation.x = -aim_pitch * 0.5 + (0.15 if crouching else 0.0)


func _player_input(delta: float) -> void:
	var ix := Input.get_axis("move_left", "move_right")
	var iy := Input.get_axis("move_forward", "move_back")
	if Vector2(ix, iy).length() > 0.01:
		move_input = Vector2(ix, iy)
	if Input.is_action_just_pressed("jump"):
		try_jump()
	if Input.is_action_just_pressed("reload"):
		start_reload()
	# Only keyboard fire action + explicit touch flag.
	# Do NOT use raw MOUSE_BUTTON_LEFT — emulate_mouse_from_touch makes
	# any screen tap look like left-click and fire gets stuck.
	if Input.is_action_pressed("fire") and not _touch_fire_held:
		fire_held = true
	elif not Input.is_action_pressed("fire") and not _touch_fire_held:
		fire_held = false


var _touch_fire_held := false


func set_touch_fire(v: bool) -> void:
	_touch_fire_held = v
	fire_held = v or Input.is_action_pressed("fire")


func release_trigger() -> void:
	_touch_fire_held = false
	fire_held = Input.is_action_pressed("fire")


func try_jump() -> void:
	if alive and is_on_floor():
		velocity.y = 8.0


func _aim_point() -> Vector3:
	var rng: float = float(GUNS[gun]["range"])
	if is_player and cam != null:
		var vp := get_viewport()
		if vp != null:
			var center := vp.get_visible_rect().size * 0.5
			var from := cam.project_ray_origin(center)
			var rdir: Vector3 = cam.project_ray_normal(center)
			# Soft aim assist: lock to enemy near crosshair
			var best: Fighter = null
			var best_perp := 2.5
			for n in get_tree().get_nodes_in_group("fighters"):
				if n == self:
					continue
				var f := n as Fighter
				if f == null or not f.alive:
					continue
				var chest: Vector3 = f.global_position + Vector3(0, 1.15, 0)
				var to_f: Vector3 = chest - from
				var t := to_f.dot(rdir)
				if t < 2.0 or t > rng:
					continue
				var perp: float = (to_f - rdir * t).length()
				if perp < best_perp:
					best_perp = perp
					best = f
			if best != null and zoom_idx > 0:
				var bp: Vector3 = best.global_position + Vector3(0, 1.15, 0)
				var tof: float = from.distance_to(bp) / 80.0
				bp += best.velocity * tof * 0.9
				return bp
			var to: Vector3 = from + rdir * rng
			var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				return hit["position"]
			return to
	var fwd := -global_transform.basis.z
	return muzzle.global_position + fwd * rng


func shoot() -> void:
	if not alive or reloading > 0.0:
		return
	if ammo_mag <= 0:
		start_reload()
		return
	ammo_mag -= 1
	fire_cd = float(GUNS[gun]["interval"])
	var arena := get_tree().current_scene
	if arena == null or not arena.has_method("get_bullet"):
		push_warning("shoot: arena missing get_bullet")
		return
	var b = arena.get_bullet()
	if b == null:
		return
	b.global_position = muzzle.global_position
	var target := _aim_point()
	var dir: Vector3 = (target - muzzle.global_position).normalized()
	if dir.length() < 0.5:
		dir = -global_transform.basis.z
	var spread: float = float(GUNS[gun]["spread"]) * (0.55 if crouching else 1.0)
	if zoom_idx == 2:
		spread *= 0.35
	if not is_player:
		var bm: Dictionary = Settings.bot_mult()
		spread = 0.055 * float(bm["err"])
		if crouching:
			spread *= 0.7
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	dir = (dir + Vector3(randf_range(-spread, spread) * 0.3, randf_range(-spread, spread) * 0.3, 0)).normalized()
	b.setup(dir, _gun_damage(), self)
	flash_m.visible = true
	flash_t = 0.05
	flash_m.rotation.z = randf() * TAU
	Sfx.play(str(GUNS[gun]["sound"]))


func _gun_damage() -> float:
	var d := float(GUNS[gun]["dmg"])
	if not is_player:
		d *= float(Settings.bot_mult()["dmg"])
	return d


func start_reload() -> void:
	if reloading > 0.0 or ammo_reserve <= 0 or ammo_mag >= mag_size():
		return
	reloading = 2.0
	Sfx.play("reload")


func _finish_reload() -> void:
	var need := mag_size() - ammo_mag
	var take := mini(need, ammo_reserve)
	ammo_mag += take
	ammo_reserve -= take


func start_heal(kind: String) -> bool:
	if heal_t > 0.0 or not alive:
		return false
	if kind == "medkit" and medkits > 0:
		heal_t = 5.0
	elif kind == "bandage" and bandages > 0:
		heal_t = 1.2
	elif kind == "drink" and drinks > 0:
		heal_t = 3.0
	else:
		return false
	heal_total = heal_t
	heal_kind = kind
	return true


func _update_heal(delta: float) -> void:
	if heal_t <= 0.0:
		return
	if heal_kind != "bandage" and move_input.length() > 0.1:
		heal_t = 0.0
		heal_kind = ""
		return
	heal_t -= delta
	if heal_t <= 0.0:
		if heal_kind == "medkit":
			medkits -= 1
			hp = MAX_HP
		elif heal_kind == "bandage":
			bandages -= 1
			hp = minf(MAX_HP, hp + 25.0)
		elif heal_kind == "drink":
			drinks -= 1
			hp = minf(MAX_HP, hp + 40.0)
		heal_kind = ""


func cancel_heal_on_damage() -> void:
	if heal_kind == "medkit" or heal_kind == "drink":
		heal_t = 0.0
		heal_kind = ""


func throw_grenade(target: Vector3) -> void:
	if grenades <= 0 or not alive:
		return
	grenades -= 1
	var arena := get_tree().current_scene
	if arena != null and arena.has_method("spawn_grenade"):
		arena.spawn_grenade(muzzle.global_position, target, self)


func take_damage(amount: float, from = null) -> void:
	if not alive:
		return
	last_hit_by = from
	var a := amount
	if helmet and helmet_hp > 0.0:
		a *= 0.78
		helmet_hp -= amount
		if helmet_hp <= 0.0:
			helmet = false
			helmet_m.visible = false
	if vest and vest_hp > 0.0:
		a *= 0.72
		vest_hp -= amount
		if vest_hp <= 0.0:
			vest = false
			vest_m.visible = false
			# Remove pouches visual - keep simple
	hp -= a
	_flash_hit()
	cancel_heal_on_damage()
	if is_player:
		Sfx.play("hurt")
		Sfx.buzz(50)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		fire_held = false
		if from != null and from != self and from is Fighter and (from as Fighter).is_player:
			(from as Fighter).kills += 1
			Sfx.buzz(70)
		died.emit(self)
		_die_fall()


func _die_fall() -> void:
	set_physics_process(false)
	col.set_deferred("disabled", true)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(visual, "rotation:x", -1.5, 0.55)
	tw.tween_property(visual, "position:y", 0.25, 0.55)
	tw.chain().tween_interval(1.0)
	tw.tween_callback(queue_free)


func start_dance() -> void:
	if not alive:
		return
	move_input = Vector2.ZERO
	fire_held = false
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(visual, "position:y", 0.3, 0.3)
	tw.tween_property(visual, "position:y", 0.0, 0.3)
	tw.parallel().tween_property(self, "rotation:y", rotation.y + TAU, 1.2)


func equip_bot_sniper() -> void:
	if looted_upgrade:
		return
	looted_upgrade = true
	gun = "sniper"
	ammo_mag = 5
	ammo_reserve = 25
	vest = true
	vest_hp = 50.0
	vest_m.visible = true
	refresh_weapon_visual()


func _flash_hit() -> void:
	if body_mat == null:
		return
	body_mat.emission_enabled = true
	body_mat.emission = Color(1, 0.15, 0.1)
	body_mat.emission_energy_multiplier = 2.5
	var tw := create_tween()
	tw.tween_property(body_mat, "emission_energy_multiplier", 0.0, 0.3)


func _nearest_enemy(max_dist: float) -> Fighter:
	var best: Fighter = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group("fighters"):
		if n == self:
			continue
		var f := n as Fighter
		if f == null or not f.alive:
			continue
		var d := global_position.distance_to(f.global_position)
		if d < best_d:
			best_d = d
			best = f
	return best


func _has_los(target: Fighter) -> bool:
	var from: Vector3 = global_position + Vector3(0, 1.5, 0)
	var to: Vector3 = target.global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	return hit.get("collider") == target


func _bot_think(delta: float) -> void:
	think_cd -= delta
	wander_cd -= delta
	burst_cd -= delta
	nade_cd -= delta
	if think_cd > 0.0:
		return
	think_cd = 0.22
	if move_input.length() > 0.1:
		stuck_t += 0.22
		if stuck_t > 2.0:
			stuck_t = 0.0
			aim_yaw += 2.2
			strafe_sign = -strafe_sign
			wander_cd = 0.0
	else:
		stuck_t = 0.0
	var arena := get_tree().current_scene
	var live := true
	if arena != null and arena.has_method("is_live"):
		live = arena.is_live()
	var target := _nearest_enemy(45.0)

	if personality == 2 and arena != null and arena.has_method("get_loot_point"):
		var lp: Vector3 = arena.get_loot_point()
		if target == null or global_position.distance_to(target.global_position) > 18.0:
			_go_to(Vector2(lp.x, lp.z))
			fire_held = false
			if target != null and global_position.distance_to(target.global_position) < 16.0:
				_engage(target)
			return

	if target != null and live:
		var to: Vector3 = target.global_position - global_position
		var dist := to.length()
		var engage_r := 30.0
		if personality == 1:
			engage_r = 22.0
		if dist < engage_r and _has_los(target):
			_engage(target)
			return
		elif personality == 0 and dist < 50.0:
			_go_to(Vector2(target.global_position.x, target.global_position.z))
			fire_held = false
			return
	if arena != null and arena.has_method("get_zone_info"):
		var zi: Dictionary = arena.get_zone_info()
		var c: Vector2 = zi["center"]
		var r: float = zi["radius"]
		var me := Vector2(global_position.x, global_position.z)
		if me.distance_to(c) > r * 0.9:
			_go_to(c)
			fire_held = false
			return
	if personality == 1:
		move_input = Vector2.ZERO
		fire_held = false
		return
	if wander_cd <= 0.0:
		wander_cd = randf_range(2.0, 4.0)
		aim_yaw = randf() * TAU
	move_input = Vector2(0, -1)
	fire_held = false


func _go_to(p: Vector2) -> void:
	var d := p - Vector2(global_position.x, global_position.z)
	if d.length() < 2.0:
		move_input = Vector2.ZERO
		return
	aim_yaw = atan2(-d.x, -d.y)
	move_input = Vector2(0, -1)


func _engage(target: Fighter) -> void:
	var to: Vector3 = target.global_position - global_position
	var dist := to.length()
	aim_yaw = atan2(-to.x, -to.z)
	aim_pitch = clamp(-(to.y - 0.3) / maxf(dist, 1.0), -0.45, 0.25)
	var bm: Dictionary = Settings.bot_mult()
	var fwd_amount := 0.0
	if personality == 0:
		fwd_amount = -0.7 if dist > 12.0 else 0.35
	else:
		if dist > 18.0:
			fwd_amount = -1.0
		elif dist < 9.0:
			fwd_amount = 1.0
	var side := sin(Time.get_ticks_msec() / 650.0 + float(get_instance_id() % 10)) * strafe_sign
	move_input = Vector2(side, fwd_amount)
	var has_ammo := ammo_mag > 0 or ammo_reserve > 0
	# Short spray then pause (burst_cd) so player can hide
	var can_spray := dist < 26.0 and burst_cd <= 0.0 and has_ammo and reloading <= 0.0
	fire_held = can_spray
	if not has_ammo:
		if ammo_reserve > 0 and reloading <= 0.0:
			start_reload()
		move_input = Vector2(0, -1)
		fire_held = false
	# Start a burst pause more often so bots don't laser forever
	if burst_cd <= 0.0 and randf() < 0.35:
		burst_cd = randf_range(0.7, 1.6) * float(bm["burst"])
		if randf() < 0.35:
			strafe_sign = -strafe_sign
	if Settings.difficulty == 2 and nade_cd <= 0.0 and grenades > 0 and dist < 26.0 and dist > 8.0:
		if not _has_los(target) or randf() < 0.3:
			nade_cd = 12.0
			throw_grenade(target.global_position)
