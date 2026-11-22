extends SceneTree
## Audio autoload tests: every effect and track renders with sane levels, tracks loop
## (jingles end), the public API behaves, and the main thread stays cheap.
## Run:    godot --headless --fixed-fps 60 --path game -s res://tests/audio_test.gd
## Listen: ... -s res://tests/audio_test.gd -- --wav-out=/tmp/claude-audio-preview
##         (writes sfx_*.wav and music_*.wav — every effect, first ~20 s of every track)

const PREVIEW_SEC := 20.0
## Effects allowed to run past the usual 0.35 s.
const LONG_SFX := ["warning", "big_explosion", "charge", "death", "capsule", "door",
		"explosion", "special"]

var _pass := 0
var _fail := 0
var _wav_out := ""

var AudioScript: GDScript
var MusicJob: GDScript
var Sequencer: GDScript
var MusicData: GDScript
var SfxData: GDScript
var Synth: GDScript
var audio: Node
var _jobs := {}  # track -> rendered MusicJob (from test_tracks_render)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wav-out="):
			_wav_out = a.substr("--wav-out=".length())
	_run_all.call_deferred()


func _run_all() -> void:
	await test_startup()
	await test_sfx_streams()
	test_sfx_api()
	test_compositions()
	test_tracks_render()
	await test_music_api()
	await test_frame_cost()
	test_volumes()
	if _wav_out != "":
		write_previews()
	# Free while music and effects are still sounding: _exit_tree must stop them, wait for
	# the worker tasks and drain the mixer so the run ends without leak warnings.
	audio.music("final_boss")
	for nm: String in audio.SFX_NAMES:
		audio.sfx(nm)
	await process_frame
	var t_free := Time.get_ticks_usec()
	root.remove_child(audio)
	audio.free()
	var free_ms := (Time.get_ticks_usec() - t_free) / 1000.0
	_jobs.clear()
	_check(free_ms < 300.0, "shutdown while playing takes %.1f ms (one-off %d ms mixer drain)" % [free_ms, AudioScript.EXIT_DRAIN_MSEC])
	_check(not is_instance_valid(audio), "autoload frees cleanly (worker tasks waited)")
	if _fail == 0:
		print("\nALL %d OK" % _pass)
	else:
		print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- startup ---------------------------------------------------------------------------

func test_startup() -> void:
	var t0 := Time.get_ticks_usec()
	AudioScript = load("res://scripts/audio/audio.gd")
	var t_load := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	audio = AudioScript.new()
	root.add_child(audio)
	var t_ready := Time.get_ticks_usec() - t0
	print("  startup: load+compile %.1f ms, _ready %.2f ms" % [t_load / 1000.0, t_ready / 1000.0])
	_check(t_load + t_ready < 200000, "autoload startup %.1f ms (< 200 ms, scripts included)" % [(t_load + t_ready) / 1000.0])
	_check(t_ready < 15000, "_ready blocks the main thread %.2f ms (< 15 ms)" % [t_ready / 1000.0])
	MusicJob = load("res://scripts/audio/music_job.gd")
	Sequencer = load("res://scripts/audio/sequencer.gd")
	MusicData = load("res://scripts/audio/music_data.gd")
	SfxData = load("res://scripts/audio/sfx_data.gd")
	Synth = load("res://scripts/audio/synth.gd")
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	_check(mi > 0 and si > 0 and AudioServer.get_bus_send(mi) == "Master"
			and AudioServer.get_bus_send(si) == "Master", "Music and SFX buses exist and send to Master")
	var names: Array = audio.SFX_NAMES
	_check(names.size() == 37 and _same_keys(names, SfxData.SFX), "SFX_NAMES (%d) match the effect recipes" % names.size())
	var tracks: Array = audio.TRACKS
	_check(tracks.size() == 17 and _same_keys(tracks, MusicData.TRACKS), "TRACKS (%d) match the compositions" % tracks.size())
	var start := Time.get_ticks_msec()
	while not audio._bank.is_done() and Time.get_ticks_msec() - start < 5000:
		await process_frame
	_check(audio._bank.is_done(), "all effects pre-rendered in the background (%.0f ms worker time)" % [audio._bank.render_usec / 1000.0])
	var early: Node = AudioScript.new()
	early.sfx("jump")
	early.music("story")
	root.add_child(early)
	_check(early.current_track == "story" and early._active != null, "calls made before _ready are safe; a requested track starts once ready")
	root.remove_child(early)
	early.free()


func _same_keys(a: Array, d: Dictionary) -> bool:
	if a.size() != d.size():
		return false
	for k in a:
		if not d.has(k):
			return false
	return true


# --- effects ---------------------------------------------------------------------------

func test_sfx_streams() -> void:
	var bad: Array = []
	var long: Array = []
	var total_bytes := 0
	for n: String in audio.SFX_NAMES:
		var s: AudioStreamWAV = audio._stream(n)
		if s == null:
			bad.append(n + " (no stream)")
			continue
		var dur := s.get_length()
		var st := _pcm_stats(s.data)
		total_bytes += s.data.size()
		if dur < 0.01 or dur > 1.3:
			bad.append("%s length %.3f s" % [n, dur])
		if st.peak < 0.05 or st.peak > 0.95:
			bad.append("%s peak %.3f" % [n, st.peak])
		if absf(st.dc) > 0.03:
			bad.append("%s DC offset %.3f" % [n, st.dc])
		if dur > 0.35 and not LONG_SFX.has(n):
			long.append("%s %.2f s" % [n, dur])
	_check(bad.is_empty(), "every effect has a stream of sane length, level and DC %s" % str(bad))
	_check(long.is_empty(), "short effects stay under 0.35 s %s" % str(long))
	var text: AudioStreamWAV = audio._stream("text")
	_check(text.get_length() < 0.03 and _pcm_stats(text.data).peak < 0.2,
			"text blip is tiny and quiet (%.3f s)" % text.get_length())
	var warn: AudioStreamWAV = audio._stream("warning")
	var boom: AudioStreamWAV = audio._stream("big_explosion")
	var charge: AudioStreamWAV = audio._stream("charge")
	_check(absf(warn.get_length() - 1.0) < 0.1 and absf(boom.get_length() - 1.0) < 0.15
			and absf(charge.get_length() - 0.6) < 0.08,
			"warning ~1 s (%.2f), big_explosion ~1 s (%.2f), charge ~0.6 s (%.2f)"
			% [warn.get_length(), boom.get_length(), charge.get_length()])
	print("  effects: %d streams, %.0f KB of PCM" % [audio.SFX_NAMES.size(), total_bytes / 1024.0])
	# Fallback path: an effect asked for before the startup worker reached it renders on
	# the main thread. Time the worst case (longest effect, cold synth).
	var bank = load("res://scripts/audio/sfx_bank.gd").new()
	var worst := 0
	var worst_name := ""
	for n: String in audio.SFX_NAMES:
		var t0 := Time.get_ticks_usec()
		bank.render_now(n)
		var dt := Time.get_ticks_usec() - t0
		if dt > worst:
			worst = dt
			worst_name = n
	_check(worst < 15000, "on-demand render of one effect on the main thread: worst %.2f ms (%s, < 15 ms)" % [worst / 1000.0, worst_name])


func test_sfx_api() -> void:
	var played0: int = audio.stats.sfx_played
	for n: String in audio.SFX_NAMES:
		audio.sfx(n)
	_check(audio.stats.sfx_played - played0 == audio.SFX_NAMES.size(), "sfx() plays every effect")
	var playing := 0
	for p: AudioStreamPlayer in audio._players:
		if p.playing:
			playing += 1
	_check(audio._players.size() == 12 and playing <= 12, "polyphony is capped at 12 voices (%d playing)" % playing)
	var limited0: int = audio.stats.sfx_limited
	audio.sfx("jump")
	audio.sfx("jump")
	_check(audio.stats.sfx_limited - limited0 >= 1, "the same effect is rate-limited within 40 ms")
	var before: int = audio.stats.sfx_played
	audio.sfx("no_such_effect")
	audio.sfx("no_such_effect")
	_check(audio.stats.sfx_played == before, "unknown effect names are ignored")
	audio._last_play.clear()
	audio.sfx("shoot", 1.5)
	var ok := false
	for i in audio._players.size():
		if audio._player_sfx[i] == "shoot" and is_equal_approx(audio._players[i].pitch_scale, 1.5):
			ok = true
	_check(ok, "pitch argument sets the player's pitch scale")
	audio.stop_sfx("shoot")


# --- music: data and rendering -------------------------------------------------------------

func test_compositions() -> void:
	var problems: Array = []
	for t: String in audio.TRACKS:
		var data: Dictionary = MusicData.TRACKS[t]
		var p: Dictionary = Sequencer.plan(data)
		for e in p.errors:
			problems.append("%s: %s" % [t, e])
		var sec: float = p.frames / float(Synth.RATE)
		if audio.JINGLES.has(t):
			if p.looping:
				problems.append(t + " should not loop")
		else:
			if not p.looping or p.bars < 16 or p.bars > 32:
				problems.append("%s: %d bars, looping %s" % [t, p.bars, p.looping])
			if p.loop_frame >= p.frames:
				problems.append(t + ": loop point past the end")
		print("  %-18s %3d bpm  %2d bars  %5.1f s  %4d events" % [t, p.bpm, p.bars, sec, p.events.size()])
	_check(problems.is_empty(), "every track parses, every bar line lines up %s" % str(problems))
	var sc: Dictionary = Sequencer.plan(MusicData.TRACKS.stage_clear)
	var bi: Dictionary = Sequencer.plan(MusicData.TRACKS.boss_intro)
	_check(absf(sc.frames / 22050.0 - 3.0) < 0.8 and absf(bi.frames / 22050.0 - 2.0) < 0.6,
			"jingle lengths: stage_clear %.2f s (~3), boss_intro %.2f s (~2)" % [sc.frames / 22050.0, bi.frames / 22050.0])


func test_tracks_render() -> void:
	var silent: Array = []
	var levels: Array = []
	var loops: Array = []
	var total_mem := 0
	var worst_first := 0
	var worst_render := 0
	for t: String in audio.TRACKS:
		var job = MusicJob.new(t, MusicData.TRACKS[t])
		job.run()
		_jobs[t] = job
		var info: Dictionary = job.info()
		worst_first = maxi(worst_first, job.first_chunk_usec)
		worst_render = maxi(worst_render, job.render_usec)
		total_mem += job.memory_bytes()
		# audibility over the first seconds, clipping / DC over the whole loop
		var head := _pull_frames(job, mini(info.frames, 8 * 22050))
		var st := _vec_stats(head)
		var whole := _vec_stats(_pull_frames(job, info.frames), 3)
		st.peak = maxf(st.peak, whole.peak)
		st.dc = whole.dc
		print("  %-18s render %6.1f ms (first chunk %4.1f ms)  %.1f MB  peak %.2f  rms %.3f  dc %+.4f"
				% [t, job.render_usec / 1000.0, job.first_chunk_usec / 1000.0, job.memory_bytes() / 1048576.0,
				st.peak, st.rms, st.dc])
		if st.rms < 0.03:
			silent.append("%s rms %.3f" % [t, st.rms])
		if st.peak > 0.995 or absf(st.dc) > 0.01:
			levels.append("%s peak %.3f dc %.4f" % [t, st.peak, st.dc])
		# loop / end behaviour through the real pull() logic
		var deck = AudioScript.Deck.new()
		deck.job = job
		var pulled := 0
		var target: int = info.frames * 2 + 5000
		var guard := 0
		while pulled < target and not deck.ended and guard < 100000:
			var f: PackedVector2Array = audio.pull(deck, 1500)
			if f.is_empty():
				break
			pulled += f.size()
			guard += 1
		if audio.JINGLES.has(t):
			if not deck.ended or pulled != info.frames:
				loops.append("%s: jingle should end after %d frames (pulled %d, ended %s)" % [t, info.frames, pulled, deck.ended])
		elif deck.ended or pulled < target:
			loops.append("%s: loop stopped after %d of %d frames" % [t, pulled, target])
		else:
			# seam: last frame of the loop vs the loop start
			var last: Vector2 = job.chunk(info.chunks - 1)[job.chunk(info.chunks - 1).size() - 1]
			var lf: int = info.loop_frame
			var first: Vector2 = job.chunk(lf / MusicJob.CHUNK)[lf % MusicJob.CHUNK]
			if (last - first).length() > 0.5:
				loops.append("%s: loop seam jump %.2f" % [t, (last - first).length()])
	_check(silent.is_empty(), "every track is audible in its first seconds %s" % str(silent))
	_check(levels.is_empty(), "no clipping and no DC offset in any track %s" % str(levels))
	_check(loops.is_empty(), "tracks loop seamlessly through pull(), jingles end %s" % str(loops))
	print("  music: worst full render %.0f ms, worst time to first chunk %.1f ms (worker), all tracks %.1f MB"
			% [worst_render / 1000.0, worst_first / 1000.0, total_mem / 1048576.0])
	_check(worst_first < 60000, "a track starts streaming within %.1f ms of worker time (< 60)" % [worst_first / 1000.0])


func _pull_frames(job, n: int) -> PackedVector2Array:
	var deck = AudioScript.Deck.new()
	deck.job = job
	var out := PackedVector2Array()
	while out.size() < n and not deck.ended:
		var f: PackedVector2Array = audio.pull(deck, mini(4096, n - out.size()))
		if f.is_empty():
			break
		out.append_array(f)
	return out


# --- music: API on the live node -----------------------------------------------------

func test_music_api() -> void:
	audio.stats.music_max_usec = 0
	audio.music("title")
	_check(audio.current_track == "title" and audio._active != null, "music() starts a track")
	var deck = audio._active
	var start := Time.get_ticks_msec()
	while deck.chunk == 0 and deck.off == 0 and Time.get_ticks_msec() - start < 2000:
		await process_frame
	_check(deck.chunk > 0 or deck.off > 0, "rendered frames reach the generator (%d ms)" % (Time.get_ticks_msec() - start))
	var pos: int = deck.chunk * MusicJob.CHUNK + deck.off
	audio.music("title")
	_check(audio._active == deck and deck.chunk * MusicJob.CHUNK + deck.off >= pos, "the same track again does not restart it")
	audio.music("boss")
	_check(audio.current_track == "boss" and deck.fade > 0.0 and audio._active != deck,
			"switching fades the old track out on the other player")
	for i in 30:
		await process_frame
	_check(deck.job == null and not deck.player.playing, "the old track stops after the 0.3 s fade")
	audio.music("not_a_track")
	_check(audio.current_track == "boss", "unknown tracks are ignored")
	audio.music("")
	_check(audio.current_track == "" and audio._active == null, "music(\"\") stops (fades) the music")
	for i in 30:
		await process_frame
	# jingle: plays once, then current_track goes back to ""
	var finished := [""]
	audio.music_finished.connect(func(t: String) -> void: finished[0] = t)
	audio.music("boss_intro")
	start = Time.get_ticks_msec()
	while audio.current_track == "boss_intro" and Time.get_ticks_msec() - start < 6000:
		await process_frame
	var took := Time.get_ticks_msec() - start
	_check(audio.current_track == "" and finished[0] == "boss_intro",
			"jingle boss_intro ends by itself after %.1f s and emits music_finished" % (took / 1000.0))
	# every track can be started
	var started := 0
	for t: String in audio.TRACKS:
		audio.music(t)
		if audio.current_track == t:
			started += 1
		for i in 3:
			await process_frame
	_check(started == audio.TRACKS.size(), "every track starts through music() (%d)" % started)
	audio.stop_music()
	_check(audio._jobs.size() <= audio.MAX_CACHED + 1, "rendered tracks are cached LRU (%d kept)" % audio._jobs.size())
	_check(audio.stats.music_max_usec < 15000, "music() never blocks over 15 ms (worst %.2f ms)" % [audio.stats.music_max_usec / 1000.0])


func test_frame_cost() -> void:
	# Real-time-ish load: effects every frame, a track switch every second (some uncached,
	# so render jobs run on workers meanwhile). Measures the autoload's own main-thread work.
	for k in audio.stats:
		if k.ends_with("_usec") and k != "ready_usec":
			audio.stats[k] = 0
	audio.stats.process_frames = 0
	var names: Array = audio.SFX_NAMES
	var tracks := ["training", "boss", "prism_gecko", "final_boss", "cryo_narwhal", "boss", "ending"]
	var worst_call := 0
	var start := Time.get_ticks_msec()
	var frames := 0
	while Time.get_ticks_msec() - start < 7000:
		if frames % 60 == 0:
			audio.music(tracks[(frames / 60) % tracks.size()])
		var t0 := Time.get_ticks_usec()
		for j in 3:
			audio.sfx(names[(frames * 3 + j) % names.size()], 0.9 + 0.1 * j)
		worst_call = maxi(worst_call, Time.get_ticks_usec() - t0)
		frames += 1
		await process_frame
		OS.delay_msec(10)  # leave real time for the audio thread to consume frames
	var pf: int = audio.stats.process_frames
	var avg: float = audio.stats.process_total_usec / maxf(pf, 1.0)
	print("  frame cost over %d frames: _process worst %.3f ms, avg %.3f ms; 3x sfx() worst %.3f ms; music() worst %.3f ms; skips %d"
			% [pf, audio.stats.process_max_usec / 1000.0, avg / 1000.0, worst_call / 1000.0,
			audio.stats.music_max_usec / 1000.0, audio._active.pb.get_skips() if audio._active and audio._active.pb else -1])
	_check(audio.stats.process_max_usec < 1500, "worst _process %.3f ms (< 1.5 ms)" % [audio.stats.process_max_usec / 1000.0])
	_check(worst_call < 1500, "worst 3 x sfx() in one frame %.3f ms (< 1.5 ms)" % [worst_call / 1000.0])
	_check(audio.stats.music_max_usec < 15000, "worst music() call %.3f ms (< 15 ms)" % [audio.stats.music_max_usec / 1000.0])
	print("  memory: audio data held %.1f MB (cached tracks + effects), static total %.1f MB"
			% [audio.memory_bytes() / 1048576.0, OS.get_static_memory_usage() / 1048576.0])
	audio.stop_music()


func test_volumes() -> void:
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	audio.set_volumes(0.0, 0.5)
	_check(AudioServer.is_bus_mute(mi) and not AudioServer.is_bus_mute(si)
			and absf(AudioServer.get_bus_volume_db(si) - linear_to_db(0.5)) < 0.01,
			"set_volumes(0, 0.5): music muted, effects at -6 dB")
	audio.set_volumes(1.0, 0.0)
	_check(not AudioServer.is_bus_mute(mi) and AudioServer.is_bus_mute(si)
			and absf(AudioServer.get_bus_volume_db(mi)) < 0.01, "set_volumes(1, 0): music full, effects muted")
	audio.set_volumes(1.0, 1.0)


# --- previews ----------------------------------------------------------------------------

func write_previews() -> void:
	DirAccess.make_dir_recursive_absolute(_wav_out)
	var n := 0
	for sn: String in audio.SFX_NAMES:
		var s: AudioStreamWAV = audio._stream(sn)
		if s.save_to_wav(_wav_out.path_join("sfx_%s.wav" % sn)) == OK:
			n += 1
	for t: String in audio.TRACKS:
		var job = _jobs[t]
		var frames := _pull_frames(job, int(PREVIEW_SEC * 22050))
		var pcm := PackedByteArray()
		pcm.resize(frames.size() * 4)
		for i in frames.size():
			pcm.encode_s16(i * 4, int(clampf(frames[i].x, -1.0, 1.0) * 32767.0))
			pcm.encode_s16(i * 4 + 2, int(clampf(frames[i].y, -1.0, 1.0) * 32767.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = 22050
		w.stereo = true
		w.data = pcm
		if w.save_to_wav(_wav_out.path_join("music_%s.wav" % t)) == OK:
			n += 1
	print("  wrote %d preview files to %s" % [n, _wav_out])


# --- helpers ---------------------------------------------------------------------------

func _pcm_stats(pcm: PackedByteArray) -> Dictionary:
	var n := pcm.size() / 2
	var peak := 0.0
	var sum := 0.0
	var sq := 0.0
	for i in n:
		var v := pcm.decode_s16(i * 2) / 32767.0
		peak = maxf(peak, absf(v))
		sum += v
		sq += v * v
	return {"peak": peak, "dc": sum / maxf(n, 1), "rms": sqrt(sq / maxf(n, 1))}


func _vec_stats(f: PackedVector2Array, stride := 1) -> Dictionary:
	var peak := 0.0
	var sum := 0.0
	var sq := 0.0
	for i in range(0, f.size(), stride):
		var v := f[i]
		peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
		sum += v.x + v.y
		sq += v.x * v.x + v.y * v.y
	var n := maxf(ceili(f.size() / float(stride)) * 2, 1)
	return {"peak": peak, "dc": sum / n, "rms": sqrt(sq / n)}


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
