extends RefCounted
## Music for Rebirth Protocol — original compositions written for this prototype
## (format: see sequencer.gd). Every track is a form of sections; `|` in the form marks
## the loop point (none = loop from the top). Jingles have "loop": false.
## Each section's chord chart drives the generated bass / arp / drum parts; the lead
## (and optional lead2) are written out in MML, one `|` per bar.

# Drum and hat grooves (one bar, 16th steps).
const D_ROCK := "k...s...k.k.s..."
const D_PUSH := "k..k..s..k.k..s."
const D_SYNC := "k..k..s...k...s."
const D_GALLOP := "k...s..kk.k.s..."
const D_TRAIN := "k.k.s.k..kk.s.k."
const D_URGENT := "k.k.s.k.k.k.s.kk"
const D_EPIC := "k.k.s..kk.k.s..k"
const D_HALF := "k.......s......."
const F_ROLL := "k...s...s.s.ssss"
const F_TOMS := "k.k.s.s.ssssTTtt"
const H_8 := "h.h.h.h.h.h.h.h."
const H_16 := "hhhhhhhhhhhhhhhh"
const H_SKIP := "h.hhh.hhh.hhh.hh"
const H_OPEN := "h.h.h.o.h.h.h.o."

const TRACKS := {
	# Title: heroic E-minor anthem, mid tempo, push-rhythm chord stabs.
	"title": {
		"bpm": 132,
		"form": "I | A B",
		"inst": {
			"lead": {"w": "p25", "v": 0.2, "echo": [36, 0.22, 0.5]},
			"arp": {"w": "p25", "v": 0.055, "center": 62, "sus": 0.55, "dc": 0.25, "chord_t": 0.025},
		},
		"sections": {
			"I": {
				"chords": "Em | C D",
				"lead": "o4 b4 > e4 g4 b4 | > c2 < a4 f+4",
				"bass": "R-------R-------", "arp": "C-------C-------",
				"drums": "k...k...k...k...", "fill": "k...k...s.s.ssss", "crash": false,
			},
			"A": {
				"chords": "Em | C | D | Em | Em | C | Am | B",
				"lead": "o5 e4. b8 b4 a8 g8 | a4. g8 e2 | f+4. a8 d4 f+8 a8 | g8 f+8 e2. |"
						+ " e4. b8 b4 > d8 < b8 | > e4. d8 c4 < b8 a8 | a4 > c4 < b4 a4 | b2 a8 f+8 d+4",
				"bass": "R-R-O-R-R-R-O-R-", "arp": "C-----C-----C---",
				"drums": D_ROCK, "fill": "k...s...s.ssTTtt", "hats": H_8,
			},
			"B": {
				"chords": "C | D | Bm | Em | C | D | Bsus4 | B",
				"lead": "o5 g4. e8 g4 a4 | f+4. d8 f+4 a4 | b4. a8 b4 > d4 < | > e2 d8 c8 < b8 a8 |"
						+ " g4 e4 g4 > c4 < | b4 a4 f+4 a4 | b4. a8 f+4 e4 | d+2. r4",
				"bass": "R-R-O-R-R-R-O-R-", "arp": "C-----C-----C---",
				"drums": D_ROCK, "fill": F_ROLL, "hats": H_8,
			},
		},
	},
	# Stage select: cool, syncopated B minor with a bouncing bass.
	"select": {
		"bpm": 150,
		"form": "A B",
		"inst": {
			"lead": {"w": "p50", "v": 0.14, "echo": [36, 0.2, 0.5]},
			"arp": {"w": "p12", "v": 0.08},
		},
		"sections": {
			"A": {
				"chords": "Bm | G | D | A | Bm | G | Em | F#",
				"lead": "o5 b4 r8 f+8 a8 b8 r8 > d8 | d8 c+8 d8 < b4 r8 g8 a8 | f+4 r8 d8 f+8 a8 r8 > d8 |"
						+ " c+4. < a8 b8 > c+8 e8 c+8 | < b4 r8 f+8 a8 b8 r8 > d8 | e8 d8 e8 < b4 r8 b8 > d8 |"
						+ " e4 g8 f+8 e8 d8 < b8 g8 | a+4 b8 > c+8 < a+2",
				"bass": "R-.RO-.RR-.RO-R-", "arp": "0.2.3.2.0.2.3.2.",
				"drums": D_PUSH, "fill": "k..k..s.s.s.ssss", "hats": H_SKIP,
			},
			"B": {
				"chords": "G | A | F#m | Bm | G | A | Bm | F#",
				"lead": "o5 b2 > d4 c+8 < b8 | a2 e4 a4 | a4. g+8 f+4 a4 | b2. r4 |"
						+ " > d2 e4 d8 < b8 | > c+2 < a4 b8 > c+8 | d4. c+8 < b4 a4 | a+2. r4",
				"bass": "R-.RO-.RR-.RO-R-", "arp": "0.2.3.2.0.2.3.2.",
				"drums": D_PUSH, "fill": "k..k..s.s.s.ssss", "hats": H_SKIP,
			},
		},
	},
	# Story scenes: slow, pensive D minor with a soft PWM lead.
	"story": {
		"bpm": 96,
		"form": "A B",
		"inst": {
			"lead": {"w": "pwm", "v": 0.16, "a": 0.02, "dc": 0.4, "sus": 0.7, "r": 0.15,
					"vib": [4.8, 0.22, 0.3], "echo": [48, 0.28, 0.55]},
			"arp": {"w": "p12", "v": 0.06, "center": 64, "r": 0.08},
			"bass": {"v": 0.36, "gate": 0.95},
			"drums": {"kick": 0.32, "hat": 0.05},
		},
		"sections": {
			"A": {
				"chords": "Dm | Bb | F | C | Dm | Bb | Gm | A",
				"lead": "o5 a2. f8 g8 | a4 g4 f2 | c2. d8 e8 | f4 e4 c2 |"
						+ " a2. > c8 d8 | d4 c4 < b-4 a4 | g4. a8 b-4 > d4 | c+2. r4",
				"bass": "R-------F-------", "arp": "0.1.2.1.3.1.2.1.",
				"drums": "k.........k.....", "hats": "..h...h...h...h.", "crash": false,
			},
			"B": {
				"chords": "Bb | C | Am | Dm | Bb | C | Asus4 | A",
				"lead": "o5 b-2 > d4 c4 | < g2. e4 | a4. g8 e2 | f2 d2 |"
						+ " b-4. a8 b-4 > d4 | e2 d4 c4 | d2. c+4 | c+2 < a2",
				"bass": "R-------F-------", "arp": "0.1.2.1.3.1.2.1.",
				"drums": "k.........k.....", "hats": "..h...h...h...h.", "crash": false,
			},
		},
	},
	# Training facility: bright C major, offbeat chord stabs, tutorial bounce.
	"training": {
		"bpm": 156,
		"form": "I | A B",
		"inst": {
			"lead": {"w": "p25", "v": 0.2, "echo": [36, 0.15, 0.5]},
			"arp": {"w": "p50", "v": 0.045, "center": 64, "sus": 0.4, "dc": 0.06, "chord_t": 0.02},
		},
		"sections": {
			"I": {
				"chords": "C | G",
				"lead": "o5 c8 c8 r8 c8 r8 c8 d8 e8 | g4 g4 g8 g8 a8 b8",
				"bass": "R.R.R.R.R.R.R.R.",
				"drums": "k...k...k...k...", "fill": "k.k.s.s.ssssssss", "crash": false,
			},
			"A": {
				"chords": "C | G | Am | F | C | G | F | G",
				"lead": "o6 c4 < g8 e8 g4 > c8 d8 | d4 < b8 g8 b4 > d8 e8 | e8 d8 c8 < a8 r8 a8 b8 > c8 | d4 c4 < a2 |"
						+ " > c4 < g8 e8 g4 > c8 d8 | d4 < b8 g8 b4 > d8 f8 | e4 d8 c8 d4 c8 < a8 | b2 > d4 r4",
				"bass": "R.O.R.O.R.O.R.O.", "arp": "..C-..C-..C-..C-",
				"drums": D_ROCK, "fill": F_ROLL, "hats": H_8,
			},
			"B": {
				"chords": "Am | F | C | G | Am | F | Dm | G",
				"lead": "o5 e4. a8 > c4 e4 | f4. e8 d4 c4 | e4. d8 c4 < g4 | b2 g4 b4 |"
						+ " e4. a8 > c4 e4 | f4. a8 g4 f4 | f4 e4 d4 c4 | d2 < b4 g4",
				"bass": "R.O.R.O.R.O.R.O.", "arp": "..C-..C-..C-..C-",
				"drums": D_ROCK, "fill": F_ROLL, "hats": H_8,
			},
		},
	},
	# Prism Gecko (data archive): glassy A minor, rippling 16th arpeggios, echoing lead.
	"prism_gecko": {
		"bpm": 160,
		"form": "A B C",
		"inst": {
			"lead": {"w": "p12", "v": 0.22, "vib": [6.0, 0.15, 0.2], "echo": [36, 0.3, 0.55]},
			"arp": {"w": "p25", "v": 0.05, "center": 69, "dc": 0.06, "sus": 0.25, "r": 0.04},
		},
		"sections": {
			"A": {
				"chords": "Am7 | Fmaj7 | Cmaj7 | G | Am7 | Fmaj7 | Dm7 | E",
				"lead": "o6 e4 < b8 > c8 r8 < a8 r8 g8 | a4 e8 f8 r8 c8 e8 f8 | g4 b8 > c8 r8 e8 d8 c8 | < b4. a8 g4 b4 |"
						+ " > e4 < b8 > c8 r8 < a8 r8 g8 | a4 > c8 e8 r8 f8 e8 c8 | d4. c8 < a4 f4 | g+2. r4",
				"bass": "R..RR..RR..RO.R.", "arp": "0123432101234321",
				"drums": D_SYNC, "fill": "k..k..s.s.ssTTtt", "hats": H_SKIP,
			},
			"B": {
				"chords": "Fmaj7 | G | Em7 | Am7 | Fmaj7 | G | Esus4 | E",
				"lead": "o6 c2 < a4 > c4 | d2 < b4 > d4 | e4. d8 < b4 g4 | a2 r8 a8 b8 > c8 |"
						+ " f2 e4 c4 | d2 < b4 g4 | a2 b4 a4 | g+2 b4 > d4",
				"bass": "R..RR..RR..RO.R.", "arp": "0123432101234321",
				"drums": D_SYNC, "fill": "k..k..s.s.ssTTtt", "hats": H_SKIP,
			},
			"C": {
				"chords": "Dm7 | Em7 | Fmaj7 | G | Dm7 | Em7 | Fmaj7 | E",
				"lead": "o5 f2. a4 | g2. b4 | a2 > c4 e4 | d2. < b4 | a2. > d4 | < b2. > e4 | c2 < a4 > c4 | < b2 g+2",
				"bass": "R-------R---R-R-", "arp": "0123432101234321",
				"drums": D_HALF, "fill": "k..k..s.s.ssTTtt", "hats": H_8,
			},
		},
	},
	# Gravity Albatross (orbital shipyard): spacious D lydian, half-time drums, long echoes.
	"gravity_albatross": {
		"bpm": 140,
		"form": "A B C",
		"inst": {
			"lead": {"w": "saw", "v": 0.13, "a": 0.01, "dc": 0.5, "sus": 0.7, "r": 0.2,
					"vib": [5.0, 0.25, 0.25], "echo": [48, 0.35, 0.6]},
			"arp": {"w": "p12", "v": 0.065, "center": 66, "r": 0.1},
		},
		"sections": {
			"A": {
				"chords": "Dmaj7 | E/D | Dmaj7 | E/D | Bm | G | Em7 | A",
				"lead": "o5 a2. f+4 | g+2. b4 | > c+2 < a4 f+4 | g+1 |"
						+ " f+4. b8 > d2 | d4. c+8 < b2 | g4. a8 b4 > d4 | c+2. r4",
				"bass": "R-------O---F---", "arp": "0.2.4.2.3.2.4.2.",
				"drums": D_HALF, "fill": "k.......s.sTsTtt", "hats": H_8,
			},
			"B": {
				"chords": "Gmaj7 | A | F#m7 | Bm7 | Gmaj7 | A | Em7 | A",
				"lead": "o6 d2 f+4 e4 | e2. c+4 | c+2 < a4 b4 | f+2 b4 > c+4 |"
						+ " d2 e4 f+4 | e2 c+4 < a4 | b2. > d4 | c+2 e2",
				"bass": "R-------O---F---", "arp": "0.2.4.2.3.2.4.2.",
				"drums": D_HALF, "fill": "k.......s.sTsTtt", "hats": H_8,
			},
			"C": {
				"chords": "Bm7 | A | Gmaj7 | F#m7 | Em7 | F#m7 | Gmaj7 | A",
				"lead": "o5 f+1 | e2. c+4 | d2 f+4 a4 | c+1 | e2 f+4 g4 | a2 c+4 e4 | d2. f+4 | e2 c+2",
				"bass": "R-------R-------", "arp": "0.2.4.2.3.2.4.2.",
				"drums": D_HALF, "fill": "k.......s.sTsTtt", "hats": "h...h...h...h...",
			},
		},
	},
	# Solar Fennec (desert drive): E phrygian-dominant runs over a galloping bass.
	"solar_fennec": {
		"bpm": 172,
		"form": "A B C",
		"inst": {
			"lead": {"w": "p25", "v": 0.2, "vib": [6.5, 0.25, 0.18], "echo": [24, 0.15, 0.5]},
			"bass": {"gate": 0.7},
		},
		"sections": {
			"A": {
				"chords": "E | F | E | F | Dm | E | F | E",
				"lead": "o5 e8 f8 g+8 a8 b4 a8 g+8 | a8 g+8 f8 e8 f4 c4 | e8 f8 g+8 b8 > d4 c8 < b8 | > c4. < a8 f4 r4 |"
						+ " d8 e8 f8 a8 > d4 c8 < a8 | b4. g+8 e4 f8 g+8 | a8 b8 > c8 d8 e8 d8 c8 < a8 | b4 a8 g+8 f8 e8 f8 g+8",
				"bass": "R.RRR.RRR.RRR.RR", "arp": "0.1.2.0.1.2.0.1.",
				"drums": D_GALLOP, "fill": F_TOMS, "hats": H_OPEN,
			},
			"B": {
				"chords": "Am | G | F | E | Am | G | F | E",
				"lead": "o5 a4. > c8 e4 d8 c8 | d4. < b8 g4 a8 b8 | > c4. < a8 f4 g8 a8 | g+4. b8 e2 |"
						+ " a4. > c8 e4 f8 e8 | d4. e8 d4 c8 < b8 | > c8 d8 c8 < a8 > c4 d8 e8 | e2 < g+4 b4",
				"bass": "R.RRR.RRR.RRR.RR", "arp": "0.1.2.0.1.2.0.1.",
				"drums": D_GALLOP, "fill": F_TOMS, "hats": H_OPEN,
			},
			"C": {
				"chords": "Dm | E | Dm | E | F | G | F | E",
				"lead": "o5 d4. f8 a4 g8 f8 | e4. g+8 b2 | d4. f8 a4 > d4 | < b2. r4 |"
						+ " > c4. < a8 f4 a4 | b4. g8 d4 g4 | a4. g8 f4 e4 | g+8 a8 b8 > c8 d8 c8 < b8 g+8",
				"bass": "R.RRR.RRR.RRR.RR", "arp": "0.1.2.0.1.2.0.1.",
				"drums": "k...t..kt.k.s.T.", "fill": F_TOMS, "hats": H_8,
			},
		},
	},
	# Cryo Narwhal (deep sea): slow, cold G minor; PWM lead, sine droplets, sparse drums.
	"cryo_narwhal": {
		"bpm": 112,
		"form": "A B C",
		"inst": {
			"lead": {"w": "pwm", "v": 0.17, "a": 0.03, "dc": 0.5, "sus": 0.7, "r": 0.25,
					"vib": [4.2, 0.25, 0.35], "echo": [48, 0.35, 0.6]},
			"arp": {"w": "sine", "v": 0.09, "center": 76, "dc": 0.25, "sus": 0.0, "r": 0.1},
			"bass": {"v": 0.4, "gate": 0.95},
			"drums": {"kick": 0.4, "snare": 0.18, "hat": 0.07, "crash": 0.1},
		},
		"sections": {
			"A": {
				"chords": "Gm | Ebmaj7 | Bb | F | Gm | Ebmaj7 | Cm7 | D",
				"lead": "o5 d2 b-4 a4 | g2. f4 | f2 d4 f4 | c2. r4 |"
						+ " d2 b-4 > d4 | d4. c8 < b-4 g4 | g2 e-4 g4 | f+1",
				"bass": "R-------R---F---", "arp": "4.2.3.1.4.2.3.1.",
				"drums": "k.........k.s...", "hats": "h...h...h...h.h.",
			},
			"B": {
				"chords": "Ebmaj7 | F | Dm | Gm | Ebmaj7 | F | Cm | Dsus4 D",
				"lead": "o5 b-2 g4 b-4 | > c2 < a4 f4 | a2 f4 d4 | g2. r4 |"
						+ " b-2 > d4 e-4 | f2. e-4 | e-2 d4 c4 | < g2 f+2",
				"bass": "R-------R---F---", "arp": "4.2.3.1.4.2.3.1.",
				"drums": "k.........k.s...", "hats": "h...h...h...h.h.",
			},
			"C": {
				"chords": "Cm | Gm | Ebmaj7 | D | Cm | Gm | Ab | D",
				"lead": "o5 g2. e-4 | d2 g4 b-4 | b-2. g4 | a2. f+4 | g2 > c4 e-4 | d2. < b-4 | > c2 e-4 c4 | < a2 f+2",
				"bass": "R-------R-------", "arp": "4.2.3.1.4.2.3.1.",
				"drums": "k...............", "hats": "h.......h.......",
			},
		},
	},
	# Terra Pangolin (underground rail): driving D minor, chugging 16th bass like wheels on track.
	"terra_pangolin": {
		"bpm": 164,
		"form": "A B C",
		"inst": {
			"lead": {"w": "p50", "v": 0.14, "echo": [36, 0.15, 0.5]},
			"arp": {"w": "p25", "v": 0.045, "center": 62, "dc": 0.05, "sus": 0.3, "chord_t": 0.018},
			"bass": {"v": 0.44, "gate": 0.6},
			"drums": {"hat": 0.06},
		},
		"sections": {
			"A": {
				"chords": "Dm | Dm | Bb | C | Dm | Dm | Gm | A",
				"lead": "o5 d4 r8 d8 f8 g8 a4 | c8 d8 r8 a8 g8 f8 e8 c8 | d4 r8 d8 f8 g8 b-4 | a8 g8 r8 e8 c4 e8 g8 |"
						+ " a4 r8 a8 > c8 d8 e8 f8 | e8 d8 c8 < a8 r8 a8 g8 e8 | g4. a8 b-4 > d4 | c+4 < a8 e8 c+8 e8 a8 > c+8",
				"bass": "RRORRRORRRORRROR", "arp": "C..C..C.C..C..C.",
				"drums": D_TRAIN, "fill": F_TOMS, "hats": H_16,
			},
			"B": {
				"chords": "Bb | C | Am | Dm | Bb | C | Gm | A",
				"lead": "o6 d2 r8 d8 c8 d8 | e2 r8 e8 d8 e8 | c4 < a4 e4 a4 | f4. e8 d2 |"
						+ " > d2 r8 d8 e8 f8 | g2 r8 g8 f8 e8 | f4. e8 d4 < b-4 | a2 > c+4 e4",
				"bass": "RRORRRORRRORRROR", "arp": "C..C..C.C..C..C.",
				"drums": D_TRAIN, "fill": F_TOMS, "hats": H_16,
			},
			"C": {
				"chords": "Gm | Gm | Dm | Dm | Bb | C | A | A",
				"lead": "o5 g4. a8 b-4 > d4 | d4. c8 < b-4 g4 | f4. g8 a4 > d4 | c4 < a4 f4 d4 |"
						+ " f4. g8 b-4 > d4 | e4. d8 c4 e4 | c+4. d8 e4 g4 | e4 d4 c+4 < a4",
				"bass": "R.R.R.R.R.R.R.R.", "arp": "C-------C-------",
				"drums": "k.......s.....k.", "fill": F_TOMS, "hats": H_8,
			},
		},
	},
	# Pulse Cicada (high voltage): fast C minor, pedal-tone riff, buzzing pulse bass.
	"pulse_cicada": {
		"bpm": 184,
		"form": "A B C",
		"inst": {
			"lead": {"w": "p25", "v": 0.22, "vib": [7.0, 0.2, 0.15], "echo": [24, 0.15, 0.55]},
			"arp": {"w": "p12", "v": 0.07, "center": 72, "dc": 0.05, "sus": 0.3},
			"bass": {"w": "p25", "v": 0.21, "gate": 0.75},
		},
		"sections": {
			"A": {
				"chords": "Cm | Ab | Bb | G | Cm | Ab | Fm | G",
				"lead": "o5 g8 g8 > c8 < g8 > d8 < g8 > e-8 d8 | c8 < a-8 > c8 e-8 f4 e-4 | d8 < b-8 > d8 f8 e-4 d4 | < b4. > d8 < b4 g4 |"
						+ " g8 g8 > c8 < g8 > d8 < g8 > e-8 f8 | g8 f8 e-8 c8 r8 c8 e-8 f8 | a-4. g8 f4 e-4 | d2 < b4 g4",
				"bass": "R-O-R-O-R-O-R-O-", "arp": "0123012301230123",
				"drums": "k...s.k.k...s...", "fill": "s.s.s.s.ssssssss", "hats": H_SKIP,
			},
			"B": {
				"chords": "Ab | Bb | Gm | Cm | Ab | Bb | Fm | G",
				"lead": "o6 c4 e-4 a-4 g8 f8 | f4 d8 < b-8 > d4 f4 | g4 d8 < b-8 > d4 g4 | e-4. d8 c2 |"
						+ " c4 e-4 a-4 g8 a-8 | b-4. a-8 g4 f4 | a-4 g4 f4 e-4 | d4 < b8 g8 b8 > d8 f8 g8",
				"bass": "R-O-R-O-R-O-R-O-", "arp": "0123012301230123",
				"drums": "k...s.k.k...s...", "fill": "s.s.s.s.ssssssss", "hats": H_SKIP,
			},
			"C": {
				"chords": "Fm | G | Cm | Ab | Fm | G | Ab | G",
				"lead": "o5 a-2 > c4 f4 | d2 < b4 g4 | > c2 e-4 g4 | a-2 g4 e-4 | < f2 a-4 > c4 | < b2 > d4 f4 | e-2 c4 e-4 | d2 < b4 > d4",
				"bass": "R-------O-------", "arp": "0123012301230123",
				"drums": D_HALF, "fill": "s.s.s.s.ssssssss", "hats": H_16,
			},
		},
	},
	# Eden Core (final stage): tense B minor with chromatic neighbour tones and diminished colour.
	"final_eden_core": {
		"bpm": 156,
		"form": "A B C",
		"inst": {
			"lead": {"w": "saw", "v": 0.15, "vib": [6.0, 0.2, 0.2], "echo": [36, 0.2, 0.5]},
			"arp": {"w": "p12", "v": 0.06, "center": 71},
			"drums": {"hat": 0.06},
		},
		"sections": {
			"A": {
				"chords": "Bm | C | Bm | C | G | A#dim | Bm | F#",
				"lead": "o5 b4 a+8 b8 > d4 c+8 d8 | e4 d+8 e8 g4 f+8 e8 | d4 c+8 d8 f+4 e8 d8 | c4 < b8 > c8 e4. < b8 |"
						+ " b4. > d8 g4 f+8 e8 | e4 c+8 < a+8 g4 a+4 | b4. > c+8 d4 e4 | f+2 c+4 < a+4",
				"bass": "R.RR.RR.R.RR.RO.", "arp": "0213021302130213",
				"drums": D_PUSH, "fill": "k..k..s.ssssTTtt", "hats": H_16,
			},
			"B": {
				"chords": "Em | Bm | C | F# | Em | Bm | C | F#7",
				"lead": "o5 g2 b4 > e4 | f+2 d4 < b4 | > g2 e4 c4 | c+2 < a+4 f+4 |"
						+ " > e4 d+8 e8 g4 f+8 e8 | d4 c+8 d8 f+4 e8 d8 | e4. f+8 g4 a4 | a+4 f+4 e4 c+4",
				"bass": "R.RR.RR.R.RR.RO.", "arp": "0213021302130213",
				"drums": D_PUSH, "fill": "k..k..s.ssssTTtt", "hats": H_16,
			},
			"C": {
				"chords": "G | A | Bm | Bm | G | A | F# | F#7",
				"lead": "o5 b2 > d4 g4 | c+2 e4 a4 | f+2. e8 d8 | c+4 d4 e4 f+4 | g2 f+4 e4 | e2 c+4 < a4 | a+2 > c+4 e4 | f+2 e4 c+4",
				"bass": "R.......R.......", "arp": "0213021302130213",
				"drums": D_HALF, "fill": F_TOMS, "hats": H_8,
			},
		},
	},
	# Boss battle: urgent A minor riff with a blue-note bite.
	"boss": {
		"bpm": 176,
		"form": "A B",
		"inst": {
			"lead": {"w": "p25", "v": 0.2, "vib": [6.5, 0.2, 0.15]},
			"bass": {"gate": 0.7},
		},
		"sections": {
			"A": {
				"chords": "Am | Am | F | E | Am | Am | Dm | E",
				"lead": "o5 a8 a8 > c8 < a8 > e-8 d8 c8 < b8 | a8 a8 > c8 < a8 > e8 d8 c8 d8 | c8 c8 f8 c8 a8 g8 f8 e8 | < b4 a+8 b8 > e4 d4 |"
						+ " < a8 a8 > c8 < a8 > e-8 d8 c8 < b8 | a8 a8 > c8 < a8 > e8 f8 e8 d8 | d8 e8 f8 a8 g8 f8 e8 d8 | e2 < b4 g+4",
				"bass": "R.RRO.RRR.RRO.RR", "arp": "0120120120120120",
				"drums": D_URGENT, "fill": "s.s.s.s.ssssTTtt", "hats": H_8,
			},
			"B": {
				"chords": "F | G | Em | Am | F | G | E | E7",
				"lead": "o6 c4. < a8 > c4 f4 | d4. < b8 > d4 g4 | e4. d8 < b4 g4 | a4. b8 > c4 e4 |"
						+ " f4. e8 c4 < a4 | > g4. f8 d4 < b4 | g+4 b4 > e4 g+4 | f4 e4 d4 < b4",
				"bass": "R.RRO.RRR.RRO.RR", "arp": "0120120120120120",
				"drums": D_URGENT, "fill": "s.s.s.s.ssssTTtt", "hats": H_8,
			},
		},
	},
	# Hidden boss: ominous C# minor, phrygian half-steps and a tritone turn, thin wavering lead.
	"hidden_boss": {
		"bpm": 148,
		"form": "A B",
		"inst": {
			"lead": {"w": "p12", "v": 0.23, "vib": [4.5, 0.35, 0.2], "echo": [48, 0.3, 0.6]},
			"arp": {"w": "p12", "v": 0.07, "center": 61},
			"bass": {"v": 0.45, "gate": 0.9},
		},
		"sections": {
			"A": {
				"chords": "C#m | D | C#m | G | C#m | D | Bm | G#",
				"lead": "o5 c+4. d8 c+4 g+4 | f+4. e8 d4 a4 | g+4. a8 g+4 e4 | g2 b4 > d4 |"
						+ " < c+4. d8 c+4 > c+4 | d4. c+8 < a4 f+4 | b4. a8 f+4 d4 | g+2 d+4 > c4",
				"bass": "R--R--R-R--R--O-", "arp": "0.0.3.0.1.0.3.0.",
				"drums": "k.....k.s.....k.", "fill": "k.....k.s.ssTTtt", "hats": "h.h.h.h.h.h.h.o.",
			},
			"B": {
				"chords": "A | G#m | F#m | C#m | A | D | G#sus4 | G#",
				"lead": "o6 c+2 e4 c+4 | < b2 > d+4 < b4 | a2 > c+4 < a4 | g+2. r4 |"
						+ " > e2 c+4 e4 | f+2 d4 f+4 | c+2 d+4 c+4 | c2 < g+2",
				"bass": "R--R--R-R--R--O-", "arp": "0.0.3.0.1.0.3.0.",
				"drums": "k.....k.s.....k.", "fill": "k.....k.s.ssTTtt", "hats": "h.h.h.h.h.h.h.o.",
			},
		},
	},
	# Final boss: epic D minor in three sections, climbing to a high Bb climax.
	"final_boss": {
		"bpm": 168,
		"form": "A B C",
		"inst": {
			"lead": {"w": "saw", "v": 0.16, "vib": [6.0, 0.22, 0.18], "echo": [36, 0.2, 0.5]},
			"arp": {"w": "p25", "v": 0.045, "center": 69, "dc": 0.06, "sus": 0.3},
		},
		"sections": {
			"A": {
				"chords": "Dm | Bb | C | Dm | Dm | Bb | Gm | A",
				"lead": "o5 d8 f8 a8 > d4 c8 < a8 f8 | g8 b-8 > d8 f4 e-8 d8 < b-8 | g8 > c8 e8 g4 f8 e8 c8 | d2. r8 < a8 |"
						+ " > d4. e8 f4 a4 | g4. f8 d4 < b-4 | b-4 > c4 d4 g4 | c+2 e2",
				"bass": "R-R-O-R-R-R-O-RO", "arp": "0123012301230123",
				"drums": D_EPIC, "fill": "k.k.s.s.ssTTttTT", "hats": H_8,
			},
			"B": {
				"chords": "Gm | A | Dm | F | Gm | A | Bb | A",
				"lead": "o6 d2 < b-4 g4 | > c+2 < a4 e4 | f4. g8 a4 > d4 | c2. r4 |"
						+ " d4. e-8 d4 c4 | c+4. d8 e4 a4 | f4. e8 d4 f4 | e2 c+4 < a4",
				"bass": "R-R-O-R-R-R-O-RO", "arp": "0123012301230123",
				"drums": D_EPIC, "fill": "k.k.s.s.ssTTttTT", "hats": H_8,
			},
			"C": {
				"chords": "Bb | C | Am | Dm | Bb | C | A | A7",
				"lead": "o6 f2 d4 f4 | g2 e4 g4 | a2 e4 c4 | d4. e8 f4 a4 |"
						+ " b-2 a4 f4 | g2 e4 c4 | e4. d8 c+4 < a4 | a4 > c+4 e4 g4",
				"bass": "R-R-O-R-R-R-O-RO", "arp": "0123012301230123",
				"drums": D_EPIC, "fill": F_TOMS, "hats": H_16,
			},
		},
	},
	# Ending: warm G major, walking bass, gentle flowing arpeggio.
	"ending": {
		"bpm": 108,
		"form": "A B",
		"inst": {
			"lead": {"w": "p50", "v": 0.13, "a": 0.01, "dc": 0.4, "sus": 0.7, "r": 0.15,
					"vib": [5.0, 0.2, 0.3], "echo": [36, 0.3, 0.55]},
			"arp": {"w": "p12", "v": 0.065, "center": 67},
			"drums": {"kick": 0.35, "snare": 0.2, "hat": 0.06},
		},
		"sections": {
			"A": {
				"chords": "G | D/F# | Em | C | G | D | C | D",
				"lead": "o5 b2 a4 g4 | a2 f+4 d4 | g4. a8 b4 > e4 | d2 c4 < b4 |"
						+ " b2 > d4 g4 | f+2 e4 d4 | e4. d8 c4 < b4 | a2. r4",
				"bass": "R---F---O---F---", "arp": "0.1.2.3.4.3.2.1.",
				"drums": D_HALF, "hats": H_8, "crash": false,
			},
			"B": {
				"chords": "Em | C | G | D | Em | C | Am7 | D",
				"lead": "o5 g2 b4 > e4 | e2 d4 c4 | d4. c8 < b4 g4 | a2 f+4 a4 |"
						+ " b2 > e4 g4 | g2 f+4 e4 | e4. d8 c4 < a4 | a2. f+4",
				"bass": "R---F---O---F---", "arp": "0.1.2.3.4.3.2.1.",
				"drums": D_HALF, "hats": H_8, "crash": false,
			},
		},
	},
	# Jingle: stage clear fanfare (~3.5 s, plays once).
	"stage_clear": {
		"bpm": 168,
		"loop": false,
		"tail": 0.6,
		"form": "A",
		"inst": {
			"lead": {"w": "p25", "v": 0.22, "r": 0.4, "echo": [24, 0.2, 0.5]},
			"arp": {"w": "p50", "v": 0.05, "center": 64, "sus": 0.6, "dc": 0.3},
		},
		"sections": {
			"A": {
				"chords": "C F | G C",
				"lead": "o5 g12 g12 g12 > c4 f8 e8 f8 a8 | d8 e8 f8 g8 > c2",
				"bass": "R---R---R---R---", "arp": "C---C---C---C---",
				"drums": "k...s...k...s...k.k.s.s.c.......", "crash": false,
			},
		},
	},
	# Jingle: boss warning sting (~2.3 s, plays once).
	"boss_intro": {
		"bpm": 132,
		"loop": false,
		"tail": 0.5,
		"form": "A",
		"inst": {
			"lead": {"w": "saw", "v": 0.18, "vib": [7.0, 0.4, 0.2], "r": 0.3},
		},
		"sections": {
			"A": {
				"chords": "Am Bb",
				"lead": "o5 a16 a16 a16 a16 b-16 b-16 b-16 b-16 > e2",
				"bass": "RRRRRRRRR-------",
				"drums": "k.k.k.k.c.......", "crash": false,
			},
		},
	},
}
