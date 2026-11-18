# Create: Hypertube — validation (slice 1)

> **History: the retired `.hnmod` bundle (0.1.0).** Everything below was run at pin
> `1d63e0a5` from the staging ladder (`tools/horizon.py`) and the embedded-content bundle, none of
> which exists any more. The current state — its ladder, package size/hash and the gap that no game
> was built at `0b14f8a` — is in [`notes.md`](notes.md) `## Migration verification (SDK 0b14f8a)`;
> the in-game transcripts below remain this port's only in-game evidence.

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
