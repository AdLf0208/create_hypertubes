# Create: Hypertubes — a Horizon port

**Create: Hypertubes** is a Minecraft mod. Travel around the world with tubes!. This repository is a **port of it to [Horizon](https://github.com/horizon-rust/horizon)**, the Rust engine for Minecraft Java 26.3. It carries the complete source of the port plus the content files it ships, and installs as a single `.hmod` package.

Upstream: [PedroRok/CreateHypertubes](https://github.com/PedroRok/CreateHypertubes) — licence **Apache-2.0**.

| | |
|---|---|
| Upstream mod | Create: Hypertubes ([source](https://github.com/PedroRok/CreateHypertubes)) |
| Ported to | Horizon 0b14f8a, Minecraft Java 26.3, mod API `0.2` |
| Package | `create_hypertube.hmod` (install it with the Horizon launcher) |
| Licence | **Apache-2.0** — the upstream mod's licence; see [Licence and credit](#licence-and-credit) |

## What this port implements

### What this slice does

- **Hypertube** — place a line of tubes; they join along one axis and draw as
  glass where they connect.
- **Hypertube Entrance** — place it looking along the line you want to travel.
  Stand in the cell behind its mouth and it pulls you in.
- **Travel** — the ride carries you along the run at **0.5 blocks a tick** (the
  jar's speed at its minimum powered speed), and leaves you 1.5 blocks past the
  entrance at the far end. A run shorter than two tubes does nothing, and
  anything that is not a tube (a wall, air) ends the run where it stands.

Both blocks are walk-through, craftable (copper, glass, iron, a hopper), and in
the creative menu under *Create: Hypertube*.

## Not yet ported

- **Kinetic power.** Create's rotation network decides whether an entrance is
- **Accelerators, junctions, the funnel and the smart-tube attachments.**
- **Curves and turns.** Upstream joins tubes with bezier connections
- **The client half.** No detached camera, swim pose, suction particles or
- **Non-player travellers.** Only server players ride (villagers, fish and
- **Tube collision.** Upstream gives a tube a thin solid box and an empty one
- **Config, goggles tooltips, the `locked`/`has_block_in_front`/`waterlogged`/
- **No in-game run at `0b14f8a`** (the launcher/game build is absent). Every other claim here is

## Installing

1. Install the [Horizon launcher](https://github.com/horizon-rust/horizon/releases) (0.2.70 or newer).
2. Add `create_hypertube.hmod` to the instance's mods.
3. The package is pinned to a specific Horizon build; the launcher checks that pin.

## Licence and credit

Create: Hypertubes was created by its upstream authors; the code, models and assets in the original mod
remain theirs and are used here under **Apache-2.0**. The Rust in this repository is a clean-room
rewrite for Horizon, not a translation of the original source.

- `LICENSE` — the upstream licence text.
- `LICENSE-NOTICE.md` — what this port carries and where it came from.
- The upstream project: https://github.com/PedroRok/CreateHypertubes

## Technical details

```
horizon-mod.toml   package manifest (id, version, api, [native] pin)
Cargo.toml         the crate; depends on `horizon-mod-api` from the fetched SDK
src/               lib.rs (the one `impl Hooks`), runtime.rs (pure logic + tests), glue
assets/ data/      the content the package ships
tools/             content generators and the e2e scenario
```

- Build: `cargo horizon-mod build` (packages; it does not compile against the game).
- Test: `cargo test`, `cargo clippy --all-targets -- -D warnings`.
- In-game: `ports/tools/launcher-game.sh run create_hypertube` in the campaign tree, or install the
  `.hmod` and play; the harness scenario is `tools/e2e.sh`.

This repository is generated from the campaign's port at `ports/create_hypertube/`; the port's own
`notes.md` is the full record (decisions, traps, evidence).
