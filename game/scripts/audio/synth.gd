extends RefCounted
## Chip-style software synth used by the Audio autoload. Every sound in the game is
## generated here from code at runtime (there are no audio files).
##
## An instance only owns read-only noise tables, and every render call works on its own
## buffers, so a WorkerThreadPool task can create its own instance and render freely.
##
## Oscillators run per sample; pitch, duty, envelope, vibrato, arpeggio and tremolo are
## updated per block of BLOCK samples (the envelope is interpolated linearly inside a
## block), which keeps the inner loops short enough for GDScript.

const RATE := 22050
const BLOCK := 32
const NOISE_LEN := 16384  # power of two
const NOISE_MASK := NOISE_LEN - 1
const METAL_LEN := 93  # short-period loop: the "metallic" noise of old sound chips

enum { W_PULSE, W_TRI, W_SAW, W_SINE, W_NOISE, W_METAL }

const WAVES := {
	"p12": [W_PULSE, 0.125], "p25": [W_PULSE, 0.25], "p50": [W_PULSE, 0.5],
	"pwm": [W_PULSE, 0.3], "tri": [W_TRI, 0.5], "saw": [W_SAW, 0.5],
	"sine": [W_SINE, 0.5], "noise": [W_NOISE, 0.5], "metal": [W_METAL, 0.5],
}

var noise := PackedFloat32Array()
var metal := PackedFloat32Array()


func _init(seed_value := 90210) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	noise.resize(NOISE_LEN)
	for i in NOISE_LEN:
		noise[i] = rng.randf_range(-1.0, 1.0)
	metal.resize(METAL_LEN)
	for i in METAL_LEN:
		metal[i] = 1.0 if rng.randf() < 0.5 else -1.0


static func midi_hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## Renders one voice into a new mono buffer (length = gate + release). Keys, all optional:
##   w    wave: p12 p25 p50 (pulse), pwm (pulse with duty LFO), tri, saw, sine, noise, metal
##   f    start Hz (noise: clock Hz)   f2 end Hz   st sweep time s (default len)   lin linear sweep
##   d    pulse duty (overrides the wave's)   d2 end duty (swept over len)   pwm_lfo [rate, depth]
##   len  gate s   a attack s   h hold s   dc decay s (default: to the end of the gate)
##   sus  sustain level   r release s after the gate   c envelope curve exponent   v volume
##   vib  [rate Hz, depth semitones, delay s]   arp [semitones...]   at arp step s
##   al   loop the arp (default true; false = stop on the last step)
##   trem [rate Hz, depth 0-1]   lp [start Hz, end Hz] one-pole low-pass   hp high-pass Hz
##   crush quantise to this many levels
func voice(p: Dictionary) -> PackedFloat32Array:
	var gate: float = p.get("len", 0.1)
	var rel: float = p.get("r", 0.004)
	var n := int((gate + rel) * RATE)
	var out := PackedFloat32Array()
	if n <= 0:
		return out
	out.resize(n)
	var wdef: Array = WAVES.get(p.get("w", "p50"), WAVES.p50)
	var kind: int = wdef[0]
	var duty: float = p.get("d", wdef[1])
	var duty2: float = p.get("d2", duty)
	var pwm: Array = p.get("pwm_lfo", [0.7, 0.18] if p.get("w", "") == "pwm" else [])
	var f0: float = p.get("f", 440.0)
	var f1: float = p.get("f2", f0)
	var st: float = maxf(p.get("st", gate), 0.001)
	var lin: bool = p.get("lin", false)
	var vol: float = p.get("v", 0.5)
	var atk: float = maxf(p.get("a", 0.002), 0.0005)
	var hold: float = p.get("h", 0.0)
	var sus: float = p.get("sus", 0.0)
	var dec: float = maxf(p.get("dc", gate - atk - hold), 0.001)
	var curve: float = p.get("c", 1.0)
	var vib: Array = p.get("vib", [])
	var arp: Array = p.get("arp", [])
	var arp_t: float = maxf(p.get("at", 0.05), 0.001)
	var arp_loop: bool = p.get("al", true)
	var trem: Array = p.get("trem", [])
	var ratios := PackedFloat32Array()
	for semis in arp:
		ratios.append(pow(2.0, float(semis) / 12.0))
	var e_gate := _env(gate - 0.00001, atk, hold, dec, sus, gate, rel, 0.0, curve)
	var ph := 0.0
	var nidx := 0
	var nval := 0.0
	var i := 0
	var fmax := RATE * 0.45
	while i < n:
		var b1 := mini(i + BLOCK, n)
		var t := float(i) / RATE
		var t1 := float(b1) / RATE
		# pitch
		var f := f0
		if f1 != f0:
			var k := minf(t / st, 1.0)
			f = lerpf(f0, f1, k) if lin else f0 * pow(f1 / f0, k)
		if not ratios.is_empty():
			var step := int(t / arp_t)
			step = step % ratios.size() if arp_loop else mini(step, ratios.size() - 1)
			f *= ratios[step]
		if not vib.is_empty() and t > vib[2]:
			var ramp := minf((t - vib[2]) / 0.15, 1.0)
			f *= pow(2.0, vib[1] * ramp / 12.0 * sin(TAU * vib[0] * (t - vib[2])))
		f = clampf(f, 1.0, fmax if kind != W_NOISE and kind != W_METAL else RATE * 4.0)
		var inc := f / RATE
		# envelope (linear inside the block)
		var ea := _env(t, atk, hold, dec, sus, gate, rel, e_gate, curve)
		var eb := _env(t1, atk, hold, dec, sus, gate, rel, e_gate, curve)
		if not trem.is_empty():
			ea *= 1.0 - trem[1] * (0.5 + 0.5 * sin(TAU * trem[0] * t))
			eb *= 1.0 - trem[1] * (0.5 + 0.5 * sin(TAU * trem[0] * t1))
		var e := ea * vol
		var de := (eb - ea) * vol / float(b1 - i)
		match kind:
			W_PULSE:
				var du := duty
				if duty2 != duty:
					du = lerpf(duty, duty2, minf(t / gate, 1.0))
				if not pwm.is_empty():
					du += pwm[1] * sin(TAU * pwm[0] * t)
				du = clampf(du, 0.04, 0.96)
				var dc := 2.0 * du - 1.0
				var norm := 1.0 / (1.0 + absf(dc))
				e *= norm
				de *= norm
				for j in range(i, b1):
					ph += inc
					if ph >= 1.0:
						ph -= 1.0
					var v := 1.0 if ph < du else -1.0
					if ph < inc:
						var x := ph / inc
						v += x + x - x * x - 1.0
					elif ph > 1.0 - inc:
						var x := (ph - 1.0) / inc
						v += x * x + x + x + 1.0
					var q := ph - du
					if q < 0.0:
						q += 1.0
					if q < inc:
						var x := q / inc
						v -= x + x - x * x - 1.0
					elif q > 1.0 - inc:
						var x := (q - 1.0) / inc
						v -= x * x + x + x + 1.0
					out[j] = (v - dc) * e
					e += de
			W_TRI:
				# 16-step triangle, like the stepped triangle channel of 8-bit consoles.
				for j in range(i, b1):
					ph += inc
					if ph >= 1.0:
						ph -= 1.0
					var v := 4.0 * ph - 1.0 if ph < 0.5 else 3.0 - 4.0 * ph
					out[j] = (floorf(v * 7.99) + 0.5) * 0.125 * e
					e += de
			W_SAW:
				for j in range(i, b1):
					ph += inc
					if ph >= 1.0:
						ph -= 1.0
					var v := 2.0 * ph - 1.0
					if ph < inc:
						var x := ph / inc
						v -= x + x - x * x - 1.0
					elif ph > 1.0 - inc:
						var x := (ph - 1.0) / inc
						v -= x * x + x + x + 1.0
					out[j] = v * e
					e += de
			W_SINE:
				for j in range(i, b1):
					ph += inc
					if ph >= 1.0:
						ph -= 1.0
					out[j] = sin(TAU * ph) * e
					e += de
			W_NOISE:
				for j in range(i, b1):
					ph += inc
					if ph >= 1.0:
						var steps := int(ph)
						ph -= steps
						nidx = (nidx + steps) & NOISE_MASK
						nval = noise[nidx]
					out[j] = nval * e
					e += de
			W_METAL:
				for j in range(i, b1):
					ph += inc
					if ph >= 1.0:
						var steps := int(ph)
						ph -= steps
						nidx = (nidx + steps) % METAL_LEN
						nval = metal[nidx]
					out[j] = nval * e
					e += de
		i = b1
	if p.has("lp"):
		_lowpass(out, p.lp[0], p.lp[1])
	if p.has("hp"):
		_highpass(out, p.hp)
	if p.has("crush"):
		var lv: float = p.crush
		for j in n:
			out[j] = roundf(out[j] * lv) / lv
	return out


static func _env(t: float, atk: float, hold: float, dec: float, sus: float, gate: float,
		rel: float, e_gate: float, curve: float) -> float:
	if t >= gate:
		return e_gate * maxf(0.0, 1.0 - (t - gate) / rel) if rel > 0.0 else 0.0
	var e: float
	if t < atk:
		e = t / atk
	elif t < atk + hold:
		e = 1.0
	else:
		e = sus + (1.0 - sus) * maxf(0.0, 1.0 - (t - atk - hold) / dec)
	return pow(e, curve) if curve != 1.0 else e


## One-pole low-pass whose cutoff glides exponentially from f_start to f_end.
static func _lowpass(buf: PackedFloat32Array, f_start: float, f_end: float) -> void:
	var n := buf.size()
	var y := 0.0
	var i := 0
	while i < n:
		var b1 := mini(i + BLOCK, n)
		var fc := f_start * pow(f_end / f_start, float(i) / n)
		var a := 1.0 - exp(-TAU * fc / RATE)
		for j in range(i, b1):
			y += (buf[j] - y) * a
			buf[j] = y
		i = b1


static func _highpass(buf: PackedFloat32Array, fc: float) -> void:
	var a := 1.0 - exp(-TAU * fc / RATE)
	var low := 0.0
	for j in buf.size():
		low += (buf[j] - low) * a
		buf[j] -= low


## Adds src (times gl / gr) into dst_l / dst_r from frame `at`, stopping at `limit`
## (exclusive). A cut-off tail gets a short fade so the cut never clicks.
static func mix(dst_l: PackedFloat32Array, dst_r: PackedFloat32Array, src: PackedFloat32Array,
		at: int, gl: float, gr: float, limit: int) -> void:
	var n := mini(src.size(), limit - at)
	if n <= 0:
		return
	var fade_from := n
	if n < src.size():
		fade_from = maxi(0, n - 96)
	for j in fade_from:
		var v := src[j]
		dst_l[at + j] += v * gl
		dst_r[at + j] += v * gr
	for j in range(fade_from, n):
		var v := src[j] * float(n - j) / float(n - fade_from)
		dst_l[at + j] += v * gl
		dst_r[at + j] += v * gr


# --- sound effects --------------------------------------------------------------------

## Renders an effect made of layers (see voice(); `t` = layer start s) to a mono buffer,
## peak-limited to 0.9 and with a short fade at the very end.
func render_sfx(layers: Array) -> PackedFloat32Array:
	var total := 0
	for l: Dictionary in layers:
		var end := int((l.get("t", 0.0) + l.get("len", 0.1) + l.get("r", 0.004)) * RATE) + 1
		total = maxi(total, end)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for l: Dictionary in layers:
		var v := voice(l)
		var at := int(l.get("t", 0.0) * RATE)
		for j in mini(v.size(), total - at):
			buf[at + j] += v[j]
	var peak := 0.0
	for j in total:
		peak = maxf(peak, absf(buf[j]))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	var tail := mini(64, total)
	for j in total:
		buf[j] *= gain
	for j in tail:
		buf[total - 1 - j] *= float(j) / tail
	return buf


static func to_pcm16(buf: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	return bytes


static func make_wav(pcm: PackedByteArray, stereo := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = stereo
	w.data = pcm
	return w


# --- drums -----------------------------------------------------------------------------

## The drum kit, rendered once per music job. Values are mono buffers at full scale.
func drum_kit() -> Dictionary:
	var kit := {}
	kit.kick = render_sfx([
		{"w": "sine", "f": 160.0, "f2": 44.0, "st": 0.09, "len": 0.17, "a": 0.0008, "c": 1.4, "v": 1.0},
		{"w": "tri", "f": 120.0, "f2": 50.0, "st": 0.05, "len": 0.06, "a": 0.0008, "c": 1.5, "v": 0.35},
		{"w": "noise", "f": 22050.0, "len": 0.008, "a": 0.0005, "v": 0.35, "lp": [6000.0, 2000.0]},
	])
	kit.snare = render_sfx([
		{"w": "noise", "f": 22050.0, "len": 0.15, "a": 0.0008, "c": 1.8, "v": 0.75, "lp": [9000.0, 3500.0]},
		{"w": "tri", "f": 240.0, "f2": 150.0, "len": 0.07, "a": 0.0008, "c": 1.4, "v": 0.6},
	])
	kit.hat = render_sfx([
		{"w": "noise", "f": 22050.0, "len": 0.035, "a": 0.0005, "c": 2.0, "v": 0.8, "hp": 6500.0},
	])
	kit.ohat = render_sfx([
		{"w": "noise", "f": 22050.0, "len": 0.16, "a": 0.0005, "c": 1.6, "v": 0.7, "hp": 5000.0},
	])
	kit.crash = render_sfx([
		{"w": "noise", "f": 22050.0, "len": 0.9, "a": 0.001, "c": 2.0, "v": 0.7, "hp": 3000.0},
		{"w": "metal", "f": 11000.0, "len": 0.45, "a": 0.001, "c": 2.0, "v": 0.18, "hp": 2000.0},
	])
	kit.tom_lo = render_sfx([
		{"w": "tri", "f": 170.0, "f2": 85.0, "len": 0.17, "a": 0.0008, "c": 1.3, "v": 0.9},
		{"w": "noise", "f": 22050.0, "len": 0.02, "a": 0.0005, "v": 0.25, "lp": [5000.0, 2000.0]},
	])
	kit.tom_hi = render_sfx([
		{"w": "tri", "f": 260.0, "f2": 140.0, "len": 0.14, "a": 0.0008, "c": 1.3, "v": 0.9},
		{"w": "noise", "f": 22050.0, "len": 0.02, "a": 0.0005, "v": 0.25, "lp": [6000.0, 2500.0]},
	])
	return kit
