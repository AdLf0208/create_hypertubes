//! Create: Hypertube — the one `impl Hooks` at the crate root.
//!
//! Upstream's `HyperEntranceBlock.getStateForPlacement` and `HypertubeBlock.getState` are
//! [`BlockPart`] methods on the two carried blocks (`state_for_placement` and `update_shape`), and
//! the travel is the [`Hooks::server_tick`] hook: a run spans many blocks and a traveller, so no
//! single block owns it and it is not a Part.
//!
//! The rules themselves live in [`runtime`], byte-identical to the retired bundle's `runtime.rs`
//! and tested by `cargo test` without the game.

pub mod runtime;

use std::collections::BTreeMap;
use std::sync::{Mutex, MutexGuard};

use mod_api::{
    self, BlockKey, BlockPart, BlockPos, BlockState, EntityRef, Hooks, LevelHost, LevelRef,
    LevelTicksHost, Registrar, RegistrationContext, ServerHost, ServerTickEvent, ServerTickPhase,
    StateForPlacementEvent, UpdateShapeEvent,
};

use crate::runtime::{
    BLACKLISTED_TRAVELLERS, Cell, Dir, NEEDED_SPEED, REENTRY_TICKS, Ride, World, feet_cell,
    may_pull, may_travel, plan, starts_ride, sweep_due, travel_speed,
};

/// The tube block's id.
const TUBE: &str = "create_hypertube:hypertube";
/// The entrance block's id.
const ENTRANCE: &str = "create_hypertube:hypertube_entrance";
/// The property the entrance's mouth points along.
const FACING: &str = "facing";

/// The six faces, in the order the tube's side reads and the jar's `getState` walks them.
const FACES: [Dir; 6] = [
    Dir::North,
    Dir::East,
    Dir::South,
    Dir::West,
    Dir::Up,
    Dir::Down,
];

/// The tube's four block-state properties.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct TubeState {
    north_south: bool,
    east_west: bool,
    up_down: bool,
    connected: bool,
}

/// The jar's `HypertubeBlock.getState`: one axis at a time, in the order north/south, east/west,
/// up/down, and `connected` only on a real arm. `sides` says whether a tube or an entrance stands
/// on each face, `[north, east, south, west, up, down]`.
fn tube_state(sides: [bool; 6]) -> TubeState {
    let [north, east, south, west, up, down] = sides;
    let north_south = north || south;
    let east_west = (east || west) && !north_south;
    let up_down = (up || down) && !north_south && !east_west;
    TubeState {
        north_south,
        east_west,
        up_down,
        connected: north_south || east_west || up_down,
    }
}

/// What one cell holds, from the block's identity and an entrance's `facing` property. A state
/// without the property keeps the block's own default, north, as the jar's `DEFAULT_FACING` does.
fn cell_of(is_tube: bool, is_entrance: bool, facing: Option<&str>) -> Cell {
    if is_tube {
        Cell::Tube
    } else if is_entrance {
        Cell::Entrance(facing.and_then(Dir::from_name).unwrap_or(Dir::North))
    } else {
        Cell::Other
    }
}

/// One traveller's ride: the entity to move, and where along the run it is.
struct Rider {
    /// The traveller, whatever kind it is. A handle that stops resolving (the entity left,
    /// died or changed level) makes the next teleport refuse, which ends the ride.
    entity: EntityRef,
    ride: Ride,
}

/// What the port keeps between server ticks: the rides in progress, when each traveller's
/// last ride ended (the re-entry guard), and its own tick count.
#[derive(Default)]
struct State {
    /// Keyed by entity UUID, as the jar's `travelDataMap` is: a player and a villager ride
    /// the same path through the same table.
    rides: BTreeMap<u128, Rider>,
    finished: BTreeMap<u128, i64>,
    now: i64,
}

#[derive(Default)]
struct Mod {
    /// One `Mod` lives for the session (`#[mod_api::horizon_mod]` boxes a `Default`), so the ride
    /// table lives here rather than in a `static`.
    state: Mutex<State>,
}

impl Mod {
    fn state(&self) -> MutexGuard<'_, State> {
        self.state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
    }
}

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Attach the two shapes to the two carried blocks. Both are content blocks declared in this
    /// package's `data/create_hypertube/horizon/block/`, so their keys exist when mods register.
    fn register(&self, r: &mut dyn Registrar, _context: &RegistrationContext) {
        let tube = r.block_key(TUBE);
        let entrance = r.block_key(ENTRANCE);
        r.block_part(tube, TubeShape { tube, entrance });
        r.block_part(entrance, EntranceShape);
    }

    /// At the end of a running server tick: move every ride one tick along, then let the
    /// entrances pull in whoever stands in their mouth. The retired bundle did the same from
    /// this hook and only knew players; the jar's rule is every living kind the default
    /// blacklist allows, so the travellers are the server's players plus, on a sweep, the
    /// level's other living entities (a run belongs to no single block here, so no Part can
    /// be ticked instead).
    fn server_tick(&self, host: &mut dyn ServerHost, event: &mut ServerTickEvent<'_>) {
        match event.phase {
            ServerTickPhase::ServerTickEnd {
                world_running: true,
            } => {}
            _ => return,
        }
        let Some(tube) = host.block_key(TUBE) else {
            return;
        };
        let Some(entrance) = host.block_key(ENTRANCE) else {
            return;
        };
        let mut state = self.state();
        state.now += 1;
        let now = state.now;
        advance_rides(host, &mut state, now);
        // The guard only has to outlive its own ticks; a busy tube would otherwise keep one
        // entry per traveller that ever rode.
        state.finished.retain(|_, at| now - *at < REENTRY_TICKS);
        pull_travellers(host, &mut state, tube, entrance);
    }
}

/// Move every ride one tick along its path. A ride ends when the path is spent or the game
/// refuses the teleport (a stale handle: the traveller left, died, or changed level).
fn advance_rides(host: &mut dyn ServerHost, state: &mut State, now: i64) {
    let mut ended: Vec<u128> = Vec::new();
    for (uuid, rider) in state.rides.iter_mut() {
        rider.ride.advance();
        let going = !rider.ride.finished();
        let at = rider.ride.position();
        if !rider.entity.teleport_to(host, at, None) || !going {
            ended.push(*uuid);
        }
    }
    for uuid in ended {
        state.rides.remove(&uuid);
        state.finished.insert(uuid, now);
    }
}

/// Start a ride for every traveller standing in an entrance's mouth: the server's players
/// every tick, and — on a [`sweep_due`] tick — every other living entity in a player's
/// level. A content block cannot carry a block entity at this pin, so the entrance cannot
/// tick itself as the jar's does; the sweep is that tick, at a fixed cadence.
fn pull_travellers(
    host: &mut dyn ServerHost,
    state: &mut State,
    tube: BlockKey,
    entrance: BlockKey,
) {
    let players = host.players().server_players();
    let player_entities: Vec<EntityRef> = players.iter().map(|player| player.entity()).collect();
    let mut candidates: Vec<(EntityRef, LevelRef)> = Vec::with_capacity(players.len());
    for player in &players {
        if let Some(level) = player.level(host) {
            candidates.push((player.entity(), level));
        }
    }
    if sweep_due(state.now) {
        let mut levels: Vec<LevelRef> = Vec::new();
        for (_, level) in &candidates {
            if !levels.contains(level) {
                levels.push(*level);
            }
        }
        for level in levels {
            let Some(entities) = level.all_entities(host) else {
                continue;
            };
            for entity in entities {
                // The players are already candidates, and only a living entity rides.
                if player_entities.contains(&entity) || host.living(entity).is_none() {
                    continue;
                }
                candidates.push((entity, level));
            }
        }
    }
    for (entity, level) in candidates {
        let Some(uuid) = entity.uuid(host) else {
            continue;
        };
        if state.rides.contains_key(&uuid) {
            continue;
        }
        let kind = entity.kind(host).map_or(String::new(), |key| key.id(host));
        let spectator = entity.spectator(host).unwrap_or(false);
        if !may_travel(&kind, spectator, &BLACKLISTED_TRAVELLERS) {
            continue;
        }
        let sneaking = entity.is_shift_key_down(host).unwrap_or(false);
        if !may_pull(state.now, state.finished.get(&uuid).copied(), sneaking) {
            continue;
        }
        let Some(position) = entity.position(host) else {
            continue;
        };
        let feet = feet_cell(position);
        let run = {
            let mut cells = Cells {
                host: &*host,
                level,
                tube,
                entrance,
            };
            let Some((mouth, facing)) = entrance_at(feet, &mut cells) else {
                continue;
            };
            plan(mouth, facing, &mut cells)
        };
        let Some(run) = run else {
            continue;
        };
        state.rides.insert(
            uuid,
            Rider {
                entity,
                ride: Ride::start(position, &run, travel_speed(NEEDED_SPEED)),
            },
        );
    }
}

/// The truth about one level's blocks, as a run walk reads them.
struct Cells<'a> {
    host: &'a dyn ServerHost,
    level: LevelRef,
    tube: BlockKey,
    entrance: BlockKey,
}

impl World for Cells<'_> {
    fn cell(&mut self, pos: [i32; 3]) -> Cell {
        let Some(block) = self.level.block(self.host, pos) else {
            // An unloaded cell ends the run, as air does.
            return Cell::Other;
        };
        let is_entrance = block == self.entrance;
        let facing = if is_entrance {
            self.level.block_property(self.host, pos, FACING)
        } else {
            None
        };
        cell_of(block == self.tube, is_entrance, facing.as_deref())
    }
}

/// The entrance whose mouth holds `feet`, with the face its tube runs along.
fn entrance_at(feet: [i32; 3], cells: &mut impl World) -> Option<([i32; 3], Dir)> {
    for dir in FACES {
        let neighbour = add(feet, dir.step());
        if let Cell::Entrance(facing) = cells.cell(neighbour)
            && starts_ride(feet, neighbour, facing)
        {
            return Some((neighbour, facing));
        }
    }
    None
}

/// The tube's own shape: a placed tube takes its axis from the blocks beside it, and a neighbour
/// that changes leaves it on one axis fewer or more (the jar's `getState` over vanilla's
/// `getStateForPlacement` and `updateShape`).
struct TubeShape {
    tube: BlockKey,
    entrance: BlockKey,
}

impl TubeShape {
    /// Whether a state is one the run continues through: a tube or an entrance.
    fn is_run(&self, state: BlockState) -> bool {
        state.block() == self.tube || state.block() == self.entrance
    }

    /// The tube's own state for the six faces around `pos`, with `changed` (whose new state is
    /// `neighbour`) substituted for one of them.
    fn shape(
        &self,
        level: &dyn LevelHost,
        pos: [i32; 3],
        state: BlockState,
        changed: Option<(Dir, BlockState)>,
    ) -> Option<BlockState> {
        let mut sides = [false; 6];
        for (index, dir) in FACES.into_iter().enumerate() {
            sides[index] = match changed {
                Some((at, neighbour)) if at == dir => self.is_run(neighbour),
                _ => level
                    .block_state(add(pos, dir.step()))
                    .is_some_and(|there| self.is_run(there)),
            };
        }
        let shape = tube_state(sides);
        let mut shaped = state;
        for (key, value) in [
            ("north_south", shape.north_south),
            ("east_west", shape.east_west),
            ("up_down", shape.up_down),
            ("connected", shape.connected),
        ] {
            shaped =
                level.state_with_property(shaped, key, if value { "true" } else { "false" })?;
        }
        Some(shaped)
    }
}

#[mod_api::horizon_part]
impl BlockPart for TubeShape {
    /// `HypertubeBlock.getStateForPlacement`: the tube joins whatever tube or entrance stands
    /// beside the cell it goes into.
    fn state_for_placement(
        &self,
        level: &dyn LevelHost,
        event: &mut StateForPlacementEvent<'_>,
    ) -> Option<Option<BlockState>> {
        let pos = xyz(event.context.pos);
        Some(Some(self.shape(level, pos, event.state, None)?))
    }

    /// `HypertubeBlock.neighborChanged` as vanilla expresses it: the state the tube takes now that
    /// its neighbour on `event.direction` is `event.neighbour`. Answering only when it differs
    /// keeps a neighbour update from writing the same state back.
    fn update_shape(
        &self,
        level: &mut dyn LevelTicksHost,
        event: &mut UpdateShapeEvent,
    ) -> Option<BlockState> {
        let pos = xyz(event.pos);
        let changed = (direction(event.direction), event.neighbour);
        let shaped = self.shape(level, pos, event.state, Some(changed))?;
        (shaped != event.state).then_some(shaped)
    }
}

/// The entrance's own shape: a placed entrance takes the face its placer looks along
/// (`HyperEntranceBlock.getStateForPlacement`).
struct EntranceShape;

#[mod_api::horizon_part]
impl BlockPart for EntranceShape {
    fn state_for_placement(
        &self,
        level: &dyn LevelHost,
        event: &mut StateForPlacementEvent<'_>,
    ) -> Option<Option<BlockState>> {
        let looked = Dir::from_look(event.context.yaw, event.context.pitch);
        let state = level.state_with_property(event.state, FACING, looked.name())?;
        Some(Some(state))
    }
}

/// The `mod_api` face for one of the runtime's own.
fn direction(face: mod_api::Direction) -> Dir {
    match face {
        mod_api::Direction::North => Dir::North,
        mod_api::Direction::East => Dir::East,
        mod_api::Direction::South => Dir::South,
        mod_api::Direction::West => Dir::West,
        mod_api::Direction::Up => Dir::Up,
        mod_api::Direction::Down => Dir::Down,
    }
}

fn xyz(pos: BlockPos) -> [i32; 3] {
    [pos.x, pos.y, pos.z]
}

fn add([x, y, z]: [i32; 3], [dx, dy, dz]: [i32; 3]) -> [i32; 3] {
    [x + dx, y + dy, z + dz]
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Which faces hold a tube or an entrance, `[north, east, south, west, up, down]`.
    fn sides(north: bool, east: bool, south: bool, west: bool, up: bool, down: bool) -> [bool; 6] {
        [north, east, south, west, up, down]
    }

    #[test]
    fn the_first_axis_with_a_neighbour_wins() {
        let lone = tube_state(sides(false, false, false, false, false, false));
        assert!(!lone.north_south && !lone.east_west && !lone.up_down && !lone.connected);

        let ns = tube_state(sides(true, false, false, false, false, false));
        assert!(ns.north_south && !ns.east_west && !ns.up_down && ns.connected);

        // north/south outranks east/west (west here) and up/down.
        let ns_wins = tube_state(sides(true, false, false, true, true, false));
        assert!(ns_wins.north_south && !ns_wins.east_west && !ns_wins.up_down && ns_wins.connected);
        // east/west outranks up/down.
        let ew_wins = tube_state(sides(false, true, false, false, true, false));
        assert!(!ew_wins.north_south && ew_wins.east_west && !ew_wins.up_down && ew_wins.connected);
        let ud = tube_state(sides(false, false, false, false, false, true));
        assert!(!ud.north_south && !ud.east_west && ud.up_down && ud.connected);
        // Both arms of one axis are one axis.
        let ns_both = tube_state(sides(true, false, true, false, false, false));
        assert!(ns_both.north_south && ns_both.connected);
    }

    #[test]
    fn a_cell_is_read_by_its_id_and_its_facing() {
        assert_eq!(cell_of(true, false, None), Cell::Tube);
        assert_eq!(
            cell_of(false, true, Some("east")),
            Cell::Entrance(Dir::East)
        );
        // A state without the property keeps the block's own default, north.
        assert_eq!(cell_of(false, true, None), Cell::Entrance(Dir::North));
        assert_eq!(cell_of(false, false, None), Cell::Other);
        assert_eq!(cell_of(false, false, Some("up")), Cell::Other);
    }

    #[test]
    fn every_face_round_trips() {
        for dir in FACES {
            assert_eq!(direction(face_of(dir)), dir, "{dir:?}");
            assert_eq!(direction(face_of(dir.opposite())), dir.opposite());
        }
    }

    /// The `mod_api` face of one of the runtime's, for the round-trip above.
    fn face_of(dir: Dir) -> mod_api::Direction {
        match dir {
            Dir::North => mod_api::Direction::North,
            Dir::East => mod_api::Direction::East,
            Dir::South => mod_api::Direction::South,
            Dir::West => mod_api::Direction::West,
            Dir::Up => mod_api::Direction::Up,
            Dir::Down => mod_api::Direction::Down,
        }
    }
}
