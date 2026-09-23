extends Node
## Procedural SFX - no audio files, all generated in code.

const RATE := 22050

var bank := {}
var players: Array = []


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	bank["rifle"] = _shot(0.14, 0.85, 950.0)
	bank["smg"] = _shot(0.09, 0.7, 1450.0)
	bank["sniper"] = _shot(0.38, 1.0, 320.0)
	bank["boom"] = _explosion()
	bank["hurt"] = _tone(175.0, 0.16, 0.7)
	bank["reload"] = _tone(700.0, 0.09, 0.45)
	bank["pickup"] = _tone(880.0, 0.12, 0.5)
	bank["ui"] = _tone(600.0, 0.05, 0.4)
	bank["warn"] = _tone(520.0, 0.28, 0.6)
	bank["chute"] = _noise(0.85, 0.3)
	bank["thud"] = _tone(110.0, 0.22, 0.85)


func _bytes(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size())
	for i in samples.size():
		data[i] = int(clampf(samples[i], -1.0, 1.0) * 100.0 + 128.0)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _tone(freq: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var k := float(i) / float(n)
		s[i] = sin(TAU * freq * float(i) / RATE) * vol * (1.0 - k)
	return _bytes(s)


func _noise(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var k := float(i) / float(n)
		s[i] = randf_range(-1.0, 1.0) * vol * (1.0 - k)
	return _bytes(s)


func _shot(dur: float, vol: float, body_freq: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var k := float(i) / float(n)
		var env := (1.0 - k) * (1.0 - k)
		s[i] = (randf_range(-1.0, 1.0) * 0.7 + sin(TAU * body_freq * float(i) / RATE) * 0.5) * vol * env
	return _bytes(s)


func _explosion() -> AudioStreamWAV:
	var dur := 0.75
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var k := float(i) / float(n)
		var f := 115.0 * (1.0 - k) + 32.0
		s[i] = (sin(TAU * f * float(i) / RATE) * 0.8 + randf_range(-1.0, 1.0) * 0.5) * (1.0 - k)
	return _bytes(s)


func play(sfx_name: String, vol_db := 0.0) -> void:
	if not bank.has(sfx_name):
		return
	for p in players:
		if not (p as AudioStreamPlayer).playing:
			(p as AudioStreamPlayer).stream = bank[sfx_name]
			(p as AudioStreamPlayer).volume_db = vol_db
			(p as AudioStreamPlayer).play()
			return


func buzz(ms: int) -> void:
	if OS.has_feature("android"):
		Input.vibrate_handheld(ms)
