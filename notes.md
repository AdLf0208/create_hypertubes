# Create: Hypertube — port notes (slices 1–2: tube + entrance + travel, then every living traveller)

> **`## Migration to the SDK format`** and **`## Migration verification (SDK 0b14f8a)`** at the
> end of this file are the current state. Everything above them is the history of the retired
> `.hnmod` bundle (pin `1d63e0a5`, `mixins/`, the embedded content `.hmod`, the staging ladder) and
> is kept as the record, not as instructions — none of `mixins/<id>/`, `compatibility.json`,
> `content/`, `rust-toolchain.toml`, `tools/horizon.py`, `tools/package.py` or the `.hnmod` exists
> any more.

Ported from **Create: Hypertube 0.6.0** (`PedroRok/CreateHypertubes`, author
"Rok"), the ATM10 jar `create_hypertube-0.6.0-NEOFORGE.jar`, for Minecraft
Java 26.3 on Horizon. Jar evidence and the upstream behaviour extraction:
[`FINDINGS.md`](FINDINGS.md). Slice plan: [`PLAN.md`](PLAN.md). Ladder and
artefacts: [`VALIDATION.md`](VALIDATION.md).

**Licence: Apache-2.0 (read from the jar's `neoforge.mods.toml`), rank 0
(permissive).** Local-only until the maintainer approves publishing
(ARCHITECTURE.md §8); [`LICENSE`](LICENSE) and
[`LICENSE-NOTICE.md`](LICENSE-NOTICE.md) carry upstream's terms.

**Class + tier (ledger): `content` / `deep`.** Per `horizon/docs/modpacks.md` a
`deep` port brings player travel driven by server hooks — here the run walk, the
ride along it and the entrances that pull — on top of carried content. The
parent **Create** is upstream and cannot be linked (`ARCHITECTURE.md` §3, "No
cross-mod API between ports"), so the slice takes the travel rule and leaves
Create's kinetic power, which is what decides an entrance's speed, as a gap.

## Slice boundary

| Piece | Implemented |
|---|---|
| Blocks | `create_hypertube:hypertube` (axis booleans + `connected`) and `create_hypertube:hypertube_entrance` (`facing` × `open`), carried from the jar with their blockstates, models, textures, loot tables and lang lines |
| Items | both block items, with 26.3 `items/*.json` definitions; recipes adapted to vanilla (see deviations) |
| Placement | a placed entrance takes the face its placer looks along (`player.getDirection()`, `UP`/`DOWN` beyond ±45°); a placed tube takes its axis from the tubes and entrances beside it, and its neighbours' states are worked out again; a break does the same for its neighbours |
| Travel | the entrance pulls the entity standing in the cell **behind its mouth**; the run is the maximal straight line of tubes from that mouth; the traveller is moved **0.5 blocks a tick** (the jar's `calculateTravelSpeed(16)`) along the polyline of block centres, and leaves **1.5 blocks past a far entrance's centre** (half a block past a bare tube's) |
| Guards | a run shorter than three path points does not travel (the jar's `travelPoints.size() < 3`); a 40-tick (2,000 ms) re-entry guard after a ride ends, so the far entrance does not suck the traveller straight back |
| Shipping | content embedded in the one `.hnmod` (the AE2 pattern): `mixins/create_hypertube/data/create_hypertube-content.hmod` + one `content_root` HEAD injection |

### Gaps (recorded, not ported)

- **Kinetic power.** Create's rotation network decides whether an entrance is
  open (`NEEDED_SPEED = 16` rpm) and how fast a ride is
  (`0.4333·min(1, rpm/16) + rpm/240`). The parent cannot be linked, so the port's
  entrance always runs at the jar's *minimum powered* speed, `travel_speed(16)`
  = 0.5 blocks a tick. `travel_speed(rpm)` is in `runtime.rs`, tested at 8, 16,
  32 and 256 rpm, so an accelerator slice can feed it.
- **Accelerators, junctions, the funnel and the smart-tube attachments.**
  `hypertube_accelerator`, `hypertube_junction`, `hypertube_funnel`,
  `tube_path`, `coghweel_hole`, the scanner and redstone-detector attachments
  are not carried.
- **Curves and turns.** Upstream joins tubes with bezier connections
  (`BezierConnection`) and follows them; this port's run is one axis, so a tube
  that turns ends the run at the corner.
- **The client half.** No detached camera, swim pose, suction particles or
  sound, no bezier tube renderer, no escape keybind: the ride is a per-tick
  server teleport and the client simply follows.
- **Non-player travellers.** ~~Only server players ride (villagers, fish and
  `create:package` do not), and `traveller_entities` / the entity
  whitelist-blacklist config is not carried.~~ **Carried in slice 2** (2026-11-21): every living
  entity rides except the jar's two default blacklist kinds. The `traveller_entities` tag and the
  other three `entityListMode` values are still not carried — only the default `BLACKLIST` mode,
  whose two names are constants. See `## Slice 2` at the end of this file.
- **Tube collision.** Upstream gives a tube a thin solid box and an empty one
  only to an entity marked as travelling; a content block's collision cannot
  depend on the entity, so this port's tubes have **no collision** for anyone
  (walk-through). Recorded as a deviation below.
- **Config, goggles tooltips, the `locked`/`has_block_in_front`/`waterlogged`/
  `power`/`powered` entrance states, and the `open` state's animation.**

## Upstream files read

Repository `https://github.com/PedroRok/CreateHypertubes`, commit
**`c3b74f52437520b05868b5eb965dc54a45d27602`** (2026-07-30, `mod_version=0.6.0`,
`minecraft_version=1.21.1`) — the same version the pack's jar was built from.
Cloned read-only outside the tree; nothing was copied, only behaviour read.

| Area | Files | What was extracted |
|---|---|---|
| Travel constants | `core/travel/TravelConstants.java` | `NEEDED_SPEED = 16`, `DEFAULT_TRAVEL_TIME = 2000`, the traveller entity list |
| Speed | `utils/TubeUtils.java` | `calculateTravelSpeed = 0.4333·min(1, rpm/16) + rpm/240` |
| Run start | `core/travel/TravelManager.java` | the 3-point minimum, the re-entry guard (`LAST_TRAVEL_TIME`/`LAST_TRAVEL_BLOCKPOS`), the exit offset and the final `setDeltaMovement` |
| Path | `core/travel/TravelPathData.java` | entrance centre, one step along `FACING`, then connected cell centres; the near-point cleanup |
| Ride | `core/travel/TravelPathMover.java` | advance by `travelSpeed` a tick along the polyline |
| Entry cell | `blocks/blockentities/parent/TravelInteractTubeBlockEntity.java` | `RADIUS = 1.0`, the entity pulled from `pos + opposite(FACING)` |
| Entrance | `blocks/HyperEntranceBlock.java` | placement facing from the player's look, `UP`/`DOWN` beyond ±45°, the `OPEN` state |
| Tube states | `blocks/HypertubeBlock.java` | `north_south`/`east_west`/`up_down` precedence, `connected`, `getPlacementFacing`, `neighborChanged` |
| Blocks | `registry/ModBlocks.java` | `destroyTime 1.0`, `explosionResistance 10`, `SoundType.METAL`, `noOcclusion`, not view-blocking, not suffocating |
| Config | `config/ServerConfig.java` | `speedMultiplier` (default 1.0), the entity list modes |

## Where the rewrite differs (deliberate deviations)

1. **Speed is constant** at the jar's minimum powered value instead of following
   a kinetic network (no Create to link).
2. **A teleport a tick** (`native_teleport_player`) instead of
   `setPos` + delta velocity: the player's own input cannot derail the ride, and
   the pin's `/tp`-style teleport zeroes motion, so no exit momentum is carried
   (`TravelManager` leaves with `lastDir · max(speed, 1)`).
3. **Tubes have no collision** for anyone (see gaps): a content block's
   collision cannot depend on the entity.
4. **One axis per run**: a corner ends the ride where upstream follows a bezier.
5. **The entry cell is the whole cell behind the mouth**; upstream centres a
   1.5-block box half a cell out of it (`getInRangeLivingEntities`).
6. **Only server players travel**, not the jar's entity families.
7. **Recipes are adapted to vanilla**, because the jar's name Create's items:
   brass sheet → copper ingot, `c:glass_panes` → glass pane, smart chute →
   hopper, cogwheel → iron ingot, the uncarried funnel → a hypertube. Same
   patterns and counts.
8. **The tube outline is the whole cell** (the jar's is the thin tube box), so a
   tube is easy to aim at and break.
9. **The entrance's `open` state stays `false`** — the model's closed form — as
   the open/close animation is part of the client half.

## Upstream defects fixed

None proved. The jar and its source agree on the states, the speeds and the
travel rules; the two things this port does differently (no collision, one axis)
are limits of the content and hook APIs, recorded as deviations above, not
defects in the mod.

## Hooks and helpers (pin `1d63e0a`, mixins `5a64af9`)

| Hook / target | Version | Helper | What it does |
|---|---|---|---|
| `server_tick` | v1, API 4 | `server_tick.rs` | At `ServerTickEnd` of a running tick: advance every ride one tick and teleport, then let the entrances pull whoever stands in a mouth |
| `place_block` | v1, API 14 | `place_block.rs` | A placed entrance takes its facing; a placed tube takes its axis and refreshes its tube neighbours |
| `destroy_block` | v1, API 14 | `destroy_block.rs` | A broken block leaves its tube neighbours on one axis fewer |
| `content_root` (target injection) | — | `embedded_content.rs` | Writes the embedded `.hmod` to `.horizon-cache/` and appends it to the dev-mod list |

Helper called, not named as a hook: **`native_teleport_player(uuid, dimension,
pos, yaw, pitch)`** — a *pending* fragment (`teleport_player`) at this pin, so a
bundle may call it but may not name its hook (AGENTS.md, campaign pin). This is
the same path `elevatorid` slice 2 verified in game. The slice-1 route it
replaces (`execute in <dim> run tp` through `native_run_command`) is not used.

Blocks are read through the server tick's read scope
(`native_server_block(context, dimension, pos)`), which is why the ride lives in
`server_tick` rather than in a player hook.

## Module layout

- `runtime.rs` — pure: `travel_speed`, `Dir`, `Cell`/`World`, `plan`, `Ride`,
  `entry_cell`/`starts_ride`, `may_enter`. 16 unit tests, no game types.
- `support.rs` — glue: the ride table (`static Mutex<Option<State>>`), the read
  scope, the teleport, the block-state refresh.
- one private function per helper file (`server_tick.rs`, `place_block.rs`,
  `destroy_block.rs`, `embedded_content.rs`).

## Content

`content/` is generated by `tools/assemble_content.py` from the jar (SHA-256
checked) and rebuilt by `tools/package.sh`; 27 files, the two block
declarations, the creative tab, the two recipes, the two loot tables (26.3's
singular `condition`), both mineable tags, and the jar's own blockstates, models,
textures and the three lang lines this slice uses.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices,rust-port

## Verification

Everything below was run in this directory on 2026-11-11/12 at the campaign pin
`1d63e0a5a37a7a708eb0b32b49bf0dfeb28ed8a9` (mixins
`5a64af938ec86b00d53d16a408aabc0038fb3e57`), `CARGO_INCREMENTAL=0`, every build
step through `ports/tools/build-slot.sh`. Full logs and the e2e transcripts:
[`VALIDATION.md`](VALIDATION.md) and
`ports/_shared/evidence/create_hypertube/`.

| Step | Evidence |
|---|---|
| `tools/unit.sh fmt` | exit 0 |
| `tools/unit.sh clippy` | exit 0, 0 warnings |
| `tools/unit.sh test` | `16 passed; 0 failed` (written first: the stub run was **14 failed / 1 passed**, then green) |
| staged `horizon.py check` | `cargo_exit: 0`, **0 warnings** |
| staged `horizon.py test` | `game::create_hypertube::tests` **16 passed; 0 failed; 1240 filtered**, `cargo_exit: 0` |
| staged `horizon.py build` (fast) | `cargo_exit: 0`, 0 warnings |
| `tools/package.sh` × 2 | `.hmod` 15,628 B `351ee2d5…c9d7` (27 entries) and `.hnmod` 24,877 B `f015aac3…a4bc` (9 entries), **identical bytes on both runs** |
| `horizon-mod check create_hypertube.hnmod --kind native-mod` | exit 0, `native-mod, format native-1/…, for 26.3` |
| `tools/e2e.sh` (default, content + bundle) | **PASS, `EXIT:0`** — ride at 0.5 blocks a tick, arrival 1.5 past the far entrance, two controls, a wall, and both placement states |
| `EMBEDDED=1 tools/e2e.sh` (no `--dev-mod`, plus the unusable-cache control) | **PASS, `EXIT:0`** — the embedded 15,628 B file is byte-identical to `content/create_hypertube.hmod`; without it neither id is known |
| `SELFTEST=1 tools/e2e.sh` | **fails as designed, `EXIT:1`** |
| `check-e2e-logs.py create_hypertube --strict` | exit 0, `logs=3 ok=3 missing-exit=0 bad-exit=0` |
| `check-skills.py --notes ports/create_hypertube` | `SKILLS GATE: PASS` |
| `upstream_ready.py create_hypertube` | exit 1 with **one** blocker: `status is pending, not ported` — the ledger row is the orchestrator's to move to `ported-partial` (this job may not edit `ports/ledger.csv`); licence, artefacts, `Skills:` line, e2e log and pin all pass |

Measured in game (The End arena, run of 20 tubes): **0.5 blocks a tick** over
8–9 samples of the straight part; the ride ended at **x = 223.0** = the far
entrance's centre + 1.5; an entrance facing air and a lone tube moved nobody
(20 ticks, unchanged); a stone wall ended the ride at x = 202.36 with the far
entrance at 206 never reached and the traveller unhurt; a placed entrance read
`[facing=east,open=false]`; a placed tube and its neighbour both read
`[connected=true,east_west=true,north_south=false,up_down=false]`.

## Migration to the SDK format (2026-11-18, SDK `0b14f8a`)

Horizon's mod-API merge (#16941, launcher ≥ 0.2.70) retired the `.hnmod` container, and the
registry closed this port's submission (**PR #785**) on 2026-11-18 with *"republish this as a
native `.hmod` with the SDK from the next Nightly"*. The port is now one flat package.

- **Pin:** Horizon **`0b14f8acfd97fa2c750e42795249dcc981178ca4`** (nightly 2026-11-18),
  horizon-mixins **`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`**, mod API **`0.2`**, launcher
  0.2.78. The SDK is fetched into `.horizon/sdk/` by `cargo horizon-mod` and never packed.
- **Version:** the port's own **0.2.0** (the retired bundle was 0.1.0; a resubmission is always a
  new version).
- **Class + tier unchanged:** class **content**, tier **deep** (ledger row): the two carried
  blocks plus player travel driven by server hooks. Nothing is re-tiered; the travel is still the
  "entity/player movement" a `deep` port needs, now through the SDK's own teleport.

### The travel: a hook, not a Part — and which call replaced the movement helper

**The travel is the global `server_tick` hook, not a Part.** A ride belongs to no single object:
it spans a run of blocks, pulls whichever player stands in a mouth, and has to keep a table
between ticks. The SDK's rule is that a moment belonging to *one* block, item, block entity, menu
or entity type is a `Part`; a run is none of those, so `Hooks::server_tick` (the same moment the
retired bundle injected) owns it. The two **shapes** are Parts, because each belongs to one block.

**`native_teleport_player(uuid, dimension, pos, yaw, pitch)` → `EntityRef::teleport_to(host,
pos, rotation)`** (host API 0.2, `Entity.teleportTo`, generated handle method; the report lists
`method:EntityRef::teleport_to` in `uses.json`). The dimension argument is gone: `teleport_to`
moves the entity inside its own level, so the port no longer has to carry the dimension name at
all. `rotation: None` keeps the traveller's own yaw and pitch, which is what the retired call was
given (the player's own values). Everything else about the ride — 0.5 blocks a tick, the 1.5-block
exit past a far entrance, the 40-tick re-entry guard — is the same `runtime.rs` code, untouched.

### Checklist — files created, files deleted

| Created | What it holds |
|---|---|
| `horizon-mod.toml` | the only manifest: `id`, `version = "0.2.0"`, `api = "0.2"`, `side = "both"`, `capabilities = ["registries"]`, `[native]` with the exact `game`/`horizon`/`mixins` |
| `Cargo.toml` | one crate; its only dependency is `horizon-mod-api` from `.horizon/sdk/` |
| `src/lib.rs` | the one `#[mod_api::horizon_mod] impl Hooks` (`register`, `server_tick`), the two `BlockPart`s, the ride table and 3 glue tests |
| `src/runtime.rs` | the old `runtime.rs`, **byte-identical** (606 lines, SHA-256 `d78f040ef902aa58339a37bb12ac37242f598e6ca214159de766d0ef258baa01`, `cmp` clean before the old copy was deleted — and again after `cargo fmt`) |
| `assets/create_hypertube/…` | the carried blockstates, models, textures, `items/*.json` and `lang/en_us.json`, moved from `content/assets/` |
| `data/create_hypertube/…`, `data/minecraft/…` | the two block declarations, the creative tab, the two recipes, the two loot tables and both mineable tags, moved from `content/data/` — all 26 carried entries byte-identical to the retired `content/create_hypertube.hmod` (15,628 B, `evidence/content-carry.log`) |
| `create_hypertube.hmod` | the delivered package, in the port root |
| `.gitignore` | `/target`, `/.horizon`, `/Cargo.lock` (trap 5) |

| Deleted | Why | Where it went |
|---|---|---|
| `mixins/create_hypertube/` (`horizon-mixin.toml`, `support.rs`, `server_tick.rs`, `place_block.rs`, `destroy_block.rs`, `embedded_content.rs`, `data/*.hmod`) | the plan/injection schema and per-hook helpers are not part of any SDK package | `runtime.rs` → `src/`; the four hook bodies → `impl Hooks` + two Parts; the embedded content → nothing (see below) |
| `content/` (`horizon-mod.toml`, `assets/`, `data/`, the built `.hmod`) | a second package; the flat package carries content itself | `assets/` + `data/` at the package root; the old manifest and `.hmod` kept as evidence |
| `create_hypertube.hnmod` (24,877 B, `f015aac3…`) | the retired container | `_shared/evidence/create_hypertube/retired-hnmod-0.1.0/` |
| `compatibility.json` | the pin is `[native]` in `horizon-mod.toml` | same folder |
| `rust-toolchain.toml` (1.95.0) | not part of any new package (and it named a toolchain the box no longer has) | same folder |
| `Cargo.lock` | not needed (no registry dependency), and a packed lock changes the artifact (trap 5) | not kept |
| `tools/horizon.py`, `tools/package.py`, `tools/package.sh`, `tools/assemble_content.py`, `tools/unit.sh` | the staging/mixin/packaging machinery; there is no stage, plan or repackage step any more | same folder |

**Kept:** `tools/e2e.sh` (the scenario is still the only in-game oracle; its `--dev-mod content`,
`EMBEDDED=1` and `CONTROL=1` legs were the retired container's and are gone — see the file's STATUS
header), `FINDINGS.md`, `PLAN.md`, `VALIDATION.md` (history), `README.md` (rewritten for the flat
layout), `LICENSE`, `LICENSE-NOTICE.md`.

### Hook / helper → SDK (0.2) mapping

| Retired | SDK (0.2) | Where |
|---|---|---|
| `server_tick` injection (the travel) | **`Hooks::server_tick`** (`ServerTickEnd`, `world_running`) — a **hook**, because a run belongs to no single object | `src/lib.rs`, `Mod::server_tick` |
| `native_teleport_player(uuid, dimension, pos, yaw, pitch)` (a *pending* fragment called as a helper) | **`EntityRef::teleport_to(host, pos, None)`** — `Entity.teleportTo`, no dimension argument | `src/lib.rs` |
| `native_server_block` read scope, `native_server_players`, `native_acting_player` | `PlayerRef::level(host)`, `LevelRef::block(host, pos)`, `LevelRef::block_property(host, pos, "facing")`, `Players::server_players()`, `PlayerRef::entity()` | `src/lib.rs`, `Cells` |
| `place_block` injection (entrance facing, tube axis) | **`BlockPart::state_for_placement`** on the entrance and the tube (`Block.getStateForPlacement` — the vanilla method upstream's `HyperEntranceBlock`/`HypertubeBlock` override) | `src/lib.rs`, `EntranceShape`/`TubeShape` |
| `destroy_block` injection (neighbours worked out again) | **`BlockPart::update_shape`** on the tube (`BlockBehaviour.updateShape`): the engine writes the answer, so no hook has to walk the neighbours itself | `src/lib.rs`, `TubeShape` |
| `support.rs` `refresh_tube` (the axis precedence) | `tube_state` + `TubeShape::shape` (pure precedence kept, one test) | `src/lib.rs` |
| `support.rs` `ReadScope` (`Cell` mapping) | `Cells` + `cell_of` | `src/lib.rs` |
| `support.rs` `static Mutex<Option<State>>` | a `Mutex<State>` field on the `Mod` struct (the macro boxes one `Default` per session) | `src/lib.rs` |
| `embedded_content.rs` `content_root` injection (AE2 pattern) | — (the package carries `assets/` and `data/` itself) | — |
| `horizon-mixin.toml` `[[module]]`/`[[injection]]` | `fn register(&self, r: &mut dyn Registrar, _: &RegistrationContext)` | `src/lib.rs` |

The dispatch is real, not assumed: on an authoritative server the engine asks the mod's
`update_shape` **before** the template's own shape logic
(`crates/horizon-world/src/level/shapes.rs:36` → `crates/horizon-client/src/game.rs:1538`
`before_update_shape` → `native_update_shape`), and `before_state_for_placement`
(`game.rs:1562`) likewise, so a content block on the `minecraft:stone` template still gets the
first word on both. `crates/` line numbers are the `1d63e0a` checkout's; the SDK hook is the same
dispatch point.

### Build and check (verbatim)

`build-slot.sh` speaks the retired tool, so every command below runs **directly in the port**
under a lease (`BUILD_LOCAL=1`, `bash -c 'cd ports/create_hypertube && …'`), with
`CARGO_INCREMENTAL=0` and **no** `--target-dir`, stage or plan step:

```sh
ports/tools/build-slot.sh run --job sdk-cht --port ports/create_hypertube --step test \
    -- bash -c 'cd ports/create_hypertube && CARGO_INCREMENTAL=0 cargo test'
# 16 runtime tests green before any glue existed; 19 with the glue (16 + 3)

ports/tools/build-slot.sh run --job sdk-cht --port ports/create_hypertube --step lint \
    -- bash -c 'cd ports/create_hypertube && cargo fmt --check &&
        CARGO_INCREMENTAL=0 cargo clippy --all-targets -- -D warnings'
# fmt clean (FMT_EXIT:0); clippy exit 0, 0 warnings

ports/tools/build-slot.sh run --job sdk-cht --port ports/create_hypertube --step build \
    -- bash -c 'cd ports/create_hypertube && rm -f Cargo.lock &&
        CARGO_INCREMENTAL=0 cargo horizon-mod build &&
        cp target/horizon-mod/create_hypertube.hmod ./create_hypertube.hmod'
# SDK 0b14f8a (build 0b14f8ac…) in ./.horizon/sdk
# Built ./target/horizon-mod/create_hypertube.hmod

ports/tools/build-slot.sh run --job sdk-cht --port ports/create_hypertube --step check \
    -- bash -c 'cd ports/create_hypertube &&
        cargo horizon-mod check create_hypertube.hmod && cargo horizon-mod fits create_hypertube.hmod'
# create_hypertube 0.2.0 (native-mod, format native-1/0b14f8ac…/e59da909…, for 26.3)
#   36911 bytes, SHA-256 1aee001be7caad5814d4ad8663357d778b2b7c6b24b6a71cdc6e5c28a95be001, unsigned
#   CHECK_EXIT:0
# Create: Hypertube:  /  0b14f8a  made for    FITS_EXIT:0
```

### Traps this migration cost (for the next port)

1. **The mod-facing host API is on the handles, not on `ServerHost`.** `entity_teleport_to`,
   `player_level`, `level_block`, `level_block_property` are **backend** trait methods
   (`EntitiesBackendMut`, `PlayersBackend`, `LevelsBackend`); a mod calls
   `entity.teleport_to(host, pos, None)`, `player.level(host)`, `level.block(host, pos)`,
   `level.block_property(host, pos, key)`. `ServerHost`'s supertraits only cover the ones that are
   area methods (`host.players()`, `host.commands()`, `host.block_key(id)`). The first compile of
   the glue failed on exactly this (five `E0599`s).
2. **`host.block_key(id)` is the run-time key lookup** (`#[access(Metadata)]`): `Registrar::block_key`
   is for `register` only. The server tick needs the tube/entrance keys to compare block reads, so
   it asks `host.block_key(TUBE)` once per tick.
3. **`Direction` is an exhaustive six-variant enum** from `horizon-core` (`Direction::ALL`,
   `normal()`), so a `match` needs all six arms and no wildcard — a wildcard means either a
   never-taken arm or an unreachable-pattern warning under `-D warnings`.
4. **`UpdateShapeEvent` carries the neighbour's *new* state**, which may not be in the world yet
   (a piston landing it). Read the other five faces from the level and take `event.direction`'s
   from `event.neighbour`, or a placement reads its own cell instead of the block that just
   arrived.
5. **`ServerTickPhase` must be matched for both the phase and `world_running`.** A frozen step
   carries `world_running: false`; treating `ServerTickEnd` as "the world advanced" moves the
   traveller during a frozen debug step.
6. **`cargo horizon-mod build` packs; it does not compile against the game** (trap 8 of the
   reference): the real native build is `horizon-launcher native-build <port> --instance
   <instance> --trust-native-code`, which is not installed here and has no game build at
   `0b14f8a` (the shared binaries are at `1d63e0a5`/`41f822b6`). The compile evidence is
   `cargo test`/`cargo clippy --all-targets` against the pinned SDK API crate — the same crate the
   launcher compiles the mod against — plus `horizon-mod check`/`fits`.
7. **No `Cargo.lock` in the package.** `cargo test`/`clippy` write one; `rm -f Cargo.lock` right
   before `cargo horizon-mod build` (and `/Cargo.lock` in `.gitignore`), or the artifact carries
   the SDK's registry pins and changes bytes.
8. **`cargo fmt` runs over `src/runtime.rs`.** It happens to be fmt-clean (the `cmp` against the
   retired file still passes afterwards), but the gate is `cmp` after `fmt`, not before.

### Migration verification (SDK `0b14f8a`)

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,verification-before-completion; BeautifulRust/rust-best-practices,rust-port

| Check | Command | Result |
|---|---|---|
| Runtime carried | `cp` + `cmp` against the retired `mixins/create_hypertube/runtime.rs` | **byte-identical**, 606 lines, SHA-256 `d78f040e…baa01` (`evidence/final-gate.log`) |
| Runtime tests **before glue** | `cargo test` (lib.rs = `pub mod runtime;` only) | **16 passed, 0 failed** (`evidence/runtime-before-glue.log`) |
| Glue tests red first | `cargo test` with the tests and no implementation | `E0425: cannot find function tube_state`, exit 101 (`evidence/glue-tests-red.log`) |
| Whole crate | `cargo test` | **19 passed, 0 failed** (16 runtime + 3 glue) (`evidence/sdk-test.log`) |
| Lints | `cargo clippy --all-targets -- -D warnings` | exit 0, 0 warnings (`evidence/sdk-clippy.log`) |
| Formatting | `cargo fmt --check` | clean (`evidence/final-gate.log`) |
| Package | `cargo horizon-mod build` | `target/horizon-mod/create_hypertube.hmod`, EXIT 0; two consecutive builds identical bytes (`evidence/sdk-build.log`) |
| Registry check | `cargo horizon-mod check create_hypertube.hmod` | `create_hypertube 0.2.0 (native-mod, format native-1/0b14f8ac…/e59da909…, for 26.3)`, **36,911 B**, SHA-256 `1aee001b…e001`, **EXIT 0** (`evidence/sdk-check.log`) |
| Fits the pinned build | `cargo horizon-mod fits create_hypertube.hmod --build nightly` | `0b14f8a  made for`, **EXIT 0** (`evidence/sdk-fits.log`) |
| Package contents | `zipfile.namelist()` | **34 entries**: manifest, `Cargo.toml`, `src/lib.rs`, `src/runtime.rs`, 26 `assets/`+`data/` files (17 assets, 9 data), `LICENSE`, `LICENSE-NOTICE.md`, `README.md`, `uses.json`; **no `Cargo.lock`** (`evidence/sdk-package-entries.log`) |
| `runtime.rs` inside the package | `unzip -p … src/runtime.rs \| sha256sum` | `d78f040e…baa01` = the retired file, byte for byte |
| Carried content | zip-compare against the retired `content/create_hypertube.hmod` | 26 entries, **no mismatches** (`evidence/content-carry.log`) |
| What it uses | `uses.json` in the package (111 entries) | names `hook:server_tick`, `hook:state_for_placement`, `hook:update_shape`, `method:EntityRef::teleport_to`, `method:LevelRef::block`/`block_property`, `method:PlayerRef::level`, `method:Players::server_players`, `part:block` — the mapping, as read by the checker |
| Fresh-tree repeat | `target/` and `Cargo.lock` removed, then `cargo horizon-mod build` | same **36,911 B**, same sha256 `1aee001b…e001`, `cmp` clean against the delivered file (`evidence/fresh-rebuild.log`) |
| Skills line | `python3 ports/tools/check-skills.py --notes ports/create_hypertube` | `Skills line present`, **SKILLS GATE: PASS** |

### Not re-run in this migration

- **The in-game e2e.** There is no `horizon-launcher` on this box and no game build at
  `0b14f8a` (the shared binaries are `1d63e0a5` and `41f822b6`), so no binary can carry this
  package yet. The 0.1.0 run stands as the behaviour's evidence
  (`evidence/e2e-default.log`, `evidence/e2e-embedded.log`, `evidence/e2e-selftest.log`,
  `check-e2e-logs.py create_hypertube --strict` → `logs=3 ok=3`): what changed is the
  *transport* — a typed `BlockPart`/`Hooks` API and `EntityRef::teleport_to` in place of
  `native_teleport_player` — not the rules, which are byte-identical and tested. The first slice
  at a launcher-capable box runs `GAME=<launcher-built> tools/e2e.sh` and records it.
- **The staged ladder** (`tools/horizon.py stage/check/test/build`) — deleted with the retired
  format.

### Gaps after the migration

1. **No in-game run at `0b14f8a`** (the launcher/game build is absent). Every other claim here is
   either carried logic, a compile-time claim against the pinned SDK, or a mapping read from the
   pin's dispatch sites.
2. **The tube's shape is written by the engine now, not by the port.** That is closer to upstream
   (a piston or a `/setblock` refreshes a tube too, which the retired place/destroy hooks did not
   cover), but it is the one behaviour the 0.1.0 e2e did not assert in that form: leg G asserts the
   placed tube *and* its neighbour, which is the `update_shape` path.
3. **Still not carried (unchanged from slice 1):** Create's kinetic network (so the entrance always
   runs at the minimum powered speed), accelerators, junctions, the funnel, the smart-tube
   attachments, bezier curves and turns, the client half (camera, swim pose, particles, sounds,
   keybind), non-player travellers, the config, the goggles tooltips, the entrance's extra states
   and its open/close animation, and tube collision.

## Changelog for the resubmission

> Supersedes **#785**, closed because Horizon retired `.hnmod` (#17992). Changes: the flat SDK
> package with `api = "0.2"` and `[native]` pinned to `0a875da`/`e59da90`; the travel is the
> SDK's `server_tick` hook and moves the traveller with `EntityRef::teleport_to` instead of the
> retired `native_teleport_player` helper (no dimension argument, same 0.5 blocks a tick and
> 1.5-block exit); the two blocks' shapes are `BlockPart`s (`state_for_placement` on both,
> `update_shape` on the tube) instead of the `place_block`/`destroy_block` hooks recomputing
> neighbours; the blocks, models, textures, recipes, loot tables, tags and lang ship **inside** the
> package, so the embedded-content bundle is gone; `src/runtime.rs` and its 16 tests are
> unchanged. Version 0.2.0.
>
> 0.2.1 adds slice 2: every **living** traveller rides, not only the server's players — the jar's
> default `BLACKLIST` mode, which refuses only `minecraft:wither` and `minecraft:ender_dragon`; a
> spectator and a traveller holding sneak are refused, as the jar refuses them. The ride table is
> keyed by entity UUID, as `TravelManager`'s is.

## Slice 2 — every living traveller (2026-11-21, pin `0a875da`)

The gap this slice closes, quoted from `### Gaps` above:

> **Non-player travellers.** Only server players ride (villagers, fish and `create:package` do
> not), and `traveller_entities` / the entity whitelist-blacklist config is not carried.

It fits the ledger's **`content` / `deep`** tier: the travel is already the server-hook half of a
`deep` port, and this widens *who* it carries — no new machine, menu or renderer. Accelerators,
junctions and the funnel were rejected for this slice because their upstream effect is read from
Create's kinetic network (`getSpeed()`), which this port cannot link: carrying one would mean
inventing a no-power speed. Curves need the bezier renderer and a corner model a content block
cannot express. The client half is a renderer the content API cannot declare.

### The rules, from the jar (upstream `c3b74f52`, 0.6.0)

| Rule | Where | What the port does |
|---|---|---|
| Every entity travels except a blacklist | `config/ServerConfig.java` `entityListMode` default `BLACKLIST` | `BLACKLISTED_TRAVELLERS` = `minecraft:wither`, `minecraft:ender_dragon`; every other kind rides |
| Only living entities are candidates | `parent/TravelInteractTubeBlockEntity.java:117` (`getEntitiesOfClass(LivingEntity.class, …)`) | `host.living(entity)` must resolve; a dropped item, arrow or orb is not a traveller |
| A spectator never travels | `TravelManager.java:63` | `may_travel(kind, spectator, …)` |
| Sneak refuses the pull | `HyperEntranceBlockEntity.tick` (`isShiftKeyDown()` and not already travelling) | `may_pull(now, last_finished, sneaking)` |
| The ride table is keyed by entity UUID | `TravelManager.java:54` (`travelDataMap`) | `State.rides: BTreeMap<u128, Rider>` — player and villager in one table |
| A too-short run refuses silently for a non-player | `TravelManager.java:82-88` | `plan()`'s `MIN_POINTS` check, unchanged |
| The guard is 2 s, per traveller | `TravelManager.java:62-79` | `REENTRY_TICKS`, now per UUID for every kind |

### How the port finds a traveller, and why that is a deviation

The jar's entrance is a **block entity**, so the game ticks it and it queries its own 1.5-block
box. A content block (`data/create_hypertube/horizon/block/*.json`) has **no block entity** at
this pin, so the port must find the mouths itself. It does two things each server tick:

1. the server's **players** are looked at every tick, exactly as before (six block reads each);
2. on every `ENTITY_SWEEP_TICKS`-th tick (**10 ticks, 0.5 s**) the mod walks
   `LevelRef::all_entities` for each level a player is in and looks at each living entity's six
   neighbours.

Deviation, recorded: **a non-player traveller is picked up within half a second rather than the
same tick**. A per-tick walk of the level's entity list would be O(entities × 6) block reads every
tick, which the jar never pays because its block entities tick themselves. The sweep keeps the
identity (`all_entities` allocates one buffer and sorts once per call) off the per-tick path. The
kind check costs one registry id `String` per living candidate per sweep: the blacklist rule is
pure and tested on ids (`may_travel`), and 0.5 s is not a hot path.

Two smaller, inherited deviations still apply to the new travellers: the entry test is the whole
cell behind the mouth (upstream centres a 1.5-block box half a cell out of it), and every traveller
in one mouth starts its own ride in the tick it is found (upstream's `getNearestEntity` takes one
per tick). The re-entry guard is also broader than the jar's: it refuses every entrance for 40
ticks, where the jar refuses only the block it left. All three are the slice-1 shape, now shared
by mobs.

Still not carried in this family: the `create_hypertube:traveller_entities` **tag**, the
`WHITELIST` / `TAG_ONLY` / `TAG_WITH_BLACKLIST` modes and the `speedMultiplier` / entity-list
**config** (the defaults are constants here). A `create:package` therefore cannot ride — Create is
not carried — but with the default blacklist any other living kind can.

### Coverage (the jar's families)

| Family | State | Where it is proven |
|---|---|---|
| The two blocks: place, read back, state properties | `tested` | e2e F/G (entrance `facing`, tube axis + its neighbour); the mineable tags are what let M break them with a pickaxe |
| The two blocks' **loot tables** | `tested` | e2e M: each broken in **survival** drops one of itself (the carried tables' `bonus_rolls` and `"rolls": 1.0` — two shapes `check_261_dialect.py` flags as unverified — are accepted by 26.3: the drops appeared) |
| The two **recipes** (crafting table, shaped) | `tested` | e2e L, `tools/craft_check.py`: `BGB/GG/BGB` → **16** tubes with 4 copper + 4 glass consumed; tube/iron/hopper → **1** entrance with all three consumed; a nine-copper ring leaves the result empty |
| Straight-run travel, speed, exit, wall, too-short run | `tested` | e2e A–E (player) |
| Non-player travellers (living, blacklist, sneak, spectator) | `tested` | e2e H (villager rides), I (item not pulled), K (wither not pulled), J (sneak refused, standing rides); unit tests for the rules |
| Kinetic power (speed from Create's network) | `not ported` | parent Create cannot be linked (`ARCHITECTURE.md` §3); the entrance rides at `travel_speed(16)` |
| Accelerators, junctions, funnel, smart-tube attachments | `not ported` | their effect is kinetic; see above |
| Curves/bezier connections and turns | `not ported` | needs the bezier renderer and a corner model |
| Client half (camera, pose, particles, sounds, keybind) | `not ported` | a client renderer the content API cannot declare |
| Tube collision (thin box; empty only for a traveller) | `not ported` | a content block's collision cannot depend on the entity |
| The `traveller_entities` tag and the entity-list config | `not ported` | no config-file API carried; the default mode is the constants in `runtime.rs` |

`python3 ports/tools/check_261_dialect.py create_hypertube.hmod` also flags the two loot tables'
`bonus_rolls` / `"rolls": 1.0` (4 offenders). Per `HANDOVER.md` §9d those two shapes are **not** among
the three game-confirmed-fatal ones, and leg M now measures them in game: both blocks drop their own
item, so 26.3 accepts the tables as carried. The recipes are `ok` (bare ids, no tag/object form).

### Red → green (verbatim)

`src/runtime.rs` is no longer the retired bundle's file byte for byte: slice 2 appends the four
traveller rules below the travel rules, each with its test (the retired 606-line copy is inside
`_shared/evidence/create_hypertube/retired-hnmod-0.1.0/create_hypertube.hnmod`, 21,810 B).
`src/lib.rs` still only converts SDK types to the runtime's.

The five new rules were written as failing tests first, against stubs
(`evidence/create_hypertube/slice2-runtime-tests-red.log`):

```
test runtime::tests::the_default_blacklist_lets_every_kind_but_two_travel ... FAILED
test runtime::tests::a_spectator_never_travels ... FAILED
test runtime::tests::the_entity_sweep_runs_every_ten_ticks ... FAILED
test runtime::tests::a_sneaking_traveller_is_not_pulled ... FAILED
test runtime::tests::an_entity_stands_in_the_cell_its_feet_are_in ... FAILED

panicked at src/runtime.rs:657:13:
minecraft:wither must stay
...
test result: FAILED. 19 passed; 5 failed; 0 ignored; 0 measured; 0 filtered out
```

Then the rules landed (`may_travel`, `may_pull`, `sweep_due`, `feet_cell`), then the glue
(`Rider`, the UUID-keyed table, `advance_rides`, `pull_travellers`):

```
test result: ok. 24 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out   (evidence/sdk-test.log)
```

`cargo clippy --all-targets -- -D warnings` exit 0 with 0 warnings, `cargo fmt --check` clean
(`evidence/sdk-clippy.log`).

### In game (the launcher-built game at `0a875da`, launched `--offscreen` for the menu legs)

`launcher-game.sh build create_hypertube` compiled `create_hypertube (1 of 1)` — a fresh build, not
a reuse. Transcript: `ports/_shared/evidence/create_hypertube-e2e/e2e-slice2-default.log`.

| Leg | Assertion | Measured |
|---|---|---|
| A–G | slice 1 unchanged: 0.5 blocks a tick, exit 1.5 past the far entrance, the two controls, the wall, both placed states | 0.5 over 10 samples; x = 223.0 at z = 0.5; controls unmoved; both states as declared |
| H | a villager summoned in the mouth cell is pulled and rides the same run | 199.5 → 214.88 after 30 ticks → **223.0** at z = 6.5, y = 101.5 |
| I | a dropped item in the same mouth cell is not a traveller | 199.5 → 199.5 after 40 ticks (unmoved) |
| K | a wither in a mouth cell is refused by the default blacklist | 199.5 → 199.5 after 40 ticks (unmoved) |
| L | both carried recipes craft in a table, and consume their ingredients | `BGB/GG/BGB` → 16 tubes, copper 16→12, glass 16→12; tube/iron/hopper → 1 entrance, each 1→0; nine copper → no result |
| M | both blocks drop themselves when broken in survival | one tube and one entrance reached the inventory |
| J | a player holding sneak is not pulled; the same player standing is | `keys held: ["ShiftLeft"]`; sneaking 199.5 for 30 ticks, then 214.38 after 30 more |

Fail-capable runs: `SELFTEST=1` flips A's and H's arrival expectation and exits **1** with a
`FAIL:` verdict; `SELFTEST=2` flips only H's, so the *new* leg is the one shown to fail, exit **1**;
`NEGATIVE=1` inverts I (the item must move) and exits **1**. `check-e2e-logs.py
create_hypertube-e2e --strict` → `logs=4 ok=4 missing-exit=0 bad-exit=0`.

Three harness facts this leg cost, for the next port: a run must be built **far entrance first, then
the tubes**, or a sweep can catch a half-built run (the near entrance alone is too short; the fill
completes it in one command) — otherwise the ride ends at the bare-tube exit; a sneak test must press
shift **before** stepping into the mouth, because a standing traveller is pulled on the very next
tick; and an arrival read needs a margin of a few ticks (a fixed 12-tick wait after the sampling loop
was one tick short of the 48-tick ride under `--offscreen`, three runs in).

### Package (0.2.1)

| | |
|---|---|
| `create_hypertube.hmod` | **39,579 B**, SHA-256 `f824be2d0de77f5d65e4b0db2c1c7d52e32efbd9ab2af174542eaf9f65591699`, **34 entries**, no `Cargo.lock` |
| two consecutive builds (`rm -f Cargo.lock` before each) | `cmp`-identical, same sha |
| `cargo horizon-mod check` | `create_hypertube 0.2.1 (native-mod, format native-1/0a875da9…/e59da909…, for 26.3)`, `CHECK_EXIT:0` (`evidence/sdk-check.log`) |
| `fits --build 0a875da` | `0a875da  made for`, exit 0 (`evidence/sdk-fits.log`) |
| `fits --build 0b14f8a` | `0b14f8a  fits`, exit 0 — a different nightly, so the pin run is not a tautology |
| `uses.json` | names `handle:LevelRef::all_entities`, `EntityRef::kind`/`uuid`/`spectator`/`is_shift_key_down`/`teleport_to`, `LivingHost::living`, `hook:server_tick`, `part:entity` |
| package vs tree | `src/lib.rs`, `src/runtime.rs`, `horizon-mod.toml`, `Cargo.toml` byte-identical inside the package (`cmp`) |
| `verify-sdk-package.py create_hypertube` | **1/1** |

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices
