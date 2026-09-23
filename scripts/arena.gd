extends Node3D
## Arena: town map, plane drop, loot, blue zone, bots, win/lose.

const FIGHTER_SCENE := preload("res://scenes/fighter.tscn")
const BOT_COUNT := 11
const ARENA_HALF := 60.0

const PHASES := [
	{"wait": 16.0, "shrink": 24.0, "radius": 40.0},
	{"wait": 12.0, "shrink": 20.0, "radius": 26.0},
	{"wait": 10.0, "shrink": 16.0, "radius": 15.0},
	{"wait": 8.0, "shrink": 14.0, "radius": 7.0},
	{"wait": 7.0, "shrink": 12.0, "radius": 0.5},
]

const BOT_NAMES := ["Viper", "Jinx", "Raka", "Sheru", "Ghost", "Toofan", "Kalia", "Zed", "Rogue", "Tiger", "Blaze", "Cobra"]
const LOOT_TABLE := ["smg", "smg", "ammo", "ammo", "medkit", "bandage", "bandage", "drink", "helmet", "vest", "grenade", "sniper", "extmag"]

var fighters: Array = []
var player: Fighter
var hud: CanvasItem
var state := "plane"  # plane -> chute -> play -> end
var match_t := 0.0

var zone_center := Vector2.ZERO
var zone_radius := 58.0
var zone_from := 58.0
var zone_to := 40.0
var zone_phase := 0
var zone_t := 0.0
var zone_state := "wait"
var zone_dps := 6.0

var houses: Array = []
var grass_spots: Array = []
var bullet_pool: Array = []
var dmg_labels: Array = []
var spark_count := 0
var particles_on := true

var plane: Node3D
var plane_t := 0.0
var plane_from := Vector3(-95, 60, -55)
var plane_to := Vector3(95, 60, 55)
var plane_dur := 22.0
var reminded_1 := false
var reminded_2 := false
var flight_cam: Camera3D
var jumped := false
var chute: Node3D
var land_target := Vector2.ZERO
var has_target := false
var beacon: MeshInstance3D
var props: Array = []
var blink_t := 0.0
var nav_red: MeshInstance3D
var nav_green: MeshInstance3D

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial


func is_live() -> bool:
	return state == "play"


func _ready() -> void:
	randomize()
	_build_sky()
	_build_ground()
	_build_town()
	_build_towers()
	_build_props()
	_build_military_props()
	_build_zone_visual()
	_spawn_loot()
	_spawn_fighters()
	_start_plane()
	hud = get_node("HUD")
	hud.call("bind", player, self)
	_apply_graphics()


func _apply_graphics() -> void:
	var g := Settings.graphics
	sun.shadow_enabled = g > 0
	sun.directional_shadow_max_distance = 55.0 if g < 2 else 100.0
	particles_on = g > 0
	if player != null and player.cam != null:
		player.cam.far = [150.0, 200.0, 260.0][clampi(g, 0, 2)]


func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material, collide := true) -> StaticBody3D:
	var st := StaticBody3D.new()
	st.position = pos
	if collide:
		var c := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = size
		c.shape = s
		st.add_child(c)
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	st.add_child(mi)
	parent.add_child(st)
	return st


func _mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _build_sky() -> void:
	sun = DirectionalLight3D.new()
	# Golden-hour military ops look (PUBG dusk vibe)
	sun.rotation = Vector3(-0.75, 0.9, 0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_split_1 = 0.12
	sun.directional_shadow_split_2 = 0.3
	add_child(sun)
	# Subtle fill light so shadows aren't pure black
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-1.2, -0.5, 0)
	fill.light_energy = 0.25
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.shadow_enabled = false
	add_child(fill)
	var env_node := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.35, 0.62)
	sky_mat.sky_horizon_color = Color(0.78, 0.72, 0.55)
	sky_mat.ground_bottom_color = Color(0.18, 0.2, 0.16)
	sky_mat.ground_horizon_color = Color(0.55, 0.5, 0.4)
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.ambient_light_sky_contribution = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.72, 0.62)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.15
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.ssao_radius = 1.5
	env_node.environment = env
	add_child(env_node)
	# Ring mountains
	var mtn_m := _mat(Color(0.28, 0.34, 0.26))
	var mtn_far := _mat(Color(0.35, 0.38, 0.42))
	for i in 12:
		var a := TAU * i / 12.0
		var mtn := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = randf_range(1.0, 3.0)
		cone.bottom_radius = randf_range(16.0, 28.0)
		cone.height = randf_range(28.0, 48.0)
		cone.radial_segments = 8
		mtn.mesh = cone
		mtn.material_override = mtn_m if i % 2 == 0 else mtn_far
		mtn.position = Vector3(cos(a) * 108.0, 6.0, sin(a) * 108.0)
		add_child(mtn)
	# Volumetric-ish cloud slabs
	var cloud_m := StandardMaterial3D.new()
	cloud_m.albedo_color = Color(1, 0.98, 0.95)
	cloud_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_m.albedo_color.a = 0.85
	for i in 10:
		var cl := MeshInstance3D.new()
		var cs := SphereMesh.new()
		cs.radius = 1.0
		cs.height = 1.0
		cl.mesh = cs
		cl.material_override = cloud_m
		cl.scale = Vector3(randf_range(10, 18), randf_range(1.2, 2.2), randf_range(5, 9))
		cl.position = Vector3(randf_range(-95, 95), randf_range(50, 78), randf_range(-95, 95))
		add_child(cl)


func _build_ground() -> void:
	var ground_body := StaticBody3D.new()
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(140, 1, 140)
	gc.shape = gs
	gc.position = Vector3(0, -0.5, 0)
	ground_body.add_child(gc)
	var gm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 140)
	gm.mesh = plane
	# Muted dirt-grass blend (PUBG Erangel vibe)
	gm.material_override = _mat(Color(0.32, 0.38, 0.22), 0.95)
	# Patch variation meshes
	var patch_m := _mat(Color(0.4, 0.36, 0.24), 0.98)
	var dark_m := _mat(Color(0.22, 0.3, 0.16), 0.95)
	for i in 40:
		var p := MeshInstance3D.new()
		var pm2 := PlaneMesh.new()
		var ps := randf_range(3, 9)
		pm2.size = Vector2(ps, ps * randf_range(0.6, 1.4))
		p.mesh = pm2
		p.material_override = patch_m if i % 3 else dark_m
		p.position = Vector3(randf_range(-62, 62), 0.02, randf_range(-62, 62))
		p.rotation.y = randf() * TAU
		add_child(p)
	ground_body.add_child(gm)
	add_child(ground_body)
	var road_m := _mat(Color(0.16, 0.16, 0.17))
	var dash_m := _mat(Color(0.85, 0.85, 0.8))
	for axis in ["x", "z"]:
		var r := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(132, 7) if axis == "x" else Vector2(7, 132)
		r.mesh = pm
		r.material_override = road_m
		r.position = Vector3(0, 0.03, 0)
		add_child(r)
		for d in range(-60, 61, 6):
			var dash := MeshInstance3D.new()
			var dm := BoxMesh.new()
			dm.size = Vector3(2, 0.02, 0.4) if axis == "x" else Vector3(0.4, 0.02, 2)
			dash.mesh = dm
			dash.material_override = dash_m
			dash.position = Vector3(d, 0.05, 0) if axis == "x" else Vector3(0, 0.05, d)
			add_child(dash)
	var wall_m := _mat(Color(0.3, 0.3, 0.32))
	for i in 4:
		if i < 2:
			_box(self, Vector3(128, 6, 2), Vector3(0, 3, -64.0 if i == 0 else 64.0), wall_m)
		else:
			_box(self, Vector3(2, 6, 128), Vector3(-64.0 if i == 2 else 64.0, 3, 0), wall_m)


func _house(pos: Vector3, yaw: float, w := 8.0, d := 7.0, h := 3.2) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var wall_m := _mat(Color(0.75, 0.68, 0.55))
	var trim_m := _mat(Color(0.5, 0.2, 0.15))
	var t := 0.3
	_box(root, Vector3(w + 1, 0.2, d + 1), Vector3(0, 0.1, 0), _mat(Color(0.5, 0.47, 0.42)))
	_box(root, Vector3(w + 1.4, 0.3, d + 1.4), Vector3(0, h + 0.15, 0), trim_m)
	var door := 2.0
	var seg := (w - door) / 2.0
	_box(root, Vector3(seg, h, t), Vector3(-(door / 2 + seg / 2), h / 2, -d / 2), wall_m)
	_box(root, Vector3(seg, h, t), Vector3(door / 2 + seg / 2, h / 2, -d / 2), wall_m)
	_box(root, Vector3(door, h - 2.2, t), Vector3(0, 2.2 + (h - 2.2) / 2, -d / 2), wall_m)
	var win := 1.4
	var segb := (w - win) / 2.0
	_box(root, Vector3(segb, h, t), Vector3(-(win / 2 + segb / 2), h / 2, d / 2), wall_m)
	_box(root, Vector3(segb, h, t), Vector3(win / 2 + segb / 2, h / 2, d / 2), wall_m)
	_box(root, Vector3(win, 1.0, t), Vector3(0, 0.5, d / 2), wall_m)
	_box(root, Vector3(win, h - 2.2, t), Vector3(0, 2.2 + (h - 2.2) / 2, d / 2), wall_m)
	_box(root, Vector3(t, h, d), Vector3(-w / 2, h / 2, 0), wall_m)
	var segd := (d - win) / 2.0
	_box(root, Vector3(t, h, segd), Vector3(w / 2, h / 2, -(win / 2 + segd / 2)), wall_m)
	_box(root, Vector3(t, h, segd), Vector3(w / 2, h / 2, win / 2 + segd / 2), wall_m)
	_box(root, Vector3(t, 1.0, win), Vector3(w / 2, 0.5, 0), wall_m)
	_box(root, Vector3(t, h - 2.2, win), Vector3(w / 2, 2.2 + (h - 2.2) / 2, 0), wall_m)
	_box(root, Vector3(1.4, 1.4, 1.4), Vector3(w / 2 - 1.4, 0.9, d / 2 - 1.4), _mat(Color(0.45, 0.35, 0.22)))
	houses.append({"pos": Vector2(pos.x, pos.z), "size": Vector2(w, d)})


func _build_town() -> void:
	var spots := [
		[Vector3(-14, 0, -12), 0.2], [Vector3(12, 0, -14), -0.15], [Vector3(-13, 0, 14), 0.1],
		[Vector3(14, 0, 12), 0.3], [Vector3(-28, 0, 2), 1.57], [Vector3(28, 0, -22), 1.57],
		[Vector3(-30, 0, 32), 0.0], [Vector3(32, 0, 34), -0.2], [Vector3(2, 0, -32), 3.14],
		[Vector3(-4, 0, 30), 3.0],
	]
	for s in spots:
		_house(s[0], s[1])
	# Warehouse floor pad
	var gp := Vector3(28, 0, -22)
	_box(self, Vector3(14, 0.2, 11), Vector3(gp.x, 0.1, gp.z), _mat(Color(0.45, 0.45, 0.48)))
	houses.append({"pos": Vector2(gp.x, gp.z), "size": Vector2(14, 11)})


func _tower(pos: Vector3, floors := 3) -> void:
	var w := 10.0
	var d := 9.0
	var fh := 3.0
	var t := 0.35
	var wall_m := _mat(Color(0.62, 0.58, 0.5))
	var slab_m := _mat(Color(0.5, 0.48, 0.44))
	_box(self, Vector3(w + 1, 0.2, d + 1), Vector3(pos.x, 0.1, pos.z), slab_m)
	for f in floors:
		var y0 := 0.2 + f * fh
		for side in 4:
			var horiz := side < 2
			var off := (d / 2 if horiz else w / 2) * (1.0 if side % 2 == 0 else -1.0)
			var len := w if horiz else d
			var px := pos.x + (0.0 if horiz else off)
			var pz := pos.z + (off if horiz else 0.0)
			if f == 0 and ((horiz and side == 1) or (not horiz and side == 2)):
				var door := 1.8
				var seg := (len - door) / 2.0
				if horiz:
					_box(self, Vector3(seg, fh, t), Vector3(-door / 2 - seg / 2, y0 + fh / 2, pz), wall_m)
					_box(self, Vector3(seg, fh, t), Vector3(door / 2 + seg / 2, y0 + fh / 2, pz), wall_m)
					_box(self, Vector3(door, fh - 2.2, t), Vector3(0, y0 + 2.2 + (fh - 2.2) / 2, pz), wall_m)
				else:
					_box(self, Vector3(t, fh, seg), Vector3(px, y0 + fh / 2, -door / 2 - seg / 2), wall_m)
					_box(self, Vector3(t, fh, seg), Vector3(px, y0 + fh / 2, door / 2 + seg / 2), wall_m)
					_box(self, Vector3(t, fh - 2.2, door), Vector3(px, y0 + 2.2 + (fh - 2.2) / 2, 0), wall_m)
			else:
				if horiz:
					_box(self, Vector3(len, 1.1, t), Vector3(px, y0 + 0.55, pz), wall_m)
					_box(self, Vector3(len, fh - 2.1, t), Vector3(px, y0 + 2.1 + (fh - 2.1) / 2, pz), wall_m)
				else:
					_box(self, Vector3(t, 1.1, len), Vector3(px, y0 + 0.55, pz), wall_m)
					_box(self, Vector3(t, fh - 2.1, len), Vector3(px, y0 + 2.1 + (fh - 2.1) / 2, pz), wall_m)
		if f < floors - 1:
			_box(self, Vector3(4.2, 0.25, d), Vector3(pos.x + 2.9, y0 + fh, pos.z), slab_m)
		# Stairs ramp
		var ramp := StaticBody3D.new()
		ramp.position = Vector3(pos.x - 2.1, y0 + 1.45, pos.z + d / 2 - 1.2)
		ramp.rotation.z = 0.578
		var rc := CollisionShape3D.new()
		var rs := BoxShape3D.new()
		rs.size = Vector3(6.2, 0.2, 1.8)
		rc.shape = rs
		ramp.add_child(rc)
		self.add_child(ramp)
		for s in 10:
			_box(self, Vector3(0.45, 0.28, 1.8), Vector3(pos.x - 4.4 + s * 0.46, y0 + 0.25 + s * 0.3, pos.z + d / 2 - 1.2), slab_m, false)
	var ry := 0.2 + floors * fh
	_box(self, Vector3(w + 0.6, 1.2, 0.3), Vector3(pos.x, ry + 0.7, pos.z - d / 2), wall_m)
	_box(self, Vector3(w + 0.6, 1.2, 0.3), Vector3(pos.x, ry + 0.7, pos.z + d / 2), wall_m)
	_box(self, Vector3(0.3, 1.2, d + 0.6), Vector3(pos.x - w / 2, ry + 0.7, pos.z), wall_m)
	_box(self, Vector3(0.3, 1.2, d + 0.6), Vector3(pos.x + w / 2, ry + 0.7, pos.z), wall_m)
	spawn_pickup("sniper", pos + Vector3(0, ry + 0.4, 0))
	spawn_pickup("medkit", pos + Vector3(2, ry + 0.4, 1))
	houses.append({"pos": Vector2(pos.x, pos.z), "size": Vector2(w + 1, d + 1)})


func _build_towers() -> void:
	_tower(Vector3(-22, 0, -38), 3)
	_tower(Vector3(26, 0, 38), 3)


func _build_props() -> void:
	var trunk_m := _mat(Color(0.35, 0.25, 0.15))
	var leaf_m := _mat(Color(0.15, 0.45, 0.18))
	var rock_m := _mat(Color(0.45, 0.45, 0.47))
	var bar_m := _mat(Color(0.6, 0.2, 0.15))
	var grass_m := _mat(Color(0.18, 0.38, 0.16))
	for i in 26:
		var pos := Vector3(randf_range(-55, 55), 0, randf_range(-55, 55))
		if abs(pos.x) < 6.0 or abs(pos.z) < 6.0:
			continue
		if pos.length() < 12.0:
			continue
		if i % 3 == 0:
			var tr := MeshInstance3D.new()
			var tc := CylinderMesh.new()
			tc.top_radius = 0.25
			tc.bottom_radius = 0.35
			tc.height = 3.0
			tr.mesh = tc
			tr.material_override = trunk_m
			tr.position = pos + Vector3(0, 1.5, 0)
			add_child(tr)
			var lf := MeshInstance3D.new()
			var ls := SphereMesh.new()
			ls.radius = 1.8
			ls.height = 3.2
			lf.mesh = ls
			lf.material_override = leaf_m
			lf.position = pos + Vector3(0, 4.2, 0)
			add_child(lf)
		elif i % 3 == 1:
			var rk := MeshInstance3D.new()
			var rs := SphereMesh.new()
			rs.radius = randf_range(0.8, 1.6)
			rs.height = rs.radius * 1.2
			rk.mesh = rs
			rk.material_override = rock_m
			rk.position = pos + Vector3(0, 0.4, 0)
			add_child(rk)
		else:
			var dr := MeshInstance3D.new()
			var dc := CylinderMesh.new()
			dc.top_radius = 0.5
			dc.bottom_radius = 0.5
			dc.height = 1.2
			dr.mesh = dc
			dr.material_override = bar_m
			dr.position = pos + Vector3(0, 0.6, 0)
			add_child(dr)
	for i in 18:
		var gpos := Vector2(randf_range(-50, 50), randf_range(-50, 50))
		var r := randf_range(2.0, 3.5)
		var g := MeshInstance3D.new()
		var gc := CylinderMesh.new()
		gc.top_radius = r
		gc.bottom_radius = r
		gc.height = 0.08
		g.mesh = gc
		g.material_override = grass_m
		g.position = Vector3(gpos.x, 0.06, gpos.y)
		add_child(g)
		grass_spots.append({"pos": gpos, "r": r})
	var pole_m := _mat(Color(0.2, 0.2, 0.22))
	for d in [-40, -20, 20, 40]:
		for off in [5.5, -5.5]:
			_box(self, Vector3(0.25, 6, 0.25), Vector3(d, 3, off), pole_m)


func _build_military_props() -> void:
	# Sandbag bunkers (PUBG cover)
	var sand := _mat(Color(0.55, 0.48, 0.32), 0.95)
	var wood_c := _mat(Color(0.4, 0.28, 0.16), 0.85)
	var metal_c := _mat(Color(0.35, 0.36, 0.38), 0.4, 0.6)
	var crate_c := _mat(Color(0.42, 0.35, 0.2), 0.9)
	var bunker_spots := [
		Vector3(-8, 0, -26), Vector3(20, 0, 8), Vector3(-36, 0, 10),
		Vector3(8, 0, 40), Vector3(-18, 0, -4),
	]
	for bp in bunker_spots:
		# Stack of sandbags
		for row in 3:
			for i in 4:
				var off := Vector3(-1.5 + i * 1.0, 0.35 + row * 0.35, 0)
				var bag := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.9, 0.32, 0.5)
				bag.mesh = bm
				bag.material_override = sand
				bag.position = bp + off
				bag.rotation.y = randf_range(-0.1, 0.1)
				add_child(bag)
				if row == 0 and i == 0:
					var c := StaticBody3D.new()
					c.position = bp + Vector3(0, 0.7, 0)
					var col := CollisionShape3D.new()
					var sh := BoxShape3D.new()
					sh.size = Vector3(4.2, 1.2, 0.7)
					col.shape = sh
					c.add_child(col)
					add_child(c)
		# Ammo crate beside
		_box(self, Vector3(1.1, 0.7, 0.8), bp + Vector3(2.5, 0.35, 0.5), crate_c)
		if randf() < 0.6:
			spawn_pickup("ammo", bp + Vector3(2.5, 0.4, 0.5))
	# Shipping containers / warehouse props
	var cont_colors := [Color(0.55, 0.2, 0.15), Color(0.15, 0.35, 0.5), Color(0.25, 0.4, 0.2)]
	var cont_spots := [
		[Vector3(34, 0, -14), 0.0], [Vector3(-40, 0, -20), 1.57],
		[Vector3(40, 0, 20), 0.4], [Vector3(-10, 0, 48), 0.0],
	]
	for i in cont_spots.size():
		var pos: Vector3 = cont_spots[i][0]
		var yaw: float = cont_spots[i][1]
		var root := Node3D.new()
		root.position = pos + Vector3(0, 1.3, 0)
		root.rotation.y = yaw
		add_child(root)
		var cm := _mat(cont_colors[i % cont_colors.size()], 0.7, 0.25)
		_box(root, Vector3(2.4, 2.6, 6.0), Vector3.ZERO, cm)
		# Corrugated ribs
		for r in 6:
			_box(root, Vector3(2.5, 0.1, 0.15), Vector3(0, -1 + r * 0.4, -2.9), _mat(Color(0.2, 0.2, 0.2), 0.5, 0.5))
		# Collision
		var cb := StaticBody3D.new()
		cb.position = pos + Vector3(0, 1.3, 0)
		cb.rotation.y = yaw
		var cc := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = Vector3(2.4, 2.6, 6.0)
		cc.shape = cs
		cb.add_child(cc)
		add_child(cb)
		houses.append({"pos": Vector2(pos.x, pos.z), "size": Vector2(2.4, 6.0)})
	# Barrels
	for i in 12:
		var pos := Vector3(randf_range(-50, 50), 0, randf_range(-50, 50))
		if abs(pos.x) < 8 and abs(pos.z) < 8:
			continue
		var barrel := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.4
		bc.bottom_radius = 0.4
		bc.height = 1.1
		bc.radial_segments = 10
		barrel.mesh = bc
		var bcol := Color(0.5, 0.15, 0.1) if i % 2 == 0 else Color(0.15, 0.3, 0.45)
		barrel.material_override = _mat(bcol, 0.55, 0.4)
		barrel.position = pos + Vector3(0, 0.55, 0)
		add_child(barrel)
		# collision barrel
		var bs := StaticBody3D.new()
		bs.position = barrel.position
		var bcc := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.4
		cyl.height = 1.1
		bcc.shape = cyl
		bs.add_child(bcc)
		add_child(bs)
	# Wire fence segments
	var post_m := _mat(Color(0.3, 0.3, 0.32), 0.4, 0.7)
	for seg in 8:
		var ang := TAU * seg / 8.0 + 0.3
		var c0 := Vector3(cos(ang) * 48, 0, sin(ang) * 48)
		var c1 := Vector3(cos(ang + 0.35) * 48, 0, sin(ang + 0.35) * 48)
		# posts
		_box(self, Vector3(0.12, 1.6, 0.12), c0 + Vector3(0, 0.8, 0), post_m)
		_box(self, Vector3(0.12, 1.6, 0.12), c1 + Vector3(0, 0.8, 0), post_m)
		# rail
		var mid := (c0 + c1) * 0.5
		var len := c0.distance_to(c1)
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.06, 0.06, len)
		rail.mesh = rm
		rail.material_override = post_m
		rail.position = mid + Vector3(0, 1.4, 0)
		rail.look_at(c1 + Vector3(0, 1.4, 0))
		add_child(rail)


func _build_zone_visual() -> void:
	var zone_shell := MeshInstance3D.new()
	zone_shell.name = "ZoneShell"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 36.0
	cyl.radial_segments = 48
	zone_shell.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.28)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	zone_shell.material_override = mat
	zone_shell.position = Vector3(0, 17, 0)
	add_child(zone_shell)
	_update_zone_visual()


func _update_zone_visual() -> void:
	var zs := get_node_or_null("ZoneShell") as MeshInstance3D
	if zs == null:
		return
	zs.scale = Vector3(zone_radius, 1, zone_radius)
	zs.position = Vector3(zone_center.x, 17, zone_center.y)


func _spawn_loot() -> void:
	for h in houses:
		var hp: Vector2 = h["pos"]
		var n := 2 if randf() < 0.4 else 1
		for i in n:
			var kind: String = LOOT_TABLE[randi() % LOOT_TABLE.size()]
			var off := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			spawn_pickup(kind, Vector3(hp.x, 0.4, hp.y) + off)
	for i in 6:
		var kind2: String = LOOT_TABLE[randi() % LOOT_TABLE.size()]
		spawn_pickup(kind2, Vector3(randf_range(-40, 40), 0.4, randf_range(-40, 40)))


func spawn_pickup(kind: String, pos: Vector3) -> void:
	var p := Pickup.make(kind, pos)
	add_child(p)


func _spawn_fighters() -> void:
	var total := BOT_COUNT + 1
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	for i in total:
		var f: Fighter = FIGHTER_SCENE.instantiate()
		var ang := TAU * float(i) / float(total)
		var r := 42.0
		var pos := Vector3(cos(ang) * r, 1.0, sin(ang) * r)
		# Set appearance BEFORE add_child so _ready builds correct look
		if i == 0:
			f.is_player = true
			f.fname = "YOU"
			f.body_color = Color(0.25, 0.3, 0.22)
			f.camo_accent = Color(0.18, 0.22, 0.15)
			f.skin_color = Color(0.8, 0.6, 0.46)
			f.helmet = true
			f.vest = true
			player = f
		else:
			f.fname = str(names[i % names.size()]) + "-" + str(i)
			var palettes := [
				[Color(0.3, 0.32, 0.24), Color(0.2, 0.22, 0.16)],
				[Color(0.35, 0.28, 0.18), Color(0.22, 0.18, 0.12)],
				[Color(0.22, 0.28, 0.3), Color(0.15, 0.18, 0.2)],
				[Color(0.4, 0.36, 0.28), Color(0.25, 0.22, 0.16)],
				[Color(0.28, 0.24, 0.2), Color(0.18, 0.15, 0.12)],
				[Color(0.32, 0.3, 0.22), Color(0.2, 0.2, 0.14)],
			]
			var pal: Array = palettes[i % palettes.size()]
			f.body_color = pal[0]
			f.camo_accent = pal[1]
			f.skin_color = Color.from_hsv(0.07, 0.35, randf_range(0.55, 0.85))
			f.personality = randi() % 3
			f.grenades = 1
			f.ammo_reserve = 60
			f.helmet = randf() < 0.5
			f.vest = randf() < 0.4
			f.aim_yaw = randf() * TAU
		f.position = pos
		f.set_physics_process(false)
		f.think_cd = randf() * 0.25
		f.wander_cd = randf() * 3.0
		add_child(f)
		f.died.connect(_on_fighter_died)
		fighters.append(f)


func _build_c130() -> void:
	var camo := _mat(Color(0.32, 0.38, 0.25), 0.6)
	var camo_d := _mat(Color(0.22, 0.28, 0.18), 0.6)
	var dark := _mat(Color(0.1, 0.11, 0.12), 0.5)
	_box(plane, Vector3(4, 3.6, 20), Vector3.ZERO, camo, false)
	_box(plane, Vector3(3.4, 2.8, 3), Vector3(0, -0.2, -11), camo, false)
	_box(plane, Vector3(3.0, 1.2, 1.2), Vector3(0, 0.9, -11.2), dark, false)
	_box(plane, Vector3(3.2, 0.3, 4), Vector3(0, -1.9, 11.5), dark, false)
	_box(plane, Vector3(3.6, 2.6, 0.4), Vector3(0, 0.6, 9.8), camo, false)
	_box(plane, Vector3(28, 0.5, 4), Vector3(0, 1.2, -1), camo, false)
	_box(plane, Vector3(0.5, 5, 3.5), Vector3(0, 3.5, 9), camo, false)
	for x in [-10.5, -4.5, 4.5, 10.5]:
		var nac := MeshInstance3D.new()
		var nc := CylinderMesh.new()
		nc.top_radius = 0.7
		nc.bottom_radius = 0.7
		nc.height = 3.0
		nac.mesh = nc
		nac.material_override = camo_d
		nac.rotation.x = PI / 2.0
		nac.position = Vector3(x, 0.6, -2.2)
		plane.add_child(nac)
		var pivot := Node3D.new()
		pivot.position = Vector3(x, 0.6, -3.9)
		plane.add_child(pivot)
		var blade_m := _mat(Color(0.12, 0.12, 0.13), 0.4)
		for a in [0.0, PI / 2.0]:
			var bl := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.35, 4.2, 0.12)
			bl.mesh = bb
			bl.material_override = blade_m
			bl.rotation.z = a
			pivot.add_child(bl)
		props.append(pivot)
	nav_red = _lamp(plane, Vector3(-14.2, 1.2, -1), Color(1, 0.1, 0.1))
	nav_green = _lamp(plane, Vector3(14.2, 1.2, -1), Color(0.1, 1, 0.2))


func _lamp(parent: Node, pos: Vector3, c: Color) -> MeshInstance3D:
	var l := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.25
	s.height = 0.5
	l.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 5.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	l.material_override = m
	l.position = pos
	parent.add_child(l)
	return l


func _start_plane() -> void:
	var ang := randf() * TAU
	var dir := Vector3(cos(ang), 0, sin(ang))
	plane_from = Vector3(zone_center.x, 60, zone_center.y) - dir * 95.0
	plane_to = Vector3(zone_center.x, 60, zone_center.y) + dir * 95.0
	plane = Node3D.new()
	plane.position = plane_from
	plane.rotation.y = atan2(-dir.x, -dir.z) + PI
	add_child(plane)
	_build_c130()
	set_land_target(zone_center, true)
	toast("Zone me utarne ke liye JUMP dabao!")
	flight_cam = Camera3D.new()
	flight_cam.position = plane_from + Vector3(-18, 8, 0)
	flight_cam.look_at(plane_from)
	flight_cam.current = true
	add_child(flight_cam)
	player.global_position = plane_from


func _physics_process(delta: float) -> void:
	if state == "plane":
		plane_t += delta
		var k: float = clampf(plane_t / plane_dur, 0.0, 1.0)
		plane.position = plane_from.lerp(plane_to, k)
		for pr in props:
			(pr as Node3D).rotation.z += delta * 25.0
		blink_t += delta
		var bl := sin(blink_t * 6.0) > 0.0
		if nav_red != null:
			nav_red.visible = bl
		if nav_green != null:
			nav_green.visible = not bl
		player.global_position = plane.position + Vector3(0, -1, 0)
		flight_cam.position = plane.position + Vector3(-20, 9, 0)
		flight_cam.look_at(plane.position)
		if hud != null:
			var over := Vector2(plane.position.x, plane.position.z).distance_to(zone_center) < zone_radius
			hud.call("set_plane_hint", over)
		if k > 0.45 and not reminded_1:
			reminded_1 = true
			toast("Zone neeche hai - JUMP dabao!")
			Sfx.play("warn")
		if k > 0.75 and not reminded_2:
			reminded_2 = true
			toast("LAST CHANCE - JUMP!")
			Sfx.play("warn")
		if k >= 1.0 and not jumped:
			player_jump()


func player_jump() -> void:
	if state != "plane" or jumped:
		return
	jumped = true
	player.global_position = plane.position + Vector3(0, -2, 0)
	player.set_physics_process(false)
	chute = Node3D.new()
	var can := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.2
	sm.height = 1.6
	can.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1, 0.45, 0.1)
	cm.roughness = 0.9
	can.material_override = cm
	can.scale = Vector3(1.4, 0.55, 1.4)
	can.position = Vector3(0, 4.2, 0)
	chute.add_child(can)
	player.add_child(chute)
	if flight_cam != null:
		flight_cam.queue_free()
		flight_cam = null
	player.cam.current = true
	state = "chute"
	toast("Parachute khula! Jagah chuno.")
	Sfx.play("chute")


func _process(delta: float) -> void:
	if state == "plane":
		return
	if state == "chute":
		_chute_fall(delta)
		return
	if state != "play":
		return
	match_t += delta
	_update_zone(delta)
	_zone_damage(delta)
	_update_sunset()
	if hud != null:
		var hpv := 0.0
		var kl := 0
		if player != null:
			if player.alive:
				hpv = player.hp
			kl = player.kills
		hud.call("refresh", fighters.size(), _zone_text(), hpv, kl)


func set_land_target(p: Vector2, quiet := false) -> void:
	land_target = Vector2(clampf(p.x, -58.0, 58.0), clampf(p.y, -58.0, 58.0))
	has_target = true
	if beacon == null:
		beacon = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.2
		cyl.height = 90.0
		beacon.mesh = cyl
		var bm := StandardMaterial3D.new()
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.albedo_color = Color(1, 0.85, 0.2, 0.35)
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		beacon.material_override = bm
		add_child(beacon)
	beacon.visible = true
	beacon.position = Vector3(land_target.x, 45, land_target.y)
	if not quiet:
		toast("Target lock!")


func _chute_fall(delta: float) -> void:
	if player == null or not player.alive:
		return
	var steer := Vector3(player.move_input.x, 0, player.move_input.y)
	var wdir: Vector3 = Basis(Vector3.UP, player.aim_yaw) * steer
	player.global_position += (wdir * 8.0 + Vector3(0, -6.0, 0)) * delta
	player.rotation.y = player.aim_yaw
	player.global_position.x = clampf(player.global_position.x, -58.0, 58.0)
	player.global_position.z = clampf(player.global_position.z, -58.0, 58.0)
	var from: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -8, 0), 1, [player.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var landed := false
	if not hit.is_empty():
		var gy: float = (hit["position"] as Vector3).y
		if player.global_position.y - gy <= 0.25:
			player.global_position.y = gy + 0.05
			landed = true
	elif player.global_position.y <= 0.15:
		player.global_position.y = 0.1
		landed = true
	if landed:
		if chute != null:
			chute.queue_free()
			chute = null
		if beacon != null:
			beacon.visible = false
		has_target = false
		player.set_physics_process(true)
		player.velocity = Vector3.ZERO
		state = "play"
		for f in fighters:
			if f != player:
				(f as Fighter).set_physics_process(true)
		Sfx.play("thud")
		toast("Land ho gaye! Lado!")
		Sfx.play("warn")


func _update_zone(delta: float) -> void:
	if zone_phase >= PHASES.size():
		return
	var ph: Dictionary = PHASES[zone_phase]
	zone_t += delta
	if zone_state == "wait":
		if zone_t >= float(ph["wait"]):
			zone_t = 0.0
			zone_state = "shrink"
			zone_from = zone_radius
			zone_to = float(ph["radius"])
			var max_off: float = maxf(zone_from - zone_to, 0.0) * 0.6
			var a := randf() * TAU
			zone_center += Vector2(cos(a), sin(a)) * (randf() * max_off)
			toast("Zone chhota ho raha hai!")
			Sfx.play("warn")
	else:
		var dur: float = float(ph["shrink"])
		var k: float = clampf(zone_t / dur, 0.0, 1.0)
		zone_radius = lerpf(zone_from, zone_to, k)
		if k >= 1.0:
			zone_t = 0.0
			zone_state = "wait"
			zone_phase += 1
			zone_dps += 2.0
	_update_zone_visual()


func _zone_text() -> String:
	if zone_phase >= PHASES.size():
		return "FINAL ZONE!"
	if zone_state == "wait":
		var ph: Dictionary = PHASES[zone_phase]
		var left: int = int(ceil(float(ph["wait"]) - zone_t))
		return "Zone: %ds" % left
	return "GET TO ZONE!"


func _zone_damage(delta: float) -> void:
	for f in fighters.duplicate():
		if f == null or not (f as Fighter).alive:
			continue
		var me := Vector2((f as Fighter).global_position.x, (f as Fighter).global_position.z)
		if me.distance_to(zone_center) > zone_radius:
			(f as Fighter).take_damage(zone_dps * delta, null)


func get_zone_info() -> Dictionary:
	return {"center": zone_center, "radius": zone_radius}


func get_loot_point() -> Vector3:
	return Vector3(zone_center.x, 0, zone_center.y)


func get_bullet():
	for b in bullet_pool:
		if not b.active:
			return b
	if bullet_pool.size() >= 32:
		return null
	var nb = Fighter.BULLET_SCENE.instantiate()
	add_child(nb)
	nb.deactivate()
	bullet_pool.append(nb)
	return nb


func spawn_grenade(from_pos: Vector3, target: Vector3, shooter) -> void:
	var g := Grenade.make(from_pos, target, shooter)
	add_child(g)


func explode(pos: Vector3, dmg: float, radius: float, from) -> void:
	Sfx.play("boom")
	var flash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	flash.mesh = sm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1, 0.7, 0.3)
	fm.emission_enabled = true
	fm.emission = Color(1, 0.6, 0.2)
	fm.emission_energy_multiplier = 5.0
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = fm
	flash.position = pos + Vector3(0, 1, 0)
	add_child(flash)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * radius * 0.8, 0.25)
	tw.tween_property(fm, "emission_energy_multiplier", 0.0, 0.4)
	tw.chain().tween_callback(flash.queue_free)
	for n in get_tree().get_nodes_in_group("fighters"):
		var f := n as Fighter
		if f == null or not f.alive:
			continue
		var d: float = f.global_position.distance_to(pos)
		if d < radius:
			f.take_damage(dmg * (1.0 - d / radius * 0.6), from)
	if player != null and player.alive:
		var pd: float = player.global_position.distance_to(pos)
		if pd < radius * 1.5:
			Sfx.buzz(50)


func spark(pos: Vector3) -> void:
	if not particles_on or spark_count > 12:
		return
	spark_count += 1
	var s := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.12)
	s.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0.8, 0.3)
	m.emission_enabled = true
	m.emission = Color(1, 0.7, 0.2)
	m.emission_energy_multiplier = 4.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.material_override = m
	s.position = pos
	add_child(s)
	var tw := create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * 0.1, 0.18)
	tw.tween_callback(func() -> void:
		spark_count -= 1
		s.queue_free()
	)


func damage_number(pos: Vector3, amount: float, mine: bool) -> void:
	if dmg_labels.size() > 10:
		return
	var lab := Label3D.new()
	lab.text = str(int(amount))
	lab.font_size = 64
	lab.pixel_size = 0.01
	lab.modulate = Color(1, 0.9, 0.2) if mine else Color(1, 0.4, 0.35)
	lab.outline_size = 10
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = pos + Vector3(randf_range(-0.3, 0.3), 2.2, 0)
	add_child(lab)
	dmg_labels.append(lab)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "position:y", lab.position.y + 1.0, 0.7)
	tw.tween_property(lab, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(func() -> void:
		dmg_labels.erase(lab)
		lab.queue_free()
	)


func toast(msg: String) -> void:
	if hud != null:
		hud.call("toast", msg)


func hit_feedback() -> void:
	if hud != null and hud.has_method("show_hit"):
		hud.call("show_hit")


func killfeed(killer: String, victim: String) -> void:
	if hud != null:
		hud.call("feed", killer, victim)


func _on_fighter_died(f: Fighter) -> void:
	fighters.erase(f)
	spawn_pickup(f.gun, f.global_position)
	spawn_pickup("ammo", f.global_position + Vector3(1, 0, 0))
	var left := fighters.size()
	if f == player:
		state = "end"
		var rank := left + 1
		Settings.record_match(player.kills, rank, false)
		Sfx.play("hurt", 4.0)
		hud.call("show_end", false, rank, player.kills)
	else:
		var kn := "ZONE"
		if f.last_hit_by != null and f.last_hit_by is Fighter:
			kn = (f.last_hit_by as Fighter).fname
		elif f.last_hit_by != null:
			kn = "BOOM"
		killfeed(kn, f.fname)
		if left == 1 and player != null and player.alive:
			state = "end"
			Settings.record_match(player.kills, 1, true)
			_slowmo_win()
			hud.call("show_end", true, 1, player.kills)


func _slowmo_win() -> void:
	Sfx.play("pickup")
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.9, true, false, true).timeout
	Engine.time_scale = 1.0


func _update_sunset() -> void:
	var k: float = clampf(match_t / 260.0, 0.0, 1.0)
	sun.rotation.x = lerpf(-0.9, -0.4, k)
	sun.light_color = Color(1, lerpf(0.96, 0.6, k), lerpf(0.9, 0.35, k))
	if sky_mat != null:
		sky_mat.sky_top_color = Color(lerpf(0.25, 0.15, k), lerpf(0.5, 0.2, k), lerpf(0.85, 0.45, k))
		sky_mat.sky_horizon_color = Color(lerpf(0.7, 0.95, k), lerpf(0.85, 0.5, k), lerpf(0.95, 0.3, k))
	env.ambient_light_energy = lerpf(0.7, 0.45, k)
