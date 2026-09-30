extends Node
## Procedurally synthesised sound effects + audio bus setup.

const S = preload("res://src/audio/synth.gd")
const SR := 44100
const VOICES := 24

var bank := {}
var players: Array = []
var next_voice := 0
var ready_done := false
var _last_play := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	if DisplayServer.get_name() == "headless":
		return
	_build_bank()
	ready_done = true


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.35
		rev.damping = 0.6
		rev.wet = 0.12
		rev.dry = 1.0
		AudioServer.add_bus_effect(sfx, rev)
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		if ClassDB.class_exists("AudioEffectHardLimiter"):
			AudioServer.add_bus_effect(master, ClassDB.instantiate("AudioEffectHardLimiter"))
		else:
			AudioServer.add_bus_effect(master, AudioEffectLimiter.new())
	Game.apply_settings()


func play(name: String, vol := 1.0, pitch := 1.0) -> void:
	if not ready_done or not bank.has(name):
		return
	var now := Time.get_ticks_msec()
	if _last_play.get(name, -1000) > now - 25:
		return  # de-duplicate stacked triggers
	_last_play[name] = now
	var p: AudioStreamPlayer = players[next_voice]
	next_voice = (next_voice + 1) % VOICES
	p.stream = bank[name]
	p.volume_db = linear_to_db(maxf(vol, 0.001))
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.play()


func _w(buf: PackedFloat32Array, peak := 0.8) -> AudioStreamWAV:
	return S.to_wav_mono(S.normalize(buf, peak), SR)


func _build_bank() -> void:
	# movement
	bank.jump = _w(S.add(S.tone(SR, 0.12, 3, 260, 720, 0.05), S.svf(S.noise(SR, 0.05, 0.012, 0.5, 11), SR, 3000, 3000, 0.7, 2)), 0.5)
	bank.walljump = _w(S.add(S.tone(SR, 0.13, 2, 380, 900, 0.045, 0.002, 0.5), S.svf(S.noise(SR, 0.06, 0.015, 0.8, 12), SR, 2500, 2500, 1.0, 1)), 0.5)
	bank.land = _w(S.add(S.tone(SR, 0.16, 0, 140, 45, 0.05), S.svf(S.noise(SR, 0.12, 0.03, 0.6, 13), SR, 600, 200, 0.7, 0)), 0.7)
	bank.dash = _w(S.svf(S.noise(SR, 0.26, 0.09, 1.0, 14, 0.01), SR, 600, 4200, 2.5, 1), 0.7)
	bank.slide = _w(S.svf(S.noise(SR, 0.3, 0.12, 1.0, 15, 0.02), SR, 1800, 700, 1.2, 1), 0.4)
	bank.grapple = _w(S.add(S.tone(SR, 0.11, 2, 1600, 300, 0.05, 0.001, 0.4), S.metal(SR, 0.25, 900, [1.0, 2.76, 5.4, 8.9], 0.06, 1.0)), 0.6)
	bank.release = _w(S.svf(S.noise(SR, 0.06, 0.015, 1.0, 16), SR, 2000, 800, 1.0, 1), 0.3)
	bank.tick = _w(S.tone(SR, 0.03, 0, 2200, 2000, 0.008), 0.35)
	bank.boost = _w(S.add(S.tone(SR, 0.3, 1, 300, 1400, 0.12, 0.005, 0.6), S.svf(S.noise(SR, 0.3, 0.1, 0.7, 17, 0.02), SR, 1000, 6000, 1.5, 1)), 0.6)
	bank.pivot = _w(S.add(S.tone(SR, 0.18, 0, 220, 110, 0.06), S.tone(SR, 0.18, 3, 660, 660, 0.05, 0.002, 0.3)), 0.5)
	bank.booster = _w(S.tone(SR, 0.2, 4, 500, 1800, 0.08, 0.002, 0.6), 0.45)
	bank.pad = _w(_boing(), 0.6)
	bank.death = _w(S.add(S.drive(S.tone(SR, 0.5, 1, 600, 60, 0.2, 0.002, 1.0), 3.0), S.svf(S.noise(SR, 0.4, 0.12, 0.8, 18), SR, 3000, 300, 0.8, 0)), 0.7)
	bank.respawn = _w(S.add(S.tone(SR, 0.35, 0, 400, 1600, 0.12, 0.02, 0.6), S.tone(SR, 0.35, 0, 600, 2400, 0.1, 0.03, 0.4)), 0.45)
	# disc
	bank.throw = _w(S.svf(S.noise(SR, 0.32, 0.1, 1.0, 19, 0.015), SR, 5000, 900, 3.0, 1), 0.7)
	bank.charge = _w(S.tone(SR, 0.12, 3, 300, 500, 0.05, 0.01, 0.4), 0.2)
	bank.snap_perfect = _w(S.add(S.add(S.tone(SR, 0.6, 0, 1568, 1568, 0.2), S.tone(SR, 0.6, 0, 2093, 2093, 0.16), 0.8), S.add(S.tone(SR, 0.6, 0, 3136, 3136, 0.1), S.noise(SR, 0.02, 0.004, 1.0, 20), 0.4), 0.7), 0.6)
	bank.snap_good = _w(S.add(S.tone(SR, 0.35, 0, 1318, 1318, 0.12), S.noise(SR, 0.02, 0.004, 0.6, 21)), 0.45)
	bank.catch = _w(S.add(S.tone(SR, 0.12, 0, 220, 160, 0.04), S.svf(S.noise(SR, 0.08, 0.02, 1.0, 22), SR, 1800, 1200, 1.4, 1)), 0.6)
	bank.recall = _w(_reverse(S.svf(S.noise(SR, 0.35, 0.12, 1.0, 23, 0.01), SR, 900, 5000, 2.0, 1)), 0.5)
	bank.disc_hit = _w(S.add(S.tone(SR, 0.08, 0, 620, 540, 0.02), S.svf(S.noise(SR, 0.04, 0.008, 0.8, 24), SR, 3000, 3000, 1.0, 1)), 0.5)
	bank.disc_land = _w(S.add(S.tone(SR, 0.1, 0, 380, 300, 0.03), S.svf(S.noise(SR, 0.12, 0.04, 0.6, 25), SR, 1500, 500, 0.8, 0)), 0.45)
	bank.skip = _w(S.add(S.tone(SR, 0.07, 0, 900, 700, 0.02), S.svf(S.noise(SR, 0.15, 0.05, 0.7, 26), SR, 4000, 1500, 1.0, 1)), 0.5)
	bank.pole = _w(S.metal(SR, 0.7, 520, [1.0, 2.41, 3.87, 5.93, 8.2], 0.35), 0.6)
	bank.chains = _w(_chains(0.7, 22, 31), 0.7)
	bank.chains_big = _w(_chains(1.4, 60, 32), 0.9)
	bank.fanfare = _w(_fanfare(), 0.55)
	bank.glass = _w(S.add(S.svf(S.noise(SR, 0.5, 0.12, 1.0, 27), SR, 6000, 3000, 0.7, 2), _chains(0.5, 14, 33), 0.6), 0.7)
	bank.gate = _w(S.add(S.tone(SR, 0.45, 2, 220, 880, 0.2, 0.005, 0.5), S.add(S.tone(SR, 0.6, 0, 880, 880, 0.25, 0.1), S.tone(SR, 0.6, 0, 1320, 1320, 0.2, 0.12), 0.7), 0.7), 0.6)
	bank.go = _w(S.tone(SR, 0.4, 2, 880, 880, 0.15, 0.003, 0.6), 0.5)
	bank.beep = _w(S.tone(SR, 0.18, 2, 440, 440, 0.08, 0.003, 0.6), 0.45)
	# ui
	bank.ui_click = _w(S.add(S.tone(SR, 0.05, 2, 1200, 900, 0.015, 0.001, 0.4), S.noise(SR, 0.01, 0.003, 0.3, 28)), 0.35)
	bank.ui_hover = _w(S.tone(SR, 0.04, 0, 1800, 1800, 0.012), 0.2)


func _boing() -> PackedFloat32Array:
	var n := int(0.4 * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var f := 180.0 + 420.0 * (1.0 - exp(-t / 0.05)) + 40.0 * sin(t * 60.0) * exp(-t / 0.1)
		ph = fmod(ph + f / SR, 1.0)
		buf[i] = sin(ph * TAU) * exp(-t / 0.12)
	return buf


func _chains(dur: float, hits: int, seed_v: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for h in hits:
		var start := int(pow(rng.randf(), 1.8) * (dur * 0.7) * SR)
		var base := rng.randf_range(2200.0, 5200.0)
		var ping := S.metal(SR, 0.12, base, [1.0, 1.52, 2.33], 0.035, rng.randf_range(0.4, 1.0))
		S.mix_into(buf, ping, start)
	return buf


func _fanfare() -> PackedFloat32Array:
	var notes := [72, 76, 79, 84]
	var n := int(1.1 * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in notes.size():
		var f := S.midi_hz(notes[i])
		var dur := 1.1 - i * 0.09
		var v := S.add(S.tone(SR, dur, 1, f, f, 0.35, 0.005, 0.5), S.tone(SR, dur, 2, f * 1.003, f * 1.003, 0.3, 0.005, 0.3))
		v = S.svf(v, SR, 4000, 1500, 0.8, 0)
		S.mix_into(buf, v, int(i * 0.09 * SR))
	return buf


func _reverse(buf: PackedFloat32Array) -> PackedFloat32Array:
	var out := buf.duplicate()
	out.reverse()
	return out
