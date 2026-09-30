extends Node
## Generative per-theme music. Each theme gets a 16-bar loop (drums, bass,
## pad, arp, lead) rendered on a worker thread, cached to user:// and
## crossfaded in.

const S = preload("res://src/audio/synth.gd")
const Themes = preload("res://src/core/theme_db.gd")
const SR := 32000
const CACHE_VERSION := 3

const SCALES := {
	"major": [0, 2, 4, 5, 7, 9, 11],
	"minor": [0, 2, 3, 5, 7, 8, 10],
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"lydian": [0, 2, 4, 6, 7, 9, 11],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
}

const STYLES := {
	"indie": {"kick": "x.....x.x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x.", "bass": "x.x.x.x.x.x.x.x.", "bass_i": "saw",
		"arp_i": "pluck_sq", "arp_rate": 2, "lead_i": "lead_sq", "pad_i": "pad_soft", "hat_vol": 0.25},
	"darksynth": {"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "..x...x...x...x.", "hat16": true, "bass": "xxxxxxxxxxxxxxxx", "bass_i": "saw",
		"arp_i": "saw_arp", "arp_rate": 1, "lead_i": "lead_saw", "pad_i": "pad_saw", "hat_vol": 0.3},
	"harp": {"kick": "x.......x.......", "snare": "", "hat": "..x...x...x...x.", "bass": "x.......x.......", "bass_i": "sub",
		"arp_i": "ks", "arp_rate": 1, "lead_i": "flute", "pad_i": "pad_soft", "hat_vol": 0.12},
	"breakbeat": {"kick": "x.x.......x.....", "snare": "....x..x.x..x..x", "hat": "xxxxxxxxxxxxxxxx", "bass": "x..x..x...x.x...", "bass_i": "saw",
		"arp_i": "bell", "arp_rate": 1, "lead_i": "lead_sq", "pad_i": "pad_saw", "hat_vol": 0.18},
	"industrial": {"kick": "x...x...x...x.x.", "snare": "....x.......x...", "hat": "..x..x..x..x..x.", "metal": true, "bass": "x.xx.x.xx.x.x.xx", "bass_i": "sq_dist",
		"arp_i": "", "arp_rate": 2, "lead_i": "lead_saw", "pad_i": "pad_saw", "hat_vol": 0.2},
	"desert": {"kick": "x.......x..x....", "snare": "....x.......x...", "hat": "..x...x...x.x.x.", "bass": "x.....x...x.....", "bass_i": "saw",
		"arp_i": "ks", "arp_rate": 2, "lead_i": "flute", "pad_i": "pad_soft", "hat_vol": 0.15},
	"ambient": {"kick": "x.......x.......", "snare": "............x...", "hat": "..x...x...x...x.", "bass": "x...............", "bass_i": "sub",
		"arp_i": "bell", "arp_rate": 2, "lead_i": "flute", "pad_i": "pad_soft", "hat_vol": 0.1},
}

var cache := {}
var current := ""
var players: Array = []
var active := 0
var thread: Thread = null
var queue: Array = []
var fade := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80
		add_child(p)
		players.append(p)
	DirAccess.make_dir_recursive_absolute("user://music")


func play_theme(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if id == current:
		return
	current = id
	if cache.has(id):
		_start(cache[id])
		return
	var path := "user://music/%s_v%d.res" % [id, CACHE_VERSION]
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is AudioStreamWAV:
			cache[id] = res
			_start(res)
			return
	if not queue.has(id):
		queue.append(id)
	_kick_thread()


func _kick_thread() -> void:
	if thread != null or queue.is_empty():
		return
	var id: String = queue.pop_front()
	thread = Thread.new()
	thread.start(_render_job.bind(id))


func _render_job(id: String) -> void:
	var th: Dictionary = Themes.get_theme(id)
	var stream := render_song(th.get("music", {}), id.hash())
	call_deferred("_on_rendered", id, stream)


func _on_rendered(id: String, stream: AudioStreamWAV) -> void:
	if thread:
		thread.wait_to_finish()
		thread = null
	cache[id] = stream
	ResourceSaver.save(stream, "user://music/%s_v%d.res" % [id, CACHE_VERSION])
	if id == current:
		_start(stream)
	_kick_thread()


func _start(stream: AudioStreamWAV) -> void:
	var old: AudioStreamPlayer = players[active]
	active = 1 - active
	var p: AudioStreamPlayer = players[active]
	p.stream = stream
	p.volume_db = -40
	p.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "volume_db", -6.0, 1.5)
	tw.tween_property(old, "volume_db", -80.0, 1.0)
	tw.chain().tween_callback(old.stop)


func _exit_tree() -> void:
	if thread:
		thread.wait_to_finish()


# ====================================================================== renderer

var _note_cache := {}
var _rng := RandomNumberGenerator.new()


func render_song(m: Dictionary, seed_v: int) -> AudioStreamWAV:
	_note_cache.clear()
	_rng.seed = seed_v
	var bpm: float = m.get("bpm", 128)
	var root: int = m.get("root", 45)
	var scale: Array = SCALES.get(m.get("scale", "minor"), SCALES.minor)
	var style: Dictionary = STYLES.get(m.get("style", "darksynth"), STYLES.darksynth)
	var prog: Array = m.get("prog", [0, 5, 3, 6])
	var step := 60.0 / bpm / 4.0
	var bars := 16
	var total_steps := bars * 16
	var n := int(total_steps * step * SR)
	var L := PackedFloat32Array()
	var R := PackedFloat32Array()
	L.resize(n)
	R.resize(n)
	var sn := func(s: int) -> int: return int(s * step * SR)

	# --- drums
	var kick := _kick()
	var snare := _snare()
	var hat := _hat(0.035)
	var ohat := _hat(0.16)
	var metal := S.metal(SR, 0.25, 700, [1.0, 1.7, 2.9, 4.3], 0.08, 1.0)
	for s in total_steps:
		var bar := s / 16
		var i := s % 16
		var fill := bar % 8 == 7 and i >= 12
		if _hit(style.kick, i) and not (bar == 0 and false):
			_mix(L, R, kick, sn.call(s), 0.9, 0.0)
		if style.snare != "" and (_hit(style.snare, i) or (fill and i % 2 == 0)):
			_mix(L, R, snare, sn.call(s), 0.55 if not fill else 0.4, 0.05)
		if _hit(style.hat, i):
			_mix(L, R, ohat if i % 4 == 2 and not style.get("hat16", false) else hat, sn.call(s), style.hat_vol, 0.3)
		elif style.get("hat16", false):
			_mix(L, R, hat, sn.call(s), style.hat_vol * 0.45, -0.3)
		if style.get("metal", false) and i % 3 == 1:
			_mix(L, R, metal, sn.call(s), 0.18, _rng.randf_range(-0.6, 0.6))

	# --- harmony
	for bar in bars:
		var deg: int = prog[bar % prog.size()]
		var chord := _chord(root, scale, deg)
		var bar_start: int = sn.call(bar * 16)
		# pad (cached per chord)
		var pkey := "pad:%s:%d" % [style.pad_i, deg]
		if not _note_cache.has(pkey):
			_note_cache[pkey] = _pad(chord, 16 * step, style.pad_i)
		_mix(L, R, _note_cache[pkey], bar_start, 0.18, 0.0)
		# bass
		for i in 16:
			if _hit(style.bass, i):
				var bn: int = chord[0] - 12
				if style.bass == "x.x.x.x.x.x.x.x." and i % 4 == 2:
					bn += 12
				var blen := 2.0 * step if style.bass_i != "sub" else 7.0 * step
				_mix(L, R, _note(style.bass_i, bn, blen), bar_start + sn.call(i), 0.45, 0.0)
		# arp
		if style.arp_i != "":
			var rate: int = style.arp_rate
			var pattern := [0, 1, 2, 1, 2, 3, 2, 1] if rate == 1 else [0, 1, 2, 3]
			var k := 0
			for i in range(0, 16, rate):
				var idx: int = pattern[k % pattern.size()]
				k += 1
				var note: int = chord[idx % 3] + 12 * (1 + idx / 3)
				var buf := _note(style.arp_i, note, step * rate * 1.2)
				var off: int = bar_start + sn.call(i)
				_mix(L, R, buf, off, 0.16, -0.4)
				_mix(L, R, buf, off + sn.call(3), 0.07, 0.6)  # ping-pong echo

	# --- lead melody (second half, phrase repeated with variation)
	var phrase := _phrase(scale, root)
	for half in 2:
		for rep in 2:
			var base_bar := 8 + half * 4 + rep * 2
			for nt in phrase:
				var st: int = base_bar * 16 + nt[0]
				var pitch: int = nt[1]
				if rep == 1 and nt[0] >= 24 and half == 1:
					pitch += scale[(nt[0] / 2) % scale.size()] % 3
				_mix(L, R, _note(style.lead_i, pitch, nt[2] * step), sn.call(st), 0.2, 0.15)

	# --- master: soft clip + normalize
	var peak := 0.0001
	for i in n:
		L[i] = tanh(L[i] * 1.1)
		R[i] = tanh(R[i] * 1.1)
		peak = maxf(peak, maxf(absf(L[i]), absf(R[i])))
	var g := 0.85 / peak
	for i in n:
		L[i] *= g
		R[i] *= g
	return S.to_wav_stereo(L, R, SR, true)


func _hit(pattern: String, i: int) -> bool:
	return pattern.length() > i and pattern[i] == "x"


func _mix(L: PackedFloat32Array, R: PackedFloat32Array, buf: PackedFloat32Array, off: int, vol: float, pan: float) -> void:
	var gl := vol * (1.0 - maxf(0.0, pan))
	var gr := vol * (1.0 - maxf(0.0, -pan))
	var n := L.size()
	var m := buf.size()
	for i in m:
		var j := (off + i) % n   # wrap tails around for a seamless loop
		var v := buf[i]
		L[j] += v * gl
		R[j] += v * gr


func _chord(root: int, scale: Array, deg: int) -> Array:
	var out := []
	for k in [0, 2, 4]:
		var d: int = deg + k
		out.append(root + 12 + scale[d % 7] + 12 * (d / 7))
	return out


func _phrase(scale: Array, root: int) -> Array:
	# 2-bar phrase: [step, midi, length_steps]
	var out := []
	var s := 0
	var deg := _rng.randi_range(0, 4)
	while s < 32:
		var len: int = [2, 2, 2, 4, 1, 3][_rng.randi_range(0, 5)]
		if _rng.randf() < 0.2:
			s += len
			continue
		deg = clampi(deg + _rng.randi_range(-2, 2), -2, 9)
		var d := posmod(deg, 7)
		var octave := 24 + 12 * int(floor(deg / 7.0))
		out.append([s, root + octave + scale[d], len])
		s += len
	return out


func _note(inst: String, midi: int, dur: float) -> PackedFloat32Array:
	var key := "%s:%d:%d" % [inst, midi, int(dur * 1000)]
	if _note_cache.has(key):
		return _note_cache[key]
	var f := S.midi_hz(midi)
	var buf: PackedFloat32Array
	match inst:
		"pluck_sq":
			buf = S.svf(S.tone(SR, dur + 0.05, 2, f, f, 0.09, 0.002), SR, 3500, 900, 0.9, 0)
		"saw_arp":
			buf = S.svf(S.tone(SR, dur + 0.05, 1, f, f, 0.12, 0.002), SR, 4000, 1200, 1.4, 0)
		"ks":
			buf = S.pluck(SR, f, dur + 0.4, 0.995, 1.0, midi)
		"bell":
			buf = S.add(S.tone(SR, dur + 0.3, 0, f, f, 0.25, 0.002), S.tone(SR, dur + 0.3, 0, f * 2.76, f * 2.76, 0.08, 0.002), 0.35)
		"saw":
			buf = S.add(S.svf(S.tone(SR, dur, 1, f, f, dur * 0.8, 0.004), SR, 1400, 400, 1.2, 0), S.tone(SR, dur, 0, f, f, dur, 0.004), 0.6)
		"sq_dist":
			buf = S.drive(S.svf(S.tone(SR, dur, 2, f, f, dur * 0.7, 0.003), SR, 1800, 500, 1.0, 0), 2.5)
		"sub":
			buf = S.tone(SR, dur, 0, f, f, dur * 0.9, 0.01)
		"lead_sq", "lead_saw", "flute":
			buf = _lead(inst, f, dur)
		_:
			buf = S.tone(SR, dur, 0, f, f, dur * 0.5)
	_note_cache[key] = buf
	return buf


func _lead(inst: String, f: float, dur: float) -> PackedFloat32Array:
	var n := int((dur + 0.08) * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var kind := 2 if inst == "lead_sq" else (1 if inst == "lead_saw" else 0)
	for i in n:
		var t := float(i) / SR
		var vib := 1.0 + 0.006 * sin(t * 34.0) * minf(1.0, t / 0.2)
		ph = fmod(ph + f * vib / SR, 1.0)
		var env := minf(1.0, t / 0.01) * (1.0 if t < dur else exp(-(t - dur) / 0.03)) * (0.8 + 0.2 * exp(-t / 0.1))
		var v := S.osc(kind, ph)
		if kind == 0:
			v += 0.3 * S.osc(0, fmod(ph * 2.0, 1.0))
		buf[i] = v * env
	if kind != 0:
		buf = S.svf(buf, SR, 3000, 2000, 0.9, 0)
	return buf


func _pad(chord: Array, dur: float, kind: String) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var detunes := [-0.006, 0.0, 0.007]
	for note in chord:
		var f := S.midi_hz(note)
		for dt in detunes:
			var ph := _rng.randf()
			var ff: float = f * (1.0 + dt)
			for i in n:
				var t := float(i) / SR
				ph = fmod(ph + ff / SR, 1.0)
				var env := minf(1.0, t / 0.35) * minf(1.0, (dur - t) / 0.2)
				var v: float = S.osc(1, ph) if kind == "pad_saw" else S.osc(3, ph)
				buf[i] += v * env * 0.15
	return S.svf(buf, SR, 1400, 1000, 0.7, 0)


func _kick() -> PackedFloat32Array:
	return S.add(S.tone(SR, 0.35, 0, 160, 42, 0.14, 0.001, 1.0), S.svf(S.noise(SR, 0.02, 0.004, 0.6, 5), SR, 3000, 3000, 0.7, 2))


func _snare() -> PackedFloat32Array:
	return S.add(S.svf(S.noise(SR, 0.22, 0.07, 0.9, 6), SR, 1800, 1800, 0.6, 2), S.tone(SR, 0.12, 3, 210, 180, 0.04, 0.001, 0.6))


func _hat(decay: float) -> PackedFloat32Array:
	return S.svf(S.noise(SR, decay * 3.0, decay, 0.8, 7), SR, 8000, 8000, 0.8, 2)
