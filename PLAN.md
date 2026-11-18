# create_hypertube — slice 1 implementation plan (tube + entrance + travel)

**Goal:** a straight run of hypertubes between two entrances carries the player
along it at the jar's minimum powered speed (0.5 blocks/tick), in game, from one
installed `.hnmod`.

**Class + tier:** `content` / `deep` (ledger row). Approach from
`horizon/docs/modpacks.md`: `deep` means a player-travel rule driven by server
tick hooks plus carried content — not a plain content block, and not a Create
machine (the parent cannot be linked; `ARCHITECTURE.md` §3).

**Pin:** Horizon `1d63e0a5a37a7a708eb0b32b49bf0dfeb28ed8a9` (`game.rs`
`64813cf4…6cef80f`), mixins `5a64af938ec86b00d53d16a408aabc0038fb3e57`,
schema 6. Only stamped hooks are named; `native_teleport_player` is called as a
pending-fragment *helper* (as `elevatorid` slice 2 does), never as a hook.

**Numbers, all from the jar's upstream source (see `FINDINGS.md`):**
`NEEDED_SPEED = 16`, `speed = 0.4333 * min(1, rpm/16) + rpm/240` → **0.5
blocks/tick** at 16 rpm; minimum 3 path points; exit 1.5 blocks past the far
entrance's centre; re-entry guard 2,000 ms (40 ticks).

## Files

| File | Responsibility |
|---|---|
| `Cargo.toml`, `rust-toolchain.toml`, `Cargo.lock` | standalone crate for the pure runtime |
| `compatibility.json` | pin + `game.rs` hash |
| `mixins/create_hypertube/runtime.rs` | pure rules: the run walk, the ride, the speed curve, entry predicate |
| `mixins/create_hypertube/support.rs` | glue: ride table, block reads through the tick's read scope, teleport |
| `mixins/create_hypertube/server_tick.rs` | `server_tick` HEAD helper |
| `mixins/create_hypertube/place_block.rs` | `place_block` HEAD helper: entrance facing, tube axis states |
| `mixins/create_hypertube/embedded_content.rs` | `content_root` HEAD helper (AE2 pattern) |
| `mixins/create_hypertube/data/create_hypertube-content.hmod` | the built content, embedded |
| `content/` | `horizon-mod.toml`, carried assets, block/item/loot/recipe/tag declarations |
| `tools/assemble_content.py` | jar → `content/`, rerunnable |
| `tools/package.py` | `.hnmod` builder (deterministic) |
| `tools/e2e.sh` | in-game scenario, `EXIT:` line, `EMBEDDED`/`CONTROL`/`SELFTEST` legs |

## Task 1 — the pure runtime (TDD)

Interface (module `crate::game::create_hypertube`):

```rust
pub const NEEDED_SPEED: f32 = 16.0;
pub const MIN_POINTS: usize = 3;
pub fn travel_speed(rpm: f32) -> f64;            // 0.4333*min(1,rpm/16)+rpm/240
pub const BASE_SPEED: f64 = 0.5;                  // travel_speed(NEEDED_SPEED)

pub enum Dir { North, East, South, West, Up, Down }
impl Dir { pub fn from_name(&str) -> Option<Dir>; pub fn step(self) -> [i32; 3]; pub fn opposite(self) -> Dir; }

pub enum Cell { Tube, Entrance(Dir), Other }      // what the world says at a position
pub trait World { fn cell(&mut self, pos: [i32; 3]) -> Cell; }

pub struct Run { pub points: Vec<[f64; 3]>, pub exit: [f64; 3], pub from_entrance: [i32; 3] }
pub fn plan(entrance: [i32; 3], facing: Dir, world: &mut impl World) -> Option<Run>;

pub struct Ride { /* points, arc length, travelled, speed */ }
impl Ride {
    pub fn start(from: [f64; 3], run: &Run, speed: f64) -> Ride;
    pub fn position(&self) -> [f64; 3];
    pub fn advance(&mut self) -> bool;            // false once finished
    pub fn finished(&self) -> bool;
}
```

Rules pinned by tests:

1. `travel_speed(16.0) == 0.5` (jar), `travel_speed(32.0)` ≈ 0.5667,
   `travel_speed(256.0) == 1.5`, `travel_speed(8.0) == 0.25` (the curve, so a
   later accelerator slice can feed it).
2. `plan` on `entrance + 4 tubes` gives entrance centre + 4 tube centres, and the
   exit at the last tube's centre (no far entrance).
3. `plan` on `entrance + 2 tubes + far entrance (facing back)` gives 4 points and
   an exit at `far centre + 1.5 * travelDir`.
4. `plan` on `entrance + 1 tube` → `None` (upstream's 3-point minimum).
5. `plan` stops at a solid wall: `entrance + tube + tube + Other + tube` → 3
   points, exit at the second tube.
6. `plan` follows one axis only: a run that turns ends at the turn.
7. `Ride` at 0.5/tick: after 1 tick 0.5 along, after 20 ticks 10; position
   interpolates inside a segment and lands exactly on the last point.
8. `Ride` never overshoots: a speed larger than the whole path finishes on it.
9. `advance` returns `false` immediately once finished (idempotent finish).
10. `Ride::start` drops path points nearer than `sqrt(0.8)` to the previous one
    (upstream's cleanup), and a start position on the first point adds no
    segment.
11. `Dir::from_name` round-trips all six names, and `None` for anything else.
12. `entry_cell(entrance, facing)` is the cell behind the mouth
    (`entrance - facing`), and `starts_ride(player_cell, entrance, facing)`
    is true exactly there.

## Task 2 — content (`tools/assemble_content.py`)

* `create_hypertube:hypertube` — template `minecraft:stone`, `occludes:false`,
  `collision_shapes: {default: []}` (walk through; the jar is `noOcclusion` and
  not suffocating), `shapes` = the tube outline along each axis (from
  `HypertubeBlock.SHAPE_*`, 0..16 scaled), state properties `north_south`,
  `east_west`, `up_down`, `connected`.
* `create_hypertube:hypertube_entrance` — same template/properties, state
  properties `facing` (6 values) and `open`, shapes = the entrance's own box
  (`Block.box` 0..16 × 0..16 × 0..23 for north, rotated by the model file).
* items, both models, both blockstates, textures, loot tables (26.3 singular
  `condition`), recipes adapted to vanilla (Create's ingredients are not
  linkable): brass sheet → copper ingot, `c:glass_panes` → `minecraft:glass_pane`,
  smart chute → hopper, cogwheel → iron ingot, funnel → a hypertube.
* lang: the jar's two block names + `itemGroup.create_hypertube`; creative tab.

## Task 3 — glue

* `place_block`: for a placed entrance, set `facing` from the acting player
  (`yaw` → horizontal, `pitch` beyond ±45° → up/down) and `open=false`; for a
  placed tube, set the axis flags and `connected` from its neighbours; then
  refresh the six tube neighbours' axis flags (upstream's `neighborChanged`).
* `server_tick` at `ServerTickEnd{world_running}`: for every server player,
  advance a ride (teleport with `native_teleport_player`), else look for an
  entrance whose entry cell holds the player (six neighbours, `facing` read from
  the block state) and start a ride when `plan` yields one and the 40-tick
  re-entry guard allows it.
* `embedded_content`: write `data/create_hypertube-content.hmod` to
  `.horizon-cache/` and append it to the dev list (AE2 pattern).

## Task 4 — ladder

`cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test`, then the
staged `stage → check → test → build` in one slot, `tools/package.py`,
`cargo horizon-mod check --kind native-mod`.

## Task 5 — e2e (fail-capable)

Arena: The End void, a stone floor, hypertubes along +x between two entrances.

* **A** a run of 4 tubes between two facing entrances carries the player from
  x0 to the far exit, ~0.5 blocks/tick (measured against the ticks waited);
* **B** control: an entrance with no tube in front moves nobody;
* **C** control: a lone tube with no entrance moves nobody;
* **D** a stone wall in the middle of the run stops the player before it
  (not at the far entrance);
* **EMBEDDED=1** the same scenario with **no `--dev-mod`**, plus a
  `.horizon-cache`-unusable control where the ids must be unknown;
* **SELFTEST=1** asserts a wrong arrival and must exit non-zero.
