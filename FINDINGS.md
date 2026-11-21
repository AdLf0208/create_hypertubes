# Create: Hypertube — findings (jar + upstream source)

Read before any code, per the brief. Everything below is measured from an
artefact: the pack's jar, or the public upstream repository. No decompilation.

## Licence (read from the jar, not a catalogue)

`META-INF/neoforge.mods.toml` in
`ports/_shared/licence-cache/create_hypertube-0.6.0-NEOFORGE.jar`
(SHA-256 `7bdb8979c7ff7d3b29f7a23771b6ae4870a6dcb7ce2e4a3214fdd6059aacace8`,
326 entries) declares:

```
modId = "create_hypertube"
version = "0.6.0"
license = "Apache License 2.0"
[[dependencies."create_hypertube"]] modId="create" type="required" versionRange="[6.0.4,6.1.0)"
```

**Apache-2.0, rank 0.** The jar ships no separate `LICENSE` file; the manifest
line is the mod's licence. `precheck-mod.py` still reports `exit 2 / licence not
read` because the campaign's `licence-precheck.csv` has no row for this mod —
the row is the orchestrator's to write, and the jar text above is the evidence.

## Jar inventory (326 entries, by family)

| Family | Entries | Notes |
|---|---|---|
| `com/pedrorok/hypertube/blocks/` | 17 classes | `HypertubeBlock`, `HyperEntranceBlock`, `HyperAcceleratorBlock`, `HyperJunctionBlock`, `TubeBlock`, `TubePathBlock`, `ActionTubeBlock` + their block entities |
| `…/core/` | 40 | travel (`TravelManager`, `TravelPathMover`, `TravelPathData`, `TravelConstants`), connections (`BezierConnection`, `SimpleConnection`), collision, camera, escape, smart-tube attachments |
| `…/client/` | 7 | models/renderers: `HypertubeBlockEntityRenderer`, `BezierTextureRenderer`, particles, outline |
| `…/config/` | 3 | `ServerConfig` (travel/entity lists/speed multiplier), `ClientConfig` |
| `…/mixin/` | 12 | player movement, camera, model, packet listener, Sable compat |
| `assets/create_hypertube/blockstates/` | 6 | `hypertube` (multipart), `hypertube_entrance` (facing × open), `hypertube_accelerator`, `hypertube_junction`, `tube_path`, `coghweel_hole` |
| `assets/create_hypertube/models/` | 33 | self-contained models: own textures only, **no `create:` parent or texture** |
| `assets/create_hypertube/textures/` | 22 | the port's own art (Apache-2.0 with the mod) |
| `assets/create_hypertube/lang/` | 9 | `en_us` plus 8 translations |
| `assets/create_hypertube/sounds/` | 2 + `sounds.json` | `suction.ogg`, `wind_tunnel.ogg` |
| `data/create_hypertube/horizon` (jar: recipes) | 7 | `hypertube`, `hypertube_entrance`, `hypertube_junction`, `hypertube_funnel`, `hyper_accelerator_small_cogwheel`, `redstone_detector_tube_attachment`, `sequenced_assembly/tube_scanner` |
| `data/create_hypertube/loot_table/blocks/` | 4 | all four blocks |
| `data/create_hypertube/advancement/recipes/misc/` | 6 | recipe unlock advancements |
| `data/create_hypertube/tags/entity_types/` | 1 | `traveller_entities` |
| `data/minecraft/tags/block/mineable/` | 2 | `pickaxe`, `axe` (both list all four blocks) |

The jar carries **no `items/*.json`** (1.21.1 era); 26.3 item definitions are
written by the port's carry script.

### The two blocks this slice is about

`assets/create_hypertube/blockstates/hypertube.json` — multipart on three axis
booleans and `connected`:

* `north_south`, `east_west`, `up_down` (booleans): which axis the tube runs on;
* `connected` (boolean): the tube holds a *managed* connection — `true` renders
  the glass `tube_part`, `false` the solid `tube_core`.

`assets/create_hypertube/blockstates/hypertube_entrance.json` — `facing`
(north/east/south/west/up/down) × `open` (boolean), six models each way.

`registry/ModBlocks.java:30-38` (upstream): `destroyTime 1.0f`,
`explosionResistance 10.0f`, `SoundType.METAL`, `noOcclusion()`,
`isViewBlocking → false`, `isSuffocating → false`. Items in both the pickaxe
and axe mineable tags (`axeOrPickaxe`).

`assets/create_hypertube/lang/en_us.json`: `block.create_hypertube.hypertube` =
"Hypertube Block", `block.create_hypertube.hypertube_entrance` = "Hypertube
Entrance Block", `itemGroup.create_hypertube` = "Create: Hypertube".

## Upstream repository

`https://github.com/PedroRok/CreateHypertubes` (Apache-2.0), cloned read-only at
**`c3b74f52437520b05868b5eb965dc54a45d27602`** (2026-07-30, `mod_version=0.6.0`,
`minecraft_version=1.21.1`, `create_version=6.0.10-281`) — the same version the
pack's jar was built from.

### Behaviour extracted (behaviour, not code)

| Behaviour | Where | Value |
|---|---|---|
| Minimum kinetic speed for an entrance to open and pull | `core/travel/TravelConstants.java:42` | `NEEDED_SPEED = 16` (RPM) |
| Travel speed from kinetic speed | `utils/TubeUtils.java:160-163` | `0.4333 * min(1, rpm/16) + rpm/240` blocks/tick — **0.5 blocks/tick at 16 rpm**, 0.5667 at 32, 1.5 at 256 |
| Speed multiplier config | `config/ServerConfig.java` | `speedMultiplier`, default 1.0, range 0.5–99 |
| Shortest run that travels | `TravelManager.java:82-88` | `travelPoints.size() < 3` → "too short", no travel |
| Path points | `TravelPathData.java:39-48` | entrance centre, then the cell one step along `FACING`, then each connected cell centre |
| Path cleanup | `TravelPathData.java:51-63` | a point closer than `sqrt(0.8)` to the previous is dropped |
| Entry cell | `parent/TravelInteractTubeBlockEntity.java:34,117-127` | `RADIUS = 1.0`; the entity in the cell **behind** the mouth (`pos + opposite(FACING)`) is pulled in |
| Entrance placement facing | `blocks/HyperEntranceBlock.java:82-110` | `player.getDirection()`, `UP` when looking above -45°, `DOWN` above +45° |
| Tube placement states | `blocks/HypertubeBlock.java:86-109` | `connected=true` + the axis of an adjacent tube, else the axis of `getPlacementFacing(player)`, `connected=false` |
| Tube neighbour states | `blocks/HypertubeBlock.java:186-200` | `north_south` = tube north or south; `east_west` only when not north/south; `up_down` only when neither |
| Exit position | `TravelManager.java:168-200` | last path point; at an entrance, the cell past it (`relative(FACING.getOpposite())`), then `+0.5` along the travel direction; the player leaves with `lastDir * max(speed, 1)` |
| Re-entry guard | `TravelManager.java:62-79,151-159` | `LAST_TRAVEL_TIME = now + 2000 ms`, `LAST_TRAVEL_BLOCKPOS`, and the last speed is added when re-entering within `1500 ms` of finishing |
| Entities that travel | `config/ServerConfig.java` `entityListMode` | default `BLACKLIST` of `wither`, `ender_dragon`; whitelist mode defaults to player/villager/wandering_trader/`create:package` |
| Curve/collision | `core/connection/BezierConnection.java`, `core/collision/TubeCollision.java` | tubes connect through bezier curves with a collision filler; the path is a polyline of block centres joined by those curves |
| Client half | `core/travel/client/*`, `client/*`, `mixin/core/*` | detached camera, swim pose, suction particles/sound, a bezier tube renderer, keybinds to escape |

## What the slice takes, and what it leaves

Nothing in the jar contradicts the brief's slice. Taken:

* the **hypertube** and **hypertube_entrance** blocks, their models, textures,
  blockstates, loot tables, lang and mineable tags;
* the **straight-run travel rule** with the jar's numbers: 16 rpm-equivalent
  speed (0.5 blocks/tick), the 3-point minimum, entry from the cell behind the
  mouth, exit past the far entrance, the 2,000 ms re-entry guard.

Left as gaps (recorded in `notes.md`):

* **kinetic power** (Create's rotation) — the parent is upstream and unlinkable
  (`ARCHITECTURE.md` §3, "No cross-mod API between ports"), so the entrance runs
  at the minimum powered speed instead of 0 (stopped) … 256 rpm;
* **curves and junctions** — a run is the maximal straight line of tubes; a
  turning tube ends it (`BezierConnection`, `HyperJunctionBlock`);
* **accelerators** (`hyper_accelerator`), the funnel, the smart-tube
  attachments (scanner, redstone detector), `tube_path`, `coghweel_hole`;
* **the client half** — detached camera, swim pose, suction particles and
  sound, the bezier tube renderer, escape keybind;
* ~~**non-player travellers** (villagers, fish, `create:package`)~~ — **carried in
  slice 2** (2026-11-21) under the jar's default `BLACKLIST` mode: every living
  kind except `minecraft:wither` and `minecraft:ender_dragon`. `create:package`
  cannot ride because Create itself is not carried, and the
  `traveller_entities` tag / other list modes / config file stay gaps;
* **tube collision along curves** (`tubeCollision` config);
* **config files** — defaults are constants.
