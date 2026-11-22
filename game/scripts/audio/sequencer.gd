extends RefCounted
## Turns a composition from music_data.gd into a flat, time-sorted list of events.
##
## A track is a list of sections (form). Each section has a chord chart and up to six
## parts: two melodic MML parts (lead, lead2) and four pattern parts generated from the
## chords (bass, arp, drums, hats; plus `fill` for the section's last drum bar).
##
## MML (one string per section, bar lines `|` are checked):
##   c d e f g a b   note, then + / # (sharp) or - (flat), length (1 2 4 8 16 32, 3 6 12 24
##                   for triplets) and dots: `c+8.`   r rest   ^len tie onto the last note
##   o4  octave (o4 c = middle C)   > <  octave up / down   l8 default length
##   q1..q8  gate in eighths of the length (default q7)   v0..v15 velocity
##   [ ... ]n repeat n times (nestable)
## Patterns: one character per 16th step, repeating; `-` holds the previous note, `.` rests.
##   bass: R root  O octave  F fifth  L fifth below  T third  S top chord tone
##   arp:  0-9 chord-tone index (0 root, 1 third, 2 fifth, ... continuing up an octave)
##         C the whole chord as a fast chip arpeggio
##   drums / hats / fill: k kick  s snare  x kick+snare  t low tom  T high tom
##         h hat  o open hat  c crash+kick  C crash

const Synth = preload("res://scripts/audio/synth.gd")

const TPQ := 48  # ticks per quarter note
const BAR := 192
const STEP := 12  # one 16th note
const NOTE_PC := {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
const ROOT_PC := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
const QUALITIES := {
	"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10],
	"maj7": [0, 4, 7, 11], "sus4": [0, 5, 7], "sus2": [0, 2, 7], "dim": [0, 3, 6],
	"dim7": [0, 3, 6, 9], "aug": [0, 4, 8], "5": [0, 7, 12], "6": [0, 4, 7, 9],
	"m6": [0, 3, 7, 9], "add9": [0, 4, 7, 14], "m9": [0, 3, 7, 10, 14],
	"7sus4": [0, 5, 7, 10], "m7b5": [0, 3, 6, 10],
}
const DRUM_HITS := {
	"k": ["kick"], "s": ["snare"], "x": ["kick", "snare"], "t": ["tom_lo"], "T": ["tom_hi"],
	"h": ["hat"], "o": ["ohat"], "c": ["crash", "kick"], "C": ["crash"],
}

## Default instruments; a track's "inst" entries are merged over these.
const DEFAULT_INST := {
	"lead": {"w": "p25", "v": 0.2, "a": 0.004, "dc": 0.22, "sus": 0.62, "r": 0.06,
			"vib": [5.5, 0.2, 0.22], "pan": -0.08},
	"lead2": {"w": "p12", "v": 0.12, "a": 0.004, "dc": 0.15, "sus": 0.5, "r": 0.05,
			"vib": [5.0, 0.15, 0.25], "pan": 0.35},
	"arp": {"w": "p12", "v": 0.075, "a": 0.002, "dc": 0.09, "sus": 0.35, "r": 0.03,
			"pan": -0.45, "center": 67, "gate": 0.9, "chord_t": 0.022},
	"bass": {"w": "tri", "v": 0.42, "a": 0.002, "dc": 0.12, "sus": 0.85, "r": 0.02,
			"pan": 0.0, "center": 40, "gate": 0.82},
	"drums": {"kick": 0.5, "snare": 0.3, "hat": 0.11, "ohat": 0.1, "crash": 0.17,
			"tom_lo": 0.34, "tom_hi": 0.3, "pan": 0.22},
}


## Expands [..]n repeats (nestable; n defaults to 2).
static func expand_repeats(src: String) -> String:
	var out := ""
	var i := 0
	while i < src.length():
		var ch := src[i]
		if ch != "[":
			out += ch
			i += 1
			continue
		var depth := 1
		var j := i + 1
		while j < src.length() and depth > 0:
			if src[j] == "[":
				depth += 1
			elif src[j] == "]":
				depth -= 1
			j += 1
		var inner := expand_repeats(src.substr(i + 1, j - i - 2))
		var digits := ""
		while j < src.length() and src[j].is_valid_int():
			digits += src[j]
			j += 1
		out += inner.repeat(int(digits) if digits != "" else 2)
		i = j
	return out


## Parses one MML part. Returns {notes: [[tick, ticks, midi, velocity, gate]...],
## ticks: total length, errors: [String]}.
static func parse_mml(src: String) -> Dictionary:
	var s := expand_repeats(src)
	var notes: Array = []
	var errors: Array = []
	var oct := 4
	var deflen := 24
	var gate := 7.0 / 8.0
	var vel := 1.0
	var tick := 0
	var bar := 1
	var last := -1
	var i := 0
	var n := s.length()
	while i < n:
		var ch := s[i]
		i += 1
		if ch == " " or ch == "\n" or ch == "\t":
			continue
		if ch == "|":
			if tick % BAR != 0:
				errors.append("bar line %d is at tick %d (%.2f bars)" % [bar, tick, tick / float(BAR)])
			bar += 1
			continue
		if ch == "o" or ch == "q" or ch == "v":
			var r := _read_int(s, i)
			i = r[1]
			if ch == "o":
				oct = r[0]
			elif ch == "q":
				gate = clampf(r[0] / 8.0, 0.1, 1.0)
			else:
				vel = clampf(r[0] / 15.0, 0.0, 1.0)
			continue
		if ch == ">":
			oct += 1
			continue
		if ch == "<":
			oct -= 1
			continue
		if ch == "l":
			var r := _read_len(s, i, deflen, errors)
			deflen = r[0]
			i = r[1]
			continue
		if ch == "r" or ch == "^":
			var r := _read_len(s, i, deflen, errors)
			i = r[1]
			if ch == "^" and last >= 0:
				notes[last][1] += r[0]
			else:
				last = -1
			tick += r[0]
			continue
		if NOTE_PC.has(ch):
			var pc: int = NOTE_PC[ch]
			while i < n and (s[i] == "+" or s[i] == "#" or s[i] == "-"):
				pc += -1 if s[i] == "-" else 1
				i += 1
			var r := _read_len(s, i, deflen, errors)
			i = r[1]
			notes.append([tick, r[0], 12 * (oct + 1) + pc, vel, gate])
			last = notes.size() - 1
			tick += r[0]
			continue
		errors.append("unexpected '%s' at %d" % [ch, i - 1])
	return {"notes": notes, "ticks": tick, "errors": errors}


static func _read_int(s: String, i: int) -> Array:
	var digits := ""
	while i < s.length() and s[i].is_valid_int():
		digits += s[i]
		i += 1
	return [int(digits) if digits != "" else 0, i]


## Note length in ticks: digits (whole-note divisor) then dots; none = the default.
static func _read_len(s: String, i: int, deflen: int, errors: Array) -> Array:
	var r := _read_int(s, i)
	var t := deflen
	if r[1] > i:
		if r[0] <= 0 or BAR % r[0] != 0:
			errors.append("bad length %d" % r[0])
		else:
			t = BAR / r[0]
	i = r[1]
	var add := t
	while i < s.length() and s[i] == ".":
		add /= 2
		t += add
		i += 1
	return [t, i]


## "F#m7/C#" -> {root: 6, tones: [0, 3, 7, 10], bass: 1}
static func parse_chord(sym: String) -> Dictionary:
	var root: int = ROOT_PC.get(sym[0], 0)
	var i := 1
	if i < sym.length() and (sym[i] == "#" or sym[i] == "b"):
		root += 1 if sym[i] == "#" else -1
		i += 1
	var rest := sym.substr(i)
	var bass := root
	var slash := rest.find("/")
	if slash >= 0:
		var b := parse_chord(rest.substr(slash + 1))
		bass = b.root
		rest = rest.substr(0, slash)
	return {"root": posmod(root, 12), "tones": QUALITIES.get(rest, QUALITIES[""]),
			"bass": posmod(bass, 12), "ok": QUALITIES.has(rest)}


## "Am F | C" -> [[start_tick, chord], ...] and the bar count.
static func parse_chart(chart: String) -> Array:
	var out: Array = []
	var bars := chart.split("|")
	for b in bars.size():
		var syms: Array = []
		for w in bars[b].split(" ", false):
			if w.strip_edges() != "":
				syms.append(w.strip_edges())
		for k in syms.size():
			out.append([b * BAR + k * BAR / syms.size(), parse_chord(syms[k])])
	return [out, bars.size()]


static func _chord_at(chart: Array, tick: int) -> Dictionary:
	var c: Dictionary = chart[0][1]
	for e in chart:
		if e[0] > tick:
			break
		c = e[1]
	return c


## Places pitch class pc in the octave around `center` (center - 6 .. center + 5).
static func _near(pc: int, center: int) -> int:
	var lo := center - 6
	return lo + posmod(pc - lo, 12)


static func _clean(pat: String) -> String:
	return pat.replace(" ", "").replace("|", "").replace("\n", "").replace("\t", "")


## Splits a pattern over `steps` 16th steps into [step, length_in_steps, symbol].
static func _pattern_hits(pat: String, steps: int) -> Array:
	var p := _clean(pat)
	var out: Array = []
	if p.is_empty():
		return out
	var n := p.length()
	for k in steps:
		var c := p[k % n]
		if c == "." or c == "-":
			continue
		var d := 1
		while k + d < steps and p[(k + d) % n] == "-":
			d += 1
		out.append([k, d, c])
	return out


static func _merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var d := base.duplicate()
	d.merge(over, true)
	return d


## Builds the render plan of a track:
## {events: [[frame, kind, data, gl, gr, limit]...] sorted by frame, frames, loop_frame,
##  looping, errors, bars}. kind 0 = synth voice (data = voice params), 1 = drum (data = name).
static func plan(track: Dictionary) -> Dictionary:
	var bpm: float = track.bpm
	var spt := Synth.RATE * 60.0 / (bpm * TPQ)  # frames per tick
	var looping: bool = track.get("loop", true)
	var inst := {}
	var over: Dictionary = track.get("inst", {})
	for k in DEFAULT_INST:
		inst[k] = _merged(DEFAULT_INST[k], over.get(k, {}))
	var errors: Array = []
	var raw: Array = []  # [tick, kind, data, pan]
	var tick := 0
	var loop_tick := 0
	var sections: Dictionary = track.sections
	for sname in String(track.form).split(" ", false):
		if sname == "|":
			loop_tick = tick
			continue
		if not sections.has(sname):
			errors.append("unknown section " + sname)
			continue
		var sec: Dictionary = sections[sname]
		var ch := parse_chart(sec.chords)
		var chart: Array = ch[0]
		var bars: int = ch[1]
		var ticks := bars * BAR
		for e in chart:
			if not e[1].ok:
				errors.append("%s: unknown chord quality" % sname)
		for part in ["lead", "lead2"]:
			if not sec.has(part):
				continue
			var m := parse_mml(sec[part])
			for err in m.errors:
				errors.append("%s.%s: %s" % [sname, part, err])
			if m.ticks != ticks:
				errors.append("%s.%s: %d ticks, section has %d (%d bars)" % [sname, part, m.ticks, ticks, bars])
			var ins: Dictionary = inst[part]
			for nt in m.notes:
				if nt[0] >= ticks:
					continue
				_add_note(raw, tick + nt[0], nt[1] * nt[4], Synth.midi_hz(nt[2]), nt[3], ins, spt, [])
				if ins.has("echo"):
					var ec: Array = ins.echo
					var echo_ins := ins.duplicate()
					echo_ins.pan = ec[2]
					_add_note(raw, tick + nt[0] + int(ec[0]), nt[1] * nt[4], Synth.midi_hz(nt[2]),
							nt[3] * ec[1], echo_ins, spt, [])
		var steps := ticks / STEP
		if sec.has("bass"):
			var ins: Dictionary = inst.bass
			var center: int = ins.center
			for h in _pattern_hits(sec.bass, steps):
				var at: int = h[0] * STEP
				var c := _chord_at(chart, at)
				var root := _near(c.bass, center)
				var croot := _near(c.root, center)
				var tones: Array = c.tones
				var m := root
				match h[2]:
					"O": m = root + 12
					"F": m = croot + 7 if croot + 7 <= center + 9 else croot - 5
					"L": m = croot - 5
					"T": m = croot + int(tones[1])
					"S": m = croot + int(tones[tones.size() - 1])
				_add_note(raw, tick + at, h[1] * STEP * float(ins.gate), Synth.midi_hz(m), 1.0, ins, spt, [])
		if sec.has("arp"):
			var ins: Dictionary = inst.arp
			var center: int = ins.center
			for h in _pattern_hits(sec.arp, steps):
				var at: int = h[0] * STEP
				var c := _chord_at(chart, at)
				var tones: Array = c.tones
				var root := _near(c.root, center)
				var arp: Array = []
				var m := root
				if h[2] == "C":
					arp = tones.slice(0, 4)
				else:
					var idx := int(h[2])
					m = root + int(tones[idx % tones.size()]) + 12 * (idx / tones.size())
				_add_note(raw, tick + at, h[1] * STEP * float(ins.gate), Synth.midi_hz(m),
						0.85 if h[2] == "C" else 1.0, ins, spt, arp)
		var dr: Dictionary = inst.drums
		var drum_parts: Array = []
		if sec.has("drums"):
			var p := _clean(sec.drums)
			if sec.has("fill") and bars >= 1:
				var body := ""
				for b in bars - 1:
					for k in 16:
						body += p[(b * 16 + k) % p.length()]
				p = body + _clean(sec.fill)
			drum_parts.append(p)
		if sec.has("hats"):
			drum_parts.append(sec.hats)
		if sec.get("crash", true) and sec.has("drums"):
			raw.append([tick, 1, "crash", 0.0, float(dr.crash)])
		for p in drum_parts:
			for h in _pattern_hits(p, steps):
				for hit in DRUM_HITS.get(h[2], []):
					var pan: float = dr.pan if hit == "hat" or hit == "ohat" else 0.0
					raw.append([tick + h[0] * STEP, 1, hit, pan, float(dr[hit])])
		tick += ticks
	var total_ticks := tick
	if loop_tick >= total_ticks:
		loop_tick = 0
	var tail := 0 if looping else int(float(track.get("tail", 0.8)) * Synth.RATE)
	var frames := int(round(total_ticks * spt)) + tail
	var loop_frame := int(round(loop_tick * spt)) if looping else frames
	var events: Array = []
	for r in raw:
		var f := int(round(r[0] * spt))
		var limit := frames
		if looping and f < loop_frame:
			limit = loop_frame
		var pan: float = r[3]
		var gl := minf(1.0, 1.0 - pan)
		var gr := minf(1.0, 1.0 + pan)
		if r[1] == 1:
			gl *= r[4]
			gr *= r[4]
		events.append([f, r[1], r[2], gl, gr, limit])
	events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return {"events": events, "frames": frames, "loop_frame": loop_frame, "looping": looping,
			"errors": errors, "bars": total_ticks / BAR, "bpm": bpm}


static func _add_note(raw: Array, tick: int, len_ticks: float, hz: float, vel: float,
		ins: Dictionary, spt: float, arp: Array) -> void:
	var p := {
		"w": ins.w, "f": hz, "len": maxf(len_ticks * spt / Synth.RATE, 0.01), "v": float(ins.v) * vel,
		"a": ins.a, "dc": ins.dc, "sus": ins.sus, "r": ins.r,
	}
	if ins.has("vib"):
		p.vib = ins.vib
	if ins.has("c"):
		p.c = ins.c
	if ins.has("d"):
		p.d = ins.d
	if not arp.is_empty():
		p.arp = arp
		p.at = ins.get("chord_t", 0.022)
	raw.append([tick, 0, p, float(ins.pan), 1.0])
