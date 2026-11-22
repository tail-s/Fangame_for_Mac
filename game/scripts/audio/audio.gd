extends Node
## Audio autoload ("Audio"): chip-style sound effects and music, all synthesised from
## code at runtime — the game ships without audio files.
##
##   Audio.sfx("jump")            one-shot effect (optional pitch scale)
##   Audio.music("prism_gecko")   looping track; same track again = no-op; "" stops
##   Audio.music("stage_clear")   jingles play once, then current_track becomes ""
##   Audio.stop_music()           fade out
##   Audio.set_volumes(0.8, 1.0)  linear 0..1 for the Music / SFX buses (0 = muted)
##
## How it stays hitch-free:
## - Effects are pre-rendered to 16-bit AudioStreamWAVs by a WorkerThreadPool task at
##   startup (an effect asked for before the task reaches it renders on the spot, a few
##   ms at most) and played from a pool of SFX_VOICES players.
## - Each music track is rendered by a WorkerThreadPool task (music_job.gd) into chunks
##   that stream into an AudioStreamGenerator as soon as they are ready; the main thread
##   only copies finished frames into the generator. Rendered tracks are cached
##   (MAX_CACHED most recent) so loops and returning to a track cost nothing.
## - Switching tracks fades the old one out over FADE_TIME on a second player.

signal music_finished(track: String)

const Synth = preload("res://scripts/audio/synth.gd")
const SfxData = preload("res://scripts/audio/sfx_data.gd")
const SfxBank = preload("res://scripts/audio/sfx_bank.gd")
const MusicData = preload("res://scripts/audio/music_data.gd")
const MusicJob = preload("res://scripts/audio/music_job.gd")

const SFX_NAMES: Array = [
	"jump", "land", "dash", "wall_kick", "shoot", "shoot_mid", "shoot_full", "charge",
	"charge_full", "saber", "saber_heavy", "parry", "hurt", "death", "enemy_hit", "enemy_die",
	"explosion", "big_explosion", "boss_hit", "weak_hit", "pickup", "capsule", "heal",
	"weapon_fire", "weapon_switch", "tag", "special", "door", "checkpoint", "menu_move",
	"menu_ok", "menu_back", "warning", "text", "break", "crumble", "laser",
]
const TRACKS: Array = [
	"title", "select", "story", "training", "prism_gecko", "gravity_albatross", "solar_fennec",
	"cryo_narwhal", "terra_pangolin", "pulse_cicada", "final_eden_core", "boss", "hidden_boss",
	"final_boss", "ending", "stage_clear", "boss_intro",
]
const JINGLES: Array = ["stage_clear", "boss_intro"]

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const SFX_VOICES := 12
const RATE_LIMIT_MSEC := 40
const FADE_TIME := 0.3
const MUSIC_BUFFER_SEC := 0.25
const MAX_CACHED := 3
## A stopped playback is only unlinked by the audio mix thread on its next mix step(s);
## if the engine shuts down before that, it reports "ObjectDB instances were leaked"
## (seen in headless test runs that quit while sounds play). So at shutdown, if any
## playback we started may still be registered, sleep this long once (shutdown only).
const EXIT_DRAIN_MSEC := 120

var current_track := ""
var music_volume := 1.0
var sfx_volume := 1.0
## Timing / usage counters (microseconds) for tests and the debug overlay.
var stats := {
	"ready_usec": 0, "process_max_usec": 0, "process_total_usec": 0, "process_frames": 0,
	"sfx_max_usec": 0, "music_max_usec": 0, "sfx_played": 0, "sfx_limited": 0, "sfx_sync_renders": 0,
}

var _bank: SfxBank
var _streams := {}  # name -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _player_sfx: Array[String] = []
var _player_started: Array[int] = []
var _last_play := {}  # name -> msec
var _warned := {}
var _live: Array[WeakRef] = []  # playbacks we started that the engine has not freed yet

var _decks: Array[Deck] = []
var _active: Deck = null
var _jobs := {}  # track -> MusicJob (rendering or rendered)
var _lru: Array[String] = []
var _dying: Array = []  # evicted / cancelled jobs whose task still has to be waited for


## One music player: an AudioStreamGenerator fed from a MusicJob's chunks.
class Deck:
	var player: AudioStreamPlayer
	var pb: AudioStreamGeneratorPlayback
	var job: MusicJob
	var capacity := 0  # generator buffer size in frames
	var track := ""
	var chunk := 0
	var off := 0
	var ended := false  # a jingle has pushed its last frame
	var end_msec := 0  # when that last frame has been heard
	var fade := -1.0  # >= 0: fading out, seconds left

	func idle() -> bool:
		return job == null and fade < 0.0


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_players.append(p)
		_player_sfx.append("")
		_player_started.append(0)
	for i in 2:
		var d := Deck.new()
		d.player = AudioStreamPlayer.new()
		d.player.bus = MUSIC_BUS
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = Synth.RATE
		gen.buffer_length = MUSIC_BUFFER_SEC
		d.player.stream = gen
		add_child(d.player)
		_decks.append(d)
	_bank = SfxBank.new()
	_bank.task_id = WorkerThreadPool.add_task(_bank.render_all, false, "Audio SFX")
	set_volumes(music_volume, sfx_volume)
	if current_track != "":  # music() was called before we were ready
		var track := current_track
		current_track = ""
		music(track)
	stats.ready_usec = Time.get_ticks_usec() - t0


func _exit_tree() -> void:
	if _bank != null:
		_bank.cancel()
	for job in _jobs.values():
		job.cancel()
	for job in _dying:
		job.cancel()
	for p in _players:
		p.stop()
	for deck in _decks:
		_stop_deck(deck)
	_prune_live()
	if not _live.is_empty():
		OS.delay_msec(EXIT_DRAIN_MSEC)  # shutdown only, see EXIT_DRAIN_MSEC
	_live.clear()
	if _bank != null and _bank.task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_bank.task_id)
		_bank.task_id = -1
	for job in _jobs.values() + _dying:
		if job.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			job.task_id = -1
	_jobs.clear()
	_dying.clear()
	_active = null
	current_track = ""


func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


# --- public API ------------------------------------------------------------------------

func sfx(sfx_name: String, pitch := 1.0) -> void:
	if _players.is_empty():
		return  # not ready yet
	var t0 := Time.get_ticks_usec()
	var stream := _stream(sfx_name)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(sfx_name, -100000)) < RATE_LIMIT_MSEC:
		stats.sfx_limited += 1
		return
	_last_play[sfx_name] = now
	var slot := -1
	var oldest := 0
	for i in SFX_VOICES:
		if _player_sfx[i] == sfx_name and _players[i].playing:
			slot = i  # restart the same effect instead of stacking copies
			break
		if slot < 0 and not _players[i].playing:
			slot = i
	if slot < 0:
		for i in SFX_VOICES:
			if _player_started[i] < _player_started[oldest]:
				oldest = i
		slot = oldest
	var p := _players[slot]
	p.stream = stream
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.play()
	_live.append(weakref(p.get_stream_playback()))
	_player_sfx[slot] = sfx_name
	_player_started[slot] = now
	stats.sfx_played += 1
	stats.sfx_max_usec = maxi(stats.sfx_max_usec, Time.get_ticks_usec() - t0)


## Stops an effect that is still sounding (e.g. the charge whirr when the shot is released).
func stop_sfx(sfx_name: String) -> void:
	for i in SFX_VOICES:
		if _player_sfx[i] == sfx_name and _players[i].playing:
			_players[i].stop()


func music(track: String) -> void:
	if track == "":
		stop_music()
		return
	if track == current_track and _active != null:
		return
	var t0 := Time.get_ticks_usec()
	if not MusicData.TRACKS.has(track):
		_warn_once("music:" + track, "Audio: unknown music track '%s'" % track)
		return
	if _decks.is_empty():
		current_track = track  # not ready yet: _ready() starts it
		return
	_fade_out_active()
	var deck: Deck = null
	for d in _decks:
		if d.idle():
			deck = d
			break
	if deck == null:  # both still fading (very fast switching): cut the quieter one
		deck = _decks[0] if _decks[0].fade <= _decks[1].fade else _decks[1]
		_stop_deck(deck)
	deck.job = _job_for(track)
	deck.track = track
	deck.chunk = 0
	deck.off = 0
	deck.ended = false
	deck.fade = -1.0
	deck.player.volume_db = 0.0
	deck.player.play()
	deck.pb = deck.player.get_stream_playback()
	_live.append(weakref(deck.pb))
	deck.capacity = deck.pb.get_frames_available()
	_active = deck
	current_track = track
	_feed(deck)
	stats.music_max_usec = maxi(stats.music_max_usec, Time.get_ticks_usec() - t0)


func stop_music() -> void:
	_fade_out_active()
	current_track = ""


func set_volumes(music_linear: float, sfx_linear: float) -> void:
	music_volume = clampf(music_linear, 0.0, 1.0)
	sfx_volume = clampf(sfx_linear, 0.0, 1.0)
	for pair in [[MUSIC_BUS, music_volume], [SFX_BUS, sfx_volume]]:
		var idx := _ensure_bus(pair[0])
		var v: float = pair[1]
		AudioServer.set_bus_mute(idx, v <= 0.0001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


# --- per frame -------------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	for deck in _decks:
		if deck.fade >= 0.0:
			deck.fade -= delta
			if deck.fade <= 0.0:
				_stop_deck(deck)
			else:
				deck.player.volume_db = linear_to_db(deck.fade / FADE_TIME)
				_feed(deck)
		elif deck == _active:
			_feed(deck)
			if deck.ended and Time.get_ticks_msec() >= deck.end_msec:
				var track := deck.track
				_stop_deck(deck)
				_active = null
				if current_track == track:
					current_track = ""
				music_finished.emit(track)
	_reap_jobs()
	if Engine.get_process_frames() % 30 == 0:
		_prune_live()
	var dt := Time.get_ticks_usec() - t0
	stats.process_max_usec = maxi(stats.process_max_usec, dt)
	stats.process_total_usec += dt
	stats.process_frames += 1


## Copies as many rendered frames as the generator has room for.
func _feed(deck: Deck) -> void:
	if deck.pb == null or deck.job == null or deck.ended:
		return
	var room := deck.pb.get_frames_available()
	if room <= 0:
		return
	var frames := pull(deck, room)
	if not frames.is_empty():
		deck.pb.push_buffer(frames)
	if deck.ended:
		var buffered := deck.capacity - deck.pb.get_frames_available()
		deck.end_msec = Time.get_ticks_msec() + int(buffered * 1000.0 / Synth.RATE) + 100


## Takes up to `room` frames from the deck's job, following the loop point; sets
## deck.ended after the last frame of a non-looping track. (Public for tests.)
func pull(deck: Deck, room: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var job := deck.job
	var info: Dictionary = job.info()
	if not info.planned:
		return out
	var wraps := 0
	while room > 0 and wraps < 2:
		var c: PackedVector2Array = job.chunk(deck.chunk)
		if c.is_empty():
			info = job.info()
			if deck.chunk < info.chunks:
				continue  # published meanwhile
			if not info.done:
				break  # not rendered yet
			if info.looping:
				wraps += 1
				deck.chunk = info.loop_frame / MusicJob.CHUNK
				deck.off = info.loop_frame % MusicJob.CHUNK
				if info.chunks == 0:
					break
				continue
			deck.ended = true
			break
		var take := mini(room, c.size() - deck.off)
		if deck.off == 0 and take == c.size():
			out.append_array(c)
		else:
			out.append_array(c.slice(deck.off, deck.off + take))
		room -= take
		deck.off += take
		if deck.off >= c.size():
			deck.chunk += 1
			deck.off = 0
			info = job.info()
	return out


func _fade_out_active() -> void:
	if _active == null:
		return
	if _active.ended:
		_stop_deck(_active)
	else:
		_active.fade = FADE_TIME
	_active = null


func _stop_deck(deck: Deck) -> void:
	deck.player.stop()
	deck.pb = null
	deck.job = null
	deck.track = ""
	deck.fade = -1.0
	deck.ended = false


# --- music jobs / cache ----------------------------------------------------------------

func _job_for(track: String) -> MusicJob:
	var job: MusicJob = _jobs.get(track)
	if job == null:
		job = MusicJob.new(track, MusicData.TRACKS[track])
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Audio music " + track)
		_jobs[track] = job
	_lru.erase(track)
	_lru.push_back(track)
	_evict()
	return job


func _evict() -> void:
	var i := 0
	while _lru.size() > MAX_CACHED and i < _lru.size():
		var track := _lru[i]
		var in_use := false
		for d in _decks:
			if d.job != null and d.job == _jobs.get(track):
				in_use = true
		if in_use:
			i += 1
			continue
		var job = _jobs[track]
		job.cancel()
		_dying.append(job)
		_jobs.erase(track)
		_lru.remove_at(i)


func _reap_jobs() -> void:
	for job in _jobs.values():
		if job.task_id >= 0 and WorkerThreadPool.is_task_completed(job.task_id):
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			job.task_id = -1
			for err in job.info().errors:
				_warn_once("music_err:" + job.track, "Audio: track %s: %s" % [job.track, err])
	for k in range(_dying.size() - 1, -1, -1):
		var job = _dying[k]
		if job.task_id < 0 or WorkerThreadPool.is_task_completed(job.task_id):
			if job.task_id >= 0:
				WorkerThreadPool.wait_for_task_completion(job.task_id)
			_dying.remove_at(k)
	if _bank.task_id >= 0 and WorkerThreadPool.is_task_completed(_bank.task_id):
		WorkerThreadPool.wait_for_task_completion(_bank.task_id)
		_bank.task_id = -1


func _prune_live() -> void:
	for k in range(_live.size() - 1, -1, -1):
		if _live[k].get_ref() == null:
			_live.remove_at(k)


## Total bytes held by rendered music chunks and effect streams.
func memory_bytes() -> int:
	var n := 0
	for job in _jobs.values():
		n += job.memory_bytes()
	for s in _streams.values():
		n += s.data.size()
	return n


# --- effects ---------------------------------------------------------------------------

func _stream(sfx_name: String) -> AudioStreamWAV:
	var s: AudioStreamWAV = _streams.get(sfx_name)
	if s != null:
		return s
	if not SfxData.SFX.has(sfx_name):
		_warn_once("sfx:" + sfx_name, "Audio: unknown sound effect '%s'" % sfx_name)
		return null
	var pcm: PackedByteArray = _bank.get_pcm(sfx_name)
	if pcm.is_empty():
		pcm = _bank.render_now(sfx_name)
		stats.sfx_sync_renders += 1
	s = Synth.make_wav(pcm)
	_streams[sfx_name] = s
	return s


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)
