extends RefCounted
## Renders one music track on a WorkerThreadPool thread and publishes it in fixed-size
## chunks of stereo frames as soon as they are final, so playback can start after the
## first few milliseconds of work. Once done, the chunks are the whole loop and are kept
## as a cache by the Audio autoload.
##
## Notes are rendered whole, in start order, into float buffers; every frame before the
## start of the next unrendered note is final, which is what lets chunks stream out.

const Synth = preload("res://scripts/audio/synth.gd")
const Sequencer = preload("res://scripts/audio/sequencer.gd")

const CHUNK := 2048  # frames per published chunk
const MASTER := 0.8

var track := ""
var data: Dictionary
var task_id := -1

# Written by the worker under `mutex`; read by the main thread through the accessors.
var mutex := Mutex.new()
var _chunks: Array[PackedVector2Array] = []
var _frames := 0
var _loop_frame := 0
var _looping := true
var _planned := false
var _done := false
var _cancel := false
var _errors: Array = []
var render_usec := 0
var first_chunk_usec := -1

# Master bus state (worker only)
var _xl := 0.0
var _xr := 0.0
var _yl := 0.0
var _yr := 0.0


func _init(track_name: String, track_data: Dictionary) -> void:
	track = track_name
	data = track_data


func cancel() -> void:
	mutex.lock()
	_cancel = true
	mutex.unlock()


func is_cancelled() -> bool:
	mutex.lock()
	var c := _cancel
	mutex.unlock()
	return c


func is_done() -> bool:
	mutex.lock()
	var d := _done
	mutex.unlock()
	return d


## Chunk i, or an empty array if it is not rendered (yet).
func chunk(i: int) -> PackedVector2Array:
	mutex.lock()
	var c: PackedVector2Array = _chunks[i] if i < _chunks.size() else PackedVector2Array()
	mutex.unlock()
	return c


func info() -> Dictionary:
	mutex.lock()
	var d := {"chunks": _chunks.size(), "done": _done, "planned": _planned, "frames": _frames,
			"loop_frame": _loop_frame, "looping": _looping, "errors": _errors.duplicate()}
	mutex.unlock()
	return d


func memory_bytes() -> int:
	mutex.lock()
	var n := 0
	for c in _chunks:
		n += c.size() * 8
	mutex.unlock()
	return n


## Worker entry point (also callable directly, e.g. from tests).
func run() -> void:
	var t0 := Time.get_ticks_usec()
	var p := Sequencer.plan(data)
	var frames: int = p.frames
	mutex.lock()
	_frames = frames
	_loop_frame = p.loop_frame
	_looping = p.looping
	_errors = p.errors
	_planned = true
	mutex.unlock()
	var synth := Synth.new()
	var kit := synth.drum_kit()
	var buf_l := PackedFloat32Array()
	var buf_r := PackedFloat32Array()
	buf_l.resize(frames)
	buf_r.resize(frames)
	var published := 0
	var events: Array = p.events
	for ev in events:
		var at: int = ev[0]
		if at >= frames:
			continue
		if at - published >= CHUNK:
			if is_cancelled():
				return
			published = _publish(buf_l, buf_r, published, at - (at - published) % CHUNK)
			if first_chunk_usec < 0:
				first_chunk_usec = Time.get_ticks_usec() - t0
		var src: PackedFloat32Array
		if ev[1] == 1:
			src = kit[ev[2]]
		else:
			src = synth.voice(ev[2])
		Synth.mix(buf_l, buf_r, src, at, ev[3], ev[4], ev[5])
	_publish(buf_l, buf_r, published, frames)
	render_usec = Time.get_ticks_usec() - t0
	if first_chunk_usec < 0:
		first_chunk_usec = render_usec
	mutex.lock()
	_done = true
	mutex.unlock()


## Converts frames [from, to) into chunks (DC blocker + soft clip) and publishes them.
func _publish(buf_l: PackedFloat32Array, buf_r: PackedFloat32Array, from: int, to: int) -> int:
	var pos := from
	while pos < to:
		var n := mini(CHUNK, to - pos)
		var c := PackedVector2Array()
		c.resize(n)
		for k in n:
			var xl := buf_l[pos + k] * MASTER
			var xr := buf_r[pos + k] * MASTER
			_yl = xl - _xl + 0.996 * _yl
			_yr = xr - _xr + 0.996 * _yr
			_xl = xl
			_xr = xr
			var l := _yl
			var r := _yr
			if absf(l) > 0.8:
				l = signf(l) * (0.8 + 0.19 * tanh((absf(l) - 0.8) / 0.19))
			if absf(r) > 0.8:
				r = signf(r) * (0.8 + 0.19 * tanh((absf(r) - 0.8) / 0.19))
			c[k] = Vector2(l, r)
		mutex.lock()
		_chunks.append(c)
		mutex.unlock()
		pos += n
	return pos
