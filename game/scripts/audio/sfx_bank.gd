extends RefCounted
## Pre-renders every sound effect to 16-bit PCM. render_all() runs once on a
## WorkerThreadPool thread at startup; an effect requested before the worker reaches it
## is rendered on the spot by render_now() (each takes at most a few ms).

const Synth = preload("res://scripts/audio/synth.gd")
const SfxData = preload("res://scripts/audio/sfx_data.gd")

var task_id := -1
var render_usec := 0

var _mutex := Mutex.new()
var _pcm := {}  # name -> PackedByteArray
var _cancel := false
var _done := false
var _main_synth: RefCounted


func render_all() -> void:
	var t0 := Time.get_ticks_usec()
	var synth := Synth.new()
	for sfx_name in SfxData.SFX:
		_mutex.lock()
		var skip := _cancel or _pcm.has(sfx_name)
		var stop := _cancel
		_mutex.unlock()
		if stop:
			break
		if skip:
			continue
		var pcm := Synth.to_pcm16(synth.render_sfx(SfxData.SFX[sfx_name]))
		_mutex.lock()
		if not _pcm.has(sfx_name):
			_pcm[sfx_name] = pcm
		_mutex.unlock()
	render_usec = Time.get_ticks_usec() - t0
	_mutex.lock()
	_done = true
	_mutex.unlock()


func cancel() -> void:
	_mutex.lock()
	_cancel = true
	_mutex.unlock()


func is_done() -> bool:
	_mutex.lock()
	var d := _done
	_mutex.unlock()
	return d


## PCM of an effect, or an empty array if the worker has not rendered it yet.
func get_pcm(sfx_name: String) -> PackedByteArray:
	_mutex.lock()
	var pcm: PackedByteArray = _pcm.get(sfx_name, PackedByteArray())
	_mutex.unlock()
	return pcm


## Renders an effect on the calling (main) thread right now.
func render_now(sfx_name: String) -> PackedByteArray:
	if _main_synth == null:
		_main_synth = Synth.new()
	var pcm := Synth.to_pcm16(_main_synth.render_sfx(SfxData.SFX[sfx_name]))
	_mutex.lock()
	if not _pcm.has(sfx_name):
		_pcm[sfx_name] = pcm
	_mutex.unlock()
	return pcm
