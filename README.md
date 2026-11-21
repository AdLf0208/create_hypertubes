# Create: Hypertube for Horizon

Ride through glass tubes between two entrances. This is a Rust port of
[Create: Hypertube](https://github.com/PedroRok/CreateHypertubes) (Apache-2.0)
for [Horizon](https://github.com/horizon-rust/horizon), Minecraft 26.3.

## What this slice does

- **Hypertube** — place a line of tubes; they join along one axis and draw as
  glass where they connect.
- **Hypertube Entrance** — place it looking along the line you want to travel.
  Stand in the cell behind its mouth and it pulls you in.
- **Travel** — the ride carries you along the run at **0.5 blocks a tick** (the
  jar's speed at its minimum powered speed), and leaves you 1.5 blocks past the
  entrance at the far end. A run shorter than two tubes does nothing, and
  anything that is not a tube (a wall, air) ends the run where it stands.
- **Every living traveller** — a villager, a cow or any other living entity in the
  mouth rides too, as the jar's default `BLACKLIST` mode says: only
  `minecraft:wither` and `minecraft:ender_dragon` are refused. A spectator, and
  anyone holding sneak, are not pulled.

Both blocks are walk-through, craftable (copper, glass, iron, a hopper), and in
the creative menu under *Create: Hypertube*.

## What it does not do yet

- **No kinetic power.** Create's rotation network is not linkable, so an
  entrance always runs at its minimum powered speed and **accelerators are not
  ported**.
- **No curves, junctions or splitters** — a run is a straight line along one
  axis; a corner ends the ride.
- **No client half**: no detached camera, swim pose, suction particles or sound,
  and no tube renderer for curves.
- **No entity-list config or `traveller_entities` tag** — the default blacklist
  is the only mode, and `create:package` (Create is not carried) cannot ride.

The full list, with the reasons, is in [`notes.md`](notes.md); the upstream
behaviour it was built from is in [`FINDINGS.md`](FINDINGS.md).

## Install

One file: `create_hypertube.hmod`. It is the flat SDK package — the blocks, the
models, the textures, the recipes, the loot tables and the code all travel
inside it.

## Build it yourself

The package is built by the SDK's own tool, which fetches the pinned SDK into
`.horizon/sdk/` on first use:

```sh
cargo test                        # the pure travel rules and the glue's tests
cargo horizon-mod build           # -> target/horizon-mod/create_hypertube.hmod
cargo horizon-mod check create_hypertube.hmod
cargo horizon-mod fits create_hypertube.hmod --build 0a875da    # the pin
```

Building a **game** that carries it is the launcher's job
(`ports/tools/launcher-game.sh build create_hypertube`), not cargo's. The in-game
checks are in [`VALIDATION.md`](VALIDATION.md): `GAME=… CTL=… tools/e2e.sh`.

## Licence

The port's code and the carried assets are Apache-2.0, as upstream's are: see
[`LICENSE`](LICENSE) and [`LICENSE-NOTICE.md`](LICENSE-NOTICE.md). The original
art and audio belong to their author, "Rok".
