# Create: Hypertube — validation (slice 1)

> **History: the retired `.hnmod` bundle (0.1.0).** Everything below was run at pin
> `1d63e0a5` from the staging ladder (`tools/horizon.py`) and the embedded-content bundle, none of
> which exists any more. The current state is [`notes.md`](notes.md): `## Migration verification
> (SDK 0b14f8a)` for the flat package and `## Slice 2` for the traveller family at `0a875da`
> (its own ladder, package hash and in-game transcripts are repeated here as well). The in-game
> transcripts below remain the port's 0.1.0 evidence.

Pin **`1d63e0a5a37a7a708eb0b32b49bf0dfeb28ed8a9`** (mixins
`5a64af938ec86b00d53d16a408aabc0038fb3e57`, schema 6), Minecraft 26.3.
Every build/test/e2e step ran through `ports/tools/build-slot.sh` with
`CARGO_INCREMENTAL=0`. Logs: `ports/_shared/evidence/create_hypertube/`.

## Ladder

| Step | Command | Result | Log |
|---|---|---|---|
| fmt | `tools/unit.sh fmt` | exit 0 | session |
| clippy | `tools/unit.sh clippy` | exit 0, **0 warnings** | session |
| unit (red) | `tools/unit.sh test` on the stub runtime | **14 failed; 1 passed** — the tests were written first | session |
| unit (green) | `tools/unit.sh test` | **16 passed; 0 failed** | session |
| stage | `horizon.py stage --horizon …/pins/horizon-1d63e0a` | injection applied, `stage_changed: true` | session |
| check | `horizon.py check …` | `cargo_exit: 0`, **0 warnings** | `horizon-check.log` |
| test | `horizon.py test …` | `running 16 tests`; **16 passed; 0 failed; 1240 filtered**; `cargo_exit: 0` | `horizon-test.log` |
| build (fast) | `horizon.py build …` | `cargo_exit: 0`, 0 warnings, `fast/horizon-client` | `horizon-build.log` |
| package × 2 | `tools/package.sh` | `.hmod` 15,628 B `351ee2d5…c9d7` (27 entries); `.hnmod` 24,877 B `f015aac3…a4bc` (9 entries); **identical on both runs** | `package-hmod.log`, `package-hnmod.log` |
| native gate | `horizon-mod check create_hypertube.hnmod --kind native-mod` | exit 0 — `native-mod, format native-1/1d63e0a5…/5a64af93…, for 26.3` | `check-native.log` |

The first staged `check` (before the content was embedded) failed on
`native_data!` reading a missing
`native-data/create_hypertube/create_hypertube-content.hmod` — expected: the
embedded half must be built and copied in first, which `tools/package.sh` does.
It also showed three `dead_code` warnings (`NEEDED_SPEED`, `travel_speed`,
`Ride::finished`/`destination`), which the glue now uses or the runtime no
longer carries: the final check and build are warning-free.

## In-game (fail-capable)

Arena: The End's void at x=200, stone floor y=100, blocks at y=101, runs along
+X. Run A is an entrance at x=200 facing east, twenty tubes at x=201…220 and a
second entrance at x=221 facing west; the path from the mouth is 23.618 blocks,
47 ticks at 0.5 a tick.

| Leg | What it asserts | Default | Embedded |
|---|---|---|---|
| A | the entrance pulls the traveller in and the ride moves **0.5 blocks a tick** (median of consecutive straight-part samples against the game's tick counter) | 0.5 over 8 samples | 0.5 over 9 samples |
| B | the ride ends **1.5 blocks past the far entrance's centre**, level with the run | x = 223.0, z = 0.5 | x = 223.0, z = 0.5 |
| C | control: an entrance whose mouth faces air moves nobody (20 ticks) | unchanged at (199.5, 4.5) | unchanged |
| D | control: a lone tube with no entrance moves nobody (20 ticks) | unchanged at (202.5, 8.5) | unchanged |
| E | a solid wall in the run stops it: the traveller never reaches the far entrance | x = 202.36 < 203.6, health 20 | same |
| F | a placed entrance takes the face its placer looks along | `[facing=east,open=false]` | same |
| G | a placed tube takes its axis, and the tube beside it is worked out again | both `[connected=true,east_west=true,north_south=false,up_down=false]` | same |

`EMBEDDED=1` launches **without `--dev-mod`**: the content comes from the
bundle's `mixins/create_hypertube/data/create_hypertube-content.hmod`, written to
`.horizon-cache/` at start (15,628 B, byte-identical to
`content/create_hypertube.hmod`). Its control leg makes `.horizon-cache`
unusable first: neither id resolves there, so the run proves the embedded file is
what registers the blocks.

`SELFTEST=1` flips leg B's arrival (it expects x = 205.0) and the run exits
**1**.

| Run | Result | Log |
|---|---|---|
| default (content dir + bundle) | **PASS, `EXIT:0`** | `e2e-default.log` |
| `EMBEDDED=1` (bundle only, plus control) | **PASS, `EXIT:0`** | `e2e-embedded.log` |
| `SELFTEST=1` | **FAIL as designed, `EXIT:1`** | `e2e-selftest.log` |
| `check-e2e-logs.py create_hypertube --strict` | exit 0 — `logs=3 ok=3 missing-exit=0 bad-exit=0` | session |

`upstream_ready.py create_hypertube` exits 1 with exactly one blocker: the ledger
row still says `pending`. Every other gate it checks passes (Apache-2.0 read from
the jar, both artefacts in the port rather than `target/`, the `Skills:` line,
a `PASS` + `EXIT:0` log, the campaign pin in `compatibility.json`). Moving the
row to `ported-partial` is the orchestrator's step — this job's write ownership
excludes `ports/ledger.csv`.

## Reproduce

```sh
# the pure runtime, clippy and fmt (a slot per step)
ports/tools/build-slot.sh run --job ch-unit --port ports/create_hypertube \
    --step test -- ports/create_hypertube/tools/unit.sh test
ports/tools/build-slot.sh run --job ch-lint --port ports/create_hypertube \
    --step fmt -- bash -c 'ports/create_hypertube/tools/unit.sh fmt && ports/create_hypertube/tools/unit.sh clippy'

# content + native packages (also copies the .hnmod into the port root)
ports/tools/build-slot.sh run --job ch-pack --port ports/create_hypertube \
    --step package -- env CARGO_INCREMENTAL=0 ports/create_hypertube/tools/package.sh

# the ladder (campaign-relative arguments; horizon.py runs from the root)
for step in stage check test build; do
  ports/tools/build-slot.sh run --job "ch-$step" --port ports/create_hypertube --step "$step" -- \
      env CARGO_INCREMENTAL=0 python3 ports/create_hypertube/tools/horizon.py "$step" \
      --horizon ports/_shared/pins/horizon-1d63e0a
done

# the game legs (the e2e step rebuilds in the same lease)
ports/tools/build-slot.sh e2e --job ch-e2e --port ports/create_hypertube \
    --horizon "$PWD/ports/_shared/pins/horizon-1d63e0a" -- "$PWD/ports/create_hypertube/tools/e2e.sh"
EMBEDDED=1 …   # same command, embedded content only
SELFTEST=1 …   # same command, must exit 1
python3 ports/tools/check-e2e-logs.py create_hypertube --strict
```

Two runner notes from this job: `build-slot.sh e2e` `cd`s into the port before
running the command, so the script must be given as an **absolute** path and
`--horizon` must be absolute too; and a job forwarded to the second machine
cannot stage, because the mirrored pin checkout there is not a Git checkout —
those legs stay local (`BUILD_LOCAL=1`).

## Artefacts

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `content/create_hypertube.hmod` | 15,628 B | `351ee2d5ec52ea95c82f328cc1f9d49d03ef08a14d51a555e6ce223e00fac9d7` | 27 |
| `create_hypertube.hnmod` | 24,877 B | `f015aac32729c28c5bffdcade5026d6bc24dc3be23ce19eb2ed3eb90d3f7a4bc` | 9 |

---

# Slice 2 validation (`0a875da`, 2026-11-21) — every living traveller

Pin **Horizon `0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, Minecraft 26.3, SDK `0.2`, package `0.2.1`.
Every step ran through `ports/tools/build-slot.sh` (`BUILD_LOCAL=1`: the SDK stages in the port, so
the remote runner has no directory to sync; the launcher leg compiles the mod itself).
`.horizon/sdk` was deleted before the first build so the pin's SDK was fetched
(`SDK 0a875da (build 0a875da91d…) in ./.horizon/sdk`).

## Ladder

| Step | Command | Result | Log |
|---|---|---|---|
| unit (red) | `cargo test` with the new rules' tests and stubs | **5 failed, 19 passed** — `minecraft:wither must stay` (runtime.rs:657), `sneak refuses the pull` (:691), `sweep_due(ENTITY_SWEEP_TICKS)` (:683), `[0,0,0] != [199,101,0]` (:700), `!may_travel(player, spectator)` (:669) | `evidence/create_hypertube/slice2-runtime-tests-red.log` |
| unit (green) | `cargo test` | **24 passed; 0 failed** | `evidence/create_hypertube/sdk-test.log` |
| lints | `cargo fmt --check` + `cargo clippy --all-targets -- -D warnings` | `FMT_EXIT:0`, `CLIPPY_EXIT:0`, 0 warnings | `evidence/create_hypertube/sdk-clippy.log` |
| package × 2 | `rm -f Cargo.lock && cargo horizon-mod build` twice | 39,579 B, SHA-256 `f824be2d…1699`, **`cmp`-identical** both runs | session; `evidence/create_hypertube/sdk-check.log` |
| registry check | `cargo horizon-mod check create_hypertube.hmod` | `create_hypertube 0.2.1 (native-mod, format native-1/0a875da9…/e59da909…, for 26.3)`, `CHECK_EXIT:0` | `evidence/create_hypertube/sdk-check.log` |
| fits, the pin | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, exit 0 | `evidence/create_hypertube/sdk-fits.log` |
| fits, another build | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, exit 0 (so the pin run is not a tautology) | same |
| package gate | `verify-sdk-package.py create_hypertube` | **1/1** | session |
| package vs tree | `cmp` of `src/lib.rs`, `src/runtime.rs`, `horizon-mod.toml`, `Cargo.toml` from inside the `.hmod` | all byte-identical | session |
| skill gate | `check-skills.py --notes ports/create_hypertube --strict` | `SKILLS GATE: PASS` | session |

## In game (launcher-built)

`ports/tools/launcher-game.sh build create_hypertube` → `Compiling create_hypertube (1 of 1)`,
`native-0a875da-…`, exported pair used for `GAME`/`CTL`. Launch is `--offscreen` (legs L/M open a
crafting table screen; a headless client never opens one).

| Run | Result | Log |
|---|---|---|
| default (A–M, includes the villager, the item/wither controls, both recipes, both loot tables and the sneak differential) | **PASS, `EXIT:0`** | `evidence/create_hypertube-e2e/e2e-slice2-default.log` |
| `SELFTEST=1` (A's and H's arrival flipped) | **FAIL as designed, `EXIT:1`** | `…/e2e-slice2-selftest.log` |
| `SELFTEST=2` (only H's arrival flipped — the new leg) | **FAIL as designed, `EXIT:1`** | `…/e2e-slice2-selftest-entity.log` |
| `NEGATIVE=1` (leg I inverted: the item must move) | **FAIL as designed, `EXIT:1`** | `…/e2e-slice2-negative.log` |
| `check-e2e-logs.py create_hypertube-e2e --strict` | `logs=4 ok=4 missing-exit=0 bad-exit=0` | session |

Measured: player 0.5 blocks/tick → x = 223.0; villager 199.5 → 223.0 on the same path; item and
wither unmoved over 40 ticks; 16 tubes from `BGB/GG/BGB` with copper 16→12 and glass 16→12; 1
entrance with tube/iron/hopper each 1→0; nine copper crafts nothing; both blocks drop one of
themselves in survival; a sneaking player stays at 199.5 and rides once shift is released.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices
