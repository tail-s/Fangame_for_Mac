# Stage files

Each stage is one text file in this folder. `main.gd` lists every `*.txt` here that
has an `; @id` line, sorted by `@order`. Lines starting with `;` are comments; the
rest is the map, one character per 16 px tile, top row first. Rows may differ in
length (missing cells are empty).

## Metadata (`; @key value`)

| key | meaning |
|---|---|
| `id` | unique stage id (also the save-file clear flag) |
| `name` | stage-select title (English, upper case) |
| `desc` | one-line Korean description under the title |
| `order` | sort order on stage select |
| `boss` | `res://` path of the boss script spawned at `K` (see `scripts/enemies/boss_base.gd`) |
| `weapon` | IX special weapon id unlocked when the boss is defeated |
| `hidden_boss` | script spawned at `Y` when `hidden_require` is met |
| `hidden_id` | clear flag for the hidden boss (`eclipse`, `fragment`) |
| `hidden_require` | `bosses:N` (N stage bosses beaten) and/or `+eclipse` |
| `require` | stage locked on stage select until met (same syntax) |
| `final` | `true` for the final stage (its clear plays the ending) |

## Tiles

| char | tile |
|---|---|
| `.` | empty |
| `#` | solid |
| `^` | spikes (instant death) |
| `x` | cracked wall — breaks to Vanguard ARM charge shots, Core Drill, crush-style 3rd slash |
| `f` | fake tile — looks solid, no collision; Vanguard HEAD shows it |
| `o` / `O` | hologram platforms, phase A / B (alternate every 1.2 s) |
| `>` `<` `v` | laser emitters (solid) firing right / left / down |
| `u` | heat vent (solid) firing a flame column up |
| `/` `\` | mirrors that bend laser / flame beams |
| `~` | water — floaty jumps, slow fall |
| `z` | low-gravity zone |
| `\|` | updraft lift — pushes the player up |
| `i` | ice (solid) — slippery ground |
| `e` | electric floor (solid) — charges on a beat and hurts on top |
| `c` | crumbling floor — falls 0.5 s after you stand on it, returns after 4 s |
| `m` / `n` | moving platform run: slides left-right / bobs up-down (48 px, 3.2 s) |
| `P` | player spawn |
| `C` | checkpoint (also opens the armor lab with ↑) |
| `G` | goal (stage clear without a boss) |
| `w` / `t` | walker / turret enemy |
| `1`-`8` | armor capsules (1-4 Vanguard H/B/A/L, 5-8 Aero H/B/A/L) |
| `+` | HP-up tank |
| `B` `D` `K` | boss room: trigger, door (closes behind the player), boss spawn |
| `b` `d` `Y` | hidden boss room: trigger, door, spawn |

The boss room is the empty area around `K` (or `Y`), bounded by solid tiles and the
door column. Make it 22 × 11 tiles inside so the locked camera (24 × 13.5 tiles)
shows all of it, with solid floor under it and a ceiling above.

## Movement reference (for level design)

- Tile 16 px, screen 384 × 216 (24 × 13.5 tiles), stages are 20 rows tall by default.
- Full jump ≈ 63 px (≈ 3.9 tiles) up; running jump ≈ 4 tiles across.
- Dash jump ≈ 10 tiles across; a 7-tile gap needs one (it is the widest required gap).
- Any wall can be climbed by repeated wall kicks.
- Every required path must be clearable with the neutral frame and any character;
  armor parts / partners only open optional routes (GDD v0.2 §4-1).
