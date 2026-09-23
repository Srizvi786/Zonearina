extends SceneTree
## Headless smoke test: runs AFTER autoloads exist (use as main script via project boot alternative).
## Preferred CI path: godot --headless --quit-after 30
## This script only validates resources when autoloads are present.

func _initialize() -> void:
	# Defer to first process so Settings/Sfx autoloads are in the tree.
	pass


func _process(_delta: float) -> bool:
	var errors: Array[String] = []
	if root == null:
		print("SMOKE_TEST_FAIL no root")
		quit(1)
		return true
	for n in ["Settings", "Sfx"]:
		if root.get_node_or_null(n) == null and get_root().get_node_or_null(n) == null:
			# also check global
			var found := false
			for c in get_root().get_children():
				if c.name == n:
					found = true
					break
			if not found:
				errors.append("missing autoload: " + n)
	var scripts := [
		"res://scripts/arena.gd",
		"res://scripts/fighter.gd",
		"res://scripts/bullet.gd",
		"res://scripts/hud.gd",
		"res://scripts/pickup.gd",
		"res://scripts/grenade.gd",
		"res://scripts/main_menu.gd",
		"res://scripts/autoload/settings.gd",
		"res://scripts/autoload/sfx.gd",
	]
	for path in scripts:
		if not FileAccess.file_exists(path):
			errors.append("missing: " + path)
	# Scenes loadable
	for scn in ["res://scenes/arena.tscn", "res://scenes/fighter.tscn", "res://scenes/bullet.tscn", "res://scenes/main_menu.tscn"]:
		var packed = load(scn)
		if packed == null:
			errors.append("failed scene: " + scn)
		else:
			print("[ok] ", scn)
	if errors.is_empty():
		print("SMOKE_TEST_PASS")
		quit(0)
		return true
	for e in errors:
		printerr("[FAIL] ", e)
	print("SMOKE_TEST_FAIL count=", errors.size())
	quit(1)
	return true
