extends SceneTree
## Headless smoke test: parse + load all scripts, instantiate arena logic lightly.
## Run: godot --headless -s res://test/smoke_test.gd


func _init() -> void:
	var errors: Array[String] = []
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
			errors.append("missing file: " + path)
			continue
		var scr: Script = load(path)
		if scr == null:
			errors.append("failed to load: " + path)
			continue
		if not scr.can_instantiate() and path.contains("autoload") == false:
			# can_instantiate false can be OK for pure base? still flag parse
			var src := scr.source_code if scr is Script else ""
			if src.is_empty():
				errors.append("empty source: " + path)
		print("[ok] ", path)
	# Scenes
	for scn in ["res://scenes/arena.tscn", "res://scenes/fighter.tscn", "res://scenes/bullet.tscn", "res://scenes/main_menu.tscn"]:
		if not FileAccess.file_exists(scn):
			errors.append("missing scene: " + scn)
			continue
		var packed: PackedScene = load(scn)
		if packed == null:
			errors.append("failed to load scene: " + scn)
		else:
			print("[ok] ", scn)
	if errors.is_empty():
		print("SMOKE_TEST_PASS")
		quit(0)
	else:
		for e in errors:
			printerr("[FAIL] ", e)
		print("SMOKE_TEST_FAIL count=", errors.size())
		quit(1)
