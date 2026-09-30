extends RefCounted
## Tiny offline synthesiser: oscillators, envelopes, filters and helpers that
## render into PackedFloat32Array buffers. Used for SFX and generated music.

const TAU_F := TAU


static func midi_hz(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


static func osc(kind: int, ph: float) -> float:
	# ph in cycles [0,1)
	match kind:
		0: return sin(ph * TAU_F)                      # sine
		1: return 2.0 * ph - 1.0                       # saw
		2: return 1.0 if ph < 0.5 else -1.0            # square
		3: return 4.0 * absf(ph - 0.5) - 1.0           # triangle
		4: return 1.0 if ph < 0.25 else -1.0           # pulse 25%
	return 0.0


## Render a tone with pitch sweep f0->f1 (exponential), exp decay and optional attack.
static func tone(sr: int, dur: float, kind: int, f0: float, f1: float, decay: float, attack := 0.002, vol := 1.0) -> PackedFloat32Array:
	var n := int(dur * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var ratio := f1 / f0
	for i in n:
		var t := float(i) / sr
		var f := f0 * pow(ratio, t / dur)
		ph = fmod(ph + f / sr, 1.0)
		var env := exp(-t / decay) * minf(1.0, t / attack)
		buf[i] = osc(kind, ph) * env * vol
	return buf


static func noise(sr: int, dur: float, decay: float, vol := 1.0, seed := 1, attack := 0.001) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := int(dur * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / sr
		buf[i] = rng.randf_range(-1.0, 1.0) * exp(-t / decay) * minf(1.0, t / attack) * vol
	return buf


## State-variable filter with linear cutoff sweep. mode: 0 lp, 1 bp, 2 hp
static func svf(buf: PackedFloat32Array, sr: int, fc0: float, fc1: float, q := 0.7, mode := 0) -> PackedFloat32Array:
	var low := 0.0
	var band := 0.0
	var n := buf.size()
	var damp := 1.0 / maxf(q, 0.1)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var fc := lerpf(fc0, fc1, float(i) / maxf(1.0, n - 1))
		var f := 2.0 * sin(PI * minf(fc, sr * 0.22) / sr)
		low += f * band
		var high := buf[i] - low - damp * band
		band += f * high
		match mode:
			0: out[i] = low
			1: out[i] = band
			_: out[i] = high
	return out


## Karplus-Strong plucked string
static func pluck(sr: int, freq: float, dur: float, damping := 0.996, vol := 1.0, seed := 3) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var period := maxi(2, int(sr / freq))
	var line := PackedFloat32Array()
	line.resize(period)
	for i in period:
		line[i] = rng.randf_range(-1.0, 1.0)
	var n := int(dur * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var idx := 0
	var prev := 0.0
	for i in n:
		var cur := line[idx]
		var nxt := 0.5 * (cur + prev) * damping
		prev = cur
		line[idx] = nxt
		buf[i] = cur * vol
		idx = (idx + 1) % period
	return buf


## Metallic hit: sum of inharmonic partials with individual decays.
static func metal(sr: int, dur: float, base: float, partials: Array, decay: float, vol := 1.0) -> PackedFloat32Array:
	var n := int(dur * sr)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for p in partials:
		var f: float = base * p
		var d: float = decay / sqrt(p)
		for i in n:
			var t := float(i) / sr
			buf[i] += sin(t * f * TAU_F) * exp(-t / d) * vol / partials.size()
	return buf


static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int, gain := 1.0) -> void:
	var n := mini(src.size(), dst.size() - offset)
	if offset < 0:
		return
	for i in n:
		dst[offset + i] += src[i] * gain


static func add(a: PackedFloat32Array, b: PackedFloat32Array, gb := 1.0) -> PackedFloat32Array:
	var out := a.duplicate()
	if b.size() > out.size():
		out.resize(b.size())
	for i in b.size():
		out[i] += b[i] * gb
	return out


static func gain(buf: PackedFloat32Array, g: float) -> PackedFloat32Array:
	var out := buf.duplicate()
	for i in out.size():
		out[i] *= g
	return out


static func drive(buf: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var out := buf.duplicate()
	var norm := 1.0 / tanh(amount)
	for i in out.size():
		out[i] = tanh(out[i] * amount) * norm
	return out


static func normalize(buf: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in buf:
		m = maxf(m, absf(v))
	return gain(buf, peak / m)


static func to_wav_mono(buf: PackedFloat32Array, sr: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = bytes
	return w


static func to_wav_stereo(l: PackedFloat32Array, r: PackedFloat32Array, sr: int, loop := true) -> AudioStreamWAV:
	var n := mini(l.size(), r.size())
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i in n:
		bytes.encode_s16(i * 4, int(clampf(l[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(r[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = true
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w
