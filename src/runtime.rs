// Create: Hypertube — the straight-run travel rules (standalone crate lib,
// injected as `crate::game::create_hypertube`). No game access lives here.
//
// Every rule and number below was read from the jar's upstream source
// (PedroRok/CreateHypertubes, `c3b74f52`, Apache-2.0) and is recorded in
// FINDINGS.md:
//
// * `TravelConstants.java:42` — `NEEDED_SPEED = 16` rpm is the least kinetic
//   speed at which an entrance opens and pulls;
// * `TubeUtils.java:160-163` — `travel_speed(rpm) = 0.4333 * min(1, rpm/16) +
//   rpm/240` blocks a tick, so 0.5 blocks a tick at the minimum;
// * `TravelManager.java:82-88` — a run of fewer than three path points is too
//   short to travel;
// * `TravelPathData.java:39-63` — the path is the entrance centre, then each
//   connected cell centre along one axis, with points nearer than sqrt(0.8)
//   dropped;
// * `TravelManager.java:168-200` — the traveller leaves 1.5 blocks past a far
//   entrance's centre, half a block past a plain tube's;
// * `parent/TravelInteractTubeBlockEntity.java:117-127` — the entity is pulled
//   from the cell *behind* the mouth (`pos + opposite(FACING)`);
// * `TravelManager.java:62-79,151-159` — a 2,000 ms re-entry guard after a
//   travel ends.

/// The least kinetic speed that opens an entrance (`NEEDED_SPEED`); a slice
/// with no kinetic network rides at `travel_speed(NEEDED_SPEED)`, 0.5 blocks a
/// tick to the jar's own precision.
pub const NEEDED_SPEED: f32 = 16.0;
/// A run shorter than this many path points does not travel.
pub const MIN_POINTS: usize = 3;
/// How far past a far entrance's centre the traveller leaves it.
pub const EXIT_PAST_ENTRANCE: f64 = 1.5;
/// How far past a plain tube's centre the traveller leaves it.
pub const EXIT_PAST_TUBE: f64 = 0.5;
/// A start this close to the first point adds no segment of its own, so a
/// traveller already in the mouth leaves forwards rather than backwards.
pub const NEAR_POINT_SQ: f64 = 0.8;
/// Server ticks the entrance stays shut after a travel ends (2,000 ms).
pub const REENTRY_TICKS: i64 = 40;

/// The jar's travel speed for a tube network's kinetic speed, blocks a tick.
pub fn travel_speed(rpm: f32) -> f64 {
    let rpm = f64::from(if rpm.is_finite() { rpm } else { 0.0 }).max(0.0);
    0.4333 * (rpm / f64::from(NEEDED_SPEED)).min(1.0) + rpm / 240.0
}

/// One of the six faces a tube runs along, named as a block state names it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dir {
    North,
    East,
    South,
    West,
    Up,
    Down,
}

impl Dir {
    /// The state value's name, as vanilla's `Direction.getSerializedName`.
    pub fn name(self) -> &'static str {
        match self {
            Dir::North => "north",
            Dir::East => "east",
            Dir::South => "south",
            Dir::West => "west",
            Dir::Up => "up",
            Dir::Down => "down",
        }
    }

    /// The direction a state value names; `None` for anything else.
    pub fn from_name(name: &str) -> Option<Dir> {
        match name {
            "north" => Some(Dir::North),
            "east" => Some(Dir::East),
            "south" => Some(Dir::South),
            "west" => Some(Dir::West),
            "up" => Some(Dir::Up),
            "down" => Some(Dir::Down),
            _ => None,
        }
    }

    /// One block along this direction, as vanilla places it (north is -Z).
    pub fn step(self) -> [i32; 3] {
        match self {
            Dir::North => [0, 0, -1],
            Dir::East => [1, 0, 0],
            Dir::South => [0, 0, 1],
            Dir::West => [-1, 0, 0],
            Dir::Up => [0, 1, 0],
            Dir::Down => [0, -1, 0],
        }
    }

    /// One block along this direction, as a position offset.
    pub fn offset(self) -> [f64; 3] {
        let [x, y, z] = self.step();
        [f64::from(x), f64::from(y), f64::from(z)]
    }

    /// The face facing this one.
    pub fn opposite(self) -> Dir {
        match self {
            Dir::North => Dir::South,
            Dir::East => Dir::West,
            Dir::South => Dir::North,
            Dir::West => Dir::East,
            Dir::Up => Dir::Down,
            Dir::Down => Dir::Up,
        }
    }

    /// The side the tube runs along for this face: `north_south`, `east_west` or
    /// `up_down`, as the jar's block state names its three axis booleans.
    pub fn axis(self) -> &'static str {
        match self {
            Dir::North | Dir::South => "north_south",
            Dir::East | Dir::West => "east_west",
            Dir::Up | Dir::Down => "up_down",
        }
    }

    /// The face a player placing a block looks along: yaw in degrees picks the
    /// horizontal face (`Direction.fromYRot`), looking beyond 45 degrees up or
    /// down picks `Up`/`Down` (`HyperEntranceBlock.getStateForPlacement`).
    pub fn from_look(yaw: f32, pitch: f32) -> Dir {
        if pitch < -45.0 {
            return Dir::Up;
        }
        if pitch > 45.0 {
            return Dir::Down;
        }
        // Vanilla's `ROTATION_BY_CLOCKWISE_ORDER`: 0 = south, 90 = west.
        match ((yaw / 90.0 + 0.5).floor() as i64).rem_euclid(4) {
            0 => Dir::South,
            1 => Dir::West,
            2 => Dir::North,
            _ => Dir::East,
        }
    }
}

/// What the world holds at one cell, as the run walk needs it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cell {
    /// A `create_hypertube:hypertube` block.
    Tube,
    /// A `create_hypertube:hypertube_entrance` block, and the face it points.
    Entrance(Dir),
    /// Anything else, the air included: the run stops before it.
    Other,
}

/// The blocks a run walk reads. `None` from a read means "not loaded".
pub trait World {
    /// The cell at `pos`.
    fn cell(&mut self, pos: [i32; 3]) -> Cell;
}

/// A run of tubes from an entrance to where it ends.
#[derive(Clone, Debug, PartialEq)]
pub struct Run {
    /// Block centres from the entrance outwards, the far entrance included.
    pub points: Vec<[f64; 3]>,
    /// Where the traveller leaves the tube.
    pub exit: [f64; 3],
    /// The entrance block the run was walked from.
    pub entrance: [i32; 3],
    /// Whether the run ends at a second entrance rather than at a bare tube.
    pub ends_at_entrance: bool,
}

/// The centre of a block cell, as `BlockPos.getCenter`.
pub fn centre([x, y, z]: [i32; 3]) -> [f64; 3] {
    [f64::from(x) + 0.5, f64::from(y) + 0.5, f64::from(z) + 0.5]
}

/// Walk the straight run of tubes one step along `facing` from `entrance`.
///
/// `None` when the run is shorter than [`MIN_POINTS`], as the jar refuses a
/// too-short run. The walk never turns: a corner's tube is the last point.
pub fn plan(entrance: [i32; 3], facing: Dir, world: &mut impl World) -> Option<Run> {
    let step = facing.step();
    let mut points = vec![centre(entrance)];
    let mut cell = add(entrance, step);
    let mut last_tube = None;
    let mut ends_at_entrance = false;
    let mut exit = None;
    loop {
        match world.cell(cell) {
            Cell::Tube => {
                points.push(centre(cell));
                last_tube = Some(cell);
                cell = add(cell, step);
            }
            Cell::Entrance(_) if last_tube.is_some() => {
                points.push(centre(cell));
                ends_at_entrance = true;
                exit = Some(addf(
                    centre(cell),
                    scale(facing.offset(), EXIT_PAST_ENTRANCE),
                ));
                break;
            }
            _ => break,
        }
    }
    if points.len() < MIN_POINTS {
        return None;
    }
    let exit = exit.unwrap_or_else(|| {
        let last = last_tube.unwrap_or(entrance);
        addf(centre(last), scale(facing.offset(), EXIT_PAST_TUBE))
    });
    Some(Run {
        points,
        exit,
        entrance,
        ends_at_entrance,
    })
}

/// The cell an entrance pulls a traveller from: the one behind its mouth.
pub fn entry_cell(entrance: [i32; 3], facing: Dir) -> [i32; 3] {
    add(entrance, facing.opposite().step())
}

/// Whether a traveller standing in `cell` is in `entrance`'s mouth.
pub fn starts_ride(cell: [i32; 3], entrance: [i32; 3], facing: Dir) -> bool {
    entry_cell(entrance, facing) == cell
}

/// Whether an entrance may pull a traveller at server tick `now`, given when
/// the last travel ended (`None` for one that never has).
pub fn may_enter(now: i64, last_finished: Option<i64>) -> bool {
    last_finished.is_none_or(|finished| now - finished >= REENTRY_TICKS)
}

/// One traveller's ride along a run.
#[derive(Clone, Debug, PartialEq)]
pub struct Ride {
    points: Vec<[f64; 3]>,
    segment: usize,
    travelled: f64,
    speed: f64,
    finished: bool,
}

impl Ride {
    /// Start a ride at `from` (where the traveller stands) along `run`, moving
    /// `speed` blocks a tick.
    ///
    /// The path is the traveller's own position, then the run's points, then the
    /// exit: a straight run's points are a block apart, so the jar's near-point
    /// cleanup (which exists for curve points) never drops one here. A start on
    /// the mouth's own centre adds no segment, as the jar's `currentStart` does.
    pub fn start(from: [f64; 3], run: &Run, speed: f64) -> Ride {
        let mut points = vec![from];
        if distance_sq(from, run.points[0]) >= NEAR_POINT_SQ {
            points.extend(run.points.iter().copied());
        } else {
            points.extend(run.points.iter().skip(1).copied());
        }
        points.push(run.exit);
        let speed = if speed.is_finite() {
            speed.max(0.0)
        } else {
            0.0
        };
        Ride {
            finished: points.len() < 2 || speed <= 0.0,
            points,
            segment: 0,
            travelled: 0.0,
            speed,
        }
    }

    /// The traveller's position now, along the path's polyline.
    pub fn position(&self) -> [f64; 3] {
        let Some(start) = self.points.get(self.segment) else {
            return [0.0; 3];
        };
        let Some(end) = self.points.get(self.segment + 1) else {
            return *start;
        };
        let length = distance(*start, *end);
        if length <= f64::EPSILON {
            return *end;
        }
        let t = (self.travelled / length).clamp(0.0, 1.0);
        [
            start[0] + (end[0] - start[0]) * t,
            start[1] + (end[1] - start[1]) * t,
            start[2] + (end[2] - start[2]) * t,
        ]
    }

    /// Move one tick along the path. False once the ride has finished (and on
    /// every later call), true while it is still going.
    pub fn advance(&mut self) -> bool {
        if self.finished {
            return false;
        }
        let mut remaining = self.speed;
        while remaining > 0.0 && self.segment + 1 < self.points.len() {
            let start = self.points[self.segment];
            let end = self.points[self.segment + 1];
            let length = distance(start, end);
            let left = length - self.travelled;
            if remaining < left {
                self.travelled += remaining;
                remaining = 0.0;
            } else {
                remaining -= left.max(0.0);
                self.segment += 1;
                self.travelled = 0.0;
            }
        }
        if self.segment + 1 >= self.points.len() {
            self.finished = true;
        }
        !self.finished
    }

    /// Whether the traveller has reached the run's end.
    pub fn finished(&self) -> bool {
        self.finished
    }
}

fn add([x, y, z]: [i32; 3], [dx, dy, dz]: [i32; 3]) -> [i32; 3] {
    [x + dx, y + dy, z + dz]
}

fn addf([x, y, z]: [f64; 3], [dx, dy, dz]: [f64; 3]) -> [f64; 3] {
    [x + dx, y + dy, z + dz]
}

fn scale([x, y, z]: [f64; 3], by: f64) -> [f64; 3] {
    [x * by, y * by, z * by]
}

fn distance(a: [f64; 3], b: [f64; 3]) -> f64 {
    distance_sq(a, b).sqrt()
}

fn distance_sq(a: [f64; 3], b: [f64; 3]) -> f64 {
    let dx = a[0] - b[0];
    let dy = a[1] - b[1];
    let dz = a[2] - b[2];
    dx * dx + dy * dy + dz * dz
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A straight line of cells: `cells` maps a position to what it holds.
    struct Row {
        cells: Vec<([i32; 3], Cell)>,
    }

    impl Row {
        fn new(cells: Vec<([i32; 3], Cell)>) -> Row {
            Row { cells }
        }
    }

    impl World for Row {
        fn cell(&mut self, pos: [i32; 3]) -> Cell {
            self.cells
                .iter()
                .find(|(at, _)| *at == pos)
                .map_or(Cell::Other, |(_, cell)| *cell)
        }
    }

    /// The speed the glue rides at: the jar's own number at the minimum speed.
    const SPEED: f64 = 0.5;

    fn tubes(from_x: i32, count: i32) -> Vec<([i32; 3], Cell)> {
        (from_x..from_x + count)
            .map(|x| ([x, 5, 0], Cell::Tube))
            .collect()
    }

    #[test]
    fn speed_is_the_jars_curve() {
        assert!((travel_speed(NEEDED_SPEED) - 0.5).abs() < 1e-4);
        assert!((travel_speed(32.0) - 0.5667).abs() < 1e-3);
        // The jar's 0.4333 constant leaves 256 rpm at 1.49997, not exactly 1.5.
        assert!((travel_speed(256.0) - 1.5).abs() < 1e-3);
        assert!((travel_speed(8.0) - 0.25).abs() < 1e-3);
        // Below the minimum, an entrance never opens: the curve still answers.
        assert!(travel_speed(0.0) < 1e-6);
        assert_eq!(travel_speed(f32::NAN), 0.0);
    }

    #[test]
    fn dir_names_round_trip() {
        for dir in [
            Dir::North,
            Dir::East,
            Dir::South,
            Dir::West,
            Dir::Up,
            Dir::Down,
        ] {
            assert_eq!(Dir::from_name(dir.name()), Some(dir));
            assert_eq!(Dir::from_name(dir.name()).unwrap().step(), dir.step());
            assert_eq!(dir.opposite().opposite(), dir);
        }
        assert_eq!(Dir::from_name("northeast"), None);
    }

    #[test]
    fn placement_facing_follows_the_look() {
        // Yaw 0 looks south (+Z); 90 west; 180 north; 270 east.
        assert_eq!(Dir::from_look(0.0, 0.0), Dir::South);
        assert_eq!(Dir::from_look(90.0, 0.0), Dir::West);
        assert_eq!(Dir::from_look(-90.0, 0.0), Dir::East);
        assert_eq!(Dir::from_look(180.0, 0.0), Dir::North);
        assert_eq!(Dir::from_look(-180.0, 0.0), Dir::North);
        assert_eq!(Dir::from_look(0.0, -60.0), Dir::Up);
        assert_eq!(Dir::from_look(0.0, 60.0), Dir::Down);
        // 22.5 degrees rounds to south, 67.5 to west.
        assert_eq!(Dir::from_look(22.5, 0.0), Dir::South);
        assert_eq!(Dir::from_look(67.5, 0.0), Dir::West);
    }

    #[test]
    fn a_run_of_tubes_ends_at_the_last_tube() {
        let entrance = [-1, 5, 0];
        let mut world = Row::new(tubes(0, 4));
        let run = plan(entrance, Dir::East, &mut world).expect("a four-tube run");
        assert_eq!(run.points.len(), 5);
        assert_eq!(run.points[0], centre(entrance));
        assert_eq!(run.points[4], centre([3, 5, 0]));
        assert!(!run.ends_at_entrance);
        assert_eq!(run.exit, [3.5 + EXIT_PAST_TUBE, 5.5, 0.5]);
    }

    #[test]
    fn a_run_between_two_entrances_leaves_past_the_far_one() {
        let entrance = [-1, 5, 0];
        let mut cells = tubes(0, 2);
        cells.push(([2, 5, 0], Cell::Entrance(Dir::West)));
        let mut world = Row::new(cells);
        let run = plan(entrance, Dir::East, &mut world).expect("a run with a far entrance");
        assert_eq!(run.points.len(), 4);
        assert!(run.ends_at_entrance);
        assert_eq!(run.points[3], centre([2, 5, 0]));
        // 1.5 blocks past the far entrance's centre, along the travel direction.
        assert_eq!(run.exit, [2.5 + EXIT_PAST_ENTRANCE, 5.5, 0.5]);
    }

    #[test]
    fn a_too_short_run_does_not_travel() {
        let entrance = [-1, 5, 0];
        let mut world = Row::new(tubes(0, 1));
        assert_eq!(plan(entrance, Dir::East, &mut world), None);
        // Two entrances face to face with nothing between them: still too short.
        let mut world = Row::new(vec![([0, 5, 0], Cell::Entrance(Dir::West))]);
        assert_eq!(plan(entrance, Dir::East, &mut world), None);
        // A mouth facing the air.
        let mut world = Row::new(Vec::new());
        assert_eq!(plan(entrance, Dir::East, &mut world), None);
    }

    #[test]
    fn a_solid_wall_stops_the_run() {
        let entrance = [-1, 5, 0];
        let mut cells = tubes(0, 2);
        cells.push(([2, 5, 0], Cell::Other));
        cells.push(([3, 5, 0], Cell::Tube));
        let mut world = Row::new(cells);
        let run = plan(entrance, Dir::East, &mut world).expect("two tubes before the wall");
        assert_eq!(run.points.len(), 3);
        assert_eq!(run.points[2], centre([1, 5, 0]));
        assert_eq!(run.exit, [1.5 + EXIT_PAST_TUBE, 5.5, 0.5]);
    }

    #[test]
    fn a_run_never_turns() {
        let entrance = [-1, 5, 0];
        let mut cells = tubes(0, 2);
        // A corner tube one block south of the run: it is not on our line.
        cells.push(([2, 5, 1], Cell::Tube));
        cells.push(([2, 5, 0], Cell::Tube));
        let mut world = Row::new(cells);
        let run = plan(entrance, Dir::East, &mut world).expect("the straight part");
        assert_eq!(run.points.len(), 4);
        assert_eq!(run.points[3], centre([2, 5, 0]));
        assert_eq!(run.exit, [2.5 + EXIT_PAST_TUBE, 5.5, 0.5]);
    }

    #[test]
    fn a_vertical_run_exits_downwards() {
        let entrance = [0, 20, 0];
        let mut cells: Vec<([i32; 3], Cell)> =
            (0..2).map(|i| ([0, 19 - i, 0], Cell::Tube)).collect();
        cells.push(([0, 17, 0], Cell::Entrance(Dir::Up)));
        let mut world = Row::new(cells);
        let run = plan(entrance, Dir::Down, &mut world).expect("a downward run");
        assert_eq!(run.points.len(), 4);
        assert_eq!(run.exit, [0.5, 17.5 - EXIT_PAST_ENTRANCE, 0.5]);
    }

    #[test]
    fn a_ride_advances_the_jars_speed_a_tick() {
        let entrance = [-1, 5, 0];
        let mut cells = tubes(0, 2);
        cells.push(([2, 5, 0], Cell::Entrance(Dir::West)));
        let mut world = Row::new(cells);
        let run = plan(entrance, Dir::East, &mut world).expect("a run");
        // A traveller already in the mouth: the path is the three tubes plus the
        // 1.5-block exit, 4.5 blocks at 0.5 a tick.
        let mut ride = Ride::start(centre(entrance), &run, SPEED);
        assert!(!ride.finished());
        assert!(ride.advance());
        let after_one = ride.position();
        assert!((after_one[0] - 0.0).abs() < 1e-9, "{after_one:?}");
        assert!((after_one[1] - 5.5).abs() < 1e-9, "{after_one:?}");
        let mut ticks = 1;
        loop {
            ticks += 1;
            if !ride.advance() {
                break;
            }
            assert!(ticks < 1000, "the ride never finished");
        }
        assert_eq!(ticks, 9, "4.5 blocks at 0.5 a tick");
        assert_eq!(ride.position(), run.exit);
        assert!(ride.finished());
        // Finished rides stay finished.
        assert!(!ride.advance());
        assert_eq!(ride.position(), run.exit);
    }

    #[test]
    fn a_ride_never_overshoots_its_end() {
        let entrance = [-1, 5, 0];
        let mut world = Row::new(tubes(0, 3));
        let run = plan(entrance, Dir::East, &mut world).expect("a run");
        let mut ride = Ride::start(centre(entrance), &run, 100.0);
        assert!(!ride.advance());
        assert!(ride.finished());
        assert_eq!(ride.position(), run.exit);
    }

    #[test]
    fn a_traveller_behind_the_mouth_starts_from_where_they_stand() {
        let entrance = [-1, 5, 0];
        let mut world = Row::new(tubes(0, 3));
        let run = plan(entrance, Dir::East, &mut world).expect("a run");
        // The entry cell's centre: one block behind the mouth, feet on the floor.
        let start = centre(entry_cell(entrance, Dir::East));
        let start = [start[0], 5.0, start[2]];
        let mut ride = Ride::start(start, &run, SPEED);
        assert_eq!(ride.position(), start);
        assert!(ride.advance());
        let after_one = ride.position();
        // 0.5 of the 1.118-block pull to the mouth, along it: x rises, y rises.
        assert!(after_one[0] > start[0] && after_one[0] < centre(entrance)[0]);
        assert!(after_one[1] > start[1] && after_one[1] < centre(entrance)[1]);
    }

    #[test]
    fn a_ride_at_no_speed_does_not_hang() {
        let entrance = [-1, 5, 0];
        let mut world = Row::new(tubes(0, 3));
        let run = plan(entrance, Dir::East, &mut world).expect("a run");
        let mut ride = Ride::start(centre(entrance), &run, 0.0);
        assert!(ride.finished());
        assert!(!ride.advance());
    }

    #[test]
    fn the_mouth_is_the_cell_behind_the_entrance() {
        let entrance = [4, 6, 4];
        assert_eq!(entry_cell(entrance, Dir::East), [3, 6, 4]);
        assert_eq!(entry_cell(entrance, Dir::North), [4, 6, 5]);
        assert_eq!(entry_cell(entrance, Dir::Down), [4, 7, 4]);
        assert!(starts_ride([3, 6, 4], entrance, Dir::East));
        assert!(!starts_ride([5, 6, 4], entrance, Dir::East));
    }

    #[test]
    fn the_reentry_guard_lasts_two_seconds() {
        assert!(may_enter(0, None));
        assert!(!may_enter(10, Some(0)));
        assert!(!may_enter(39, Some(0)));
        assert!(may_enter(40, Some(0)));
    }

    #[test]
    fn the_tube_axis_names_match_the_block_state() {
        assert_eq!(Dir::North.axis(), "north_south");
        assert_eq!(Dir::South.axis(), "north_south");
        assert_eq!(Dir::East.axis(), "east_west");
        assert_eq!(Dir::West.axis(), "east_west");
        assert_eq!(Dir::Up.axis(), "up_down");
        assert_eq!(Dir::Down.axis(), "up_down");
    }
}
