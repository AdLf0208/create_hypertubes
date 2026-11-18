#!/usr/bin/env bash
# In-game check for Create: Hypertube slice 1: a straight run of hypertubes
# between two entrances carries the player along it at the jar's speed.
#
# STATUS (2026-11-18, SDK migration): NOT re-run since the flat `.hmod` package.
# The mod is compiled into the game by the launcher
# (`horizon-launcher native-build <port> --instance <instance> --trust-native-code`),
# so `GAME=` must point at that binary, and there is no `--dev-mod` any more: the
# package carries its own `assets/` and `data/`, so the old `--dev-mod
# "$PORT/content"`, `EMBEDDED=1` and `CONTROL=1` legs (the AE2 embedded-cache
# pattern) are retired with the `.hnmod` container. The scenario and every
# assertion are unchanged: this is still the only in-game oracle, and leg G
# (a placed tube refreshing the tube beside it) is the `update_shape` Part's.
#
# The arena is The End's void at x=200 (away from the central island, its dragon
# egg and the ambient item entities of a generated level), floor y=100, blocks
# at y=101, runs along +X.
#
# Default run (the launcher-built game carries the mod; `DEV_MOD=<dir>` loads a
# plain content `.hmod` folder as well):
#  A  the entrance smells the player in the cell behind its mouth, and the ride
#     moves them +X at the jar's 0.5 blocks a tick (measured against the game's
#     own tick counter on the straight part of the run);
#  B  the ride ends 1.5 blocks past the far entrance's centre, level with it;
#  C  control: an entrance whose mouth faces air moves nobody;
#  D  control: a lone tube with no entrance moves nobody;
#  E  a solid wall in the run stops it: the traveller never reaches the far
#     entrance;
#  F  a placed entrance takes the face its placer looks along
#     (`create_hypertube:hypertube_entrance[facing=east,open=false]`);
#  G  a placed tube takes its axis from the tube beside it, and that tube's
#     state is worked out again (`east_west=true, connected=true` on both).
#
# EMBEDDED=1 / CONTROL=1 were the retired `.hnmod` bundle's legs (the content
# half written out of a `content_root` injection and read back); the flat
# package carries `assets/` and `data/` itself, so both are gone with it.
#
# SELFTEST=1 flips B's arrival assertion (it must FAIL), proving the scenario
# can fail.
set -Eeuo pipefail
export LC_ALL=C
[ -z "${CH_DEBUG:-}" ] || set -x

CLONE=${CLONE:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/create_hypertube
CTL=${CTL:-$CLONE/ports/_shared/bin/horizon-1d63e0a5/horizon-ctl}
GAME=${GAME:-}
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/create_hypertube-e2e.sock}
SELFTEST=${SELFTEST:-0}
KEEP=${KEEP:-0}
WORLD=CreateHypertubeE2E
ID=create_hypertube
# The tube's state text as the game prints it: properties in name order.
TUBE_EW="${ID}:hypertube[connected=true,east_west=true,north_south=false,up_down=false]"
ENTRANCE_EAST="${ID}:hypertube_entrance[facing=east,open=false]"

# The End arena: floor y=100, blocks at y=101.
X0=200
Y=101
# The jar's speed at the minimum kinetic speed: 0.4333 + 16/240 blocks a tick.
SPEED=0.5
# Run A: entrance, twenty tubes, entrance; 23.6 blocks of path from the mouth,
# 47 ticks at 0.5 a tick — long enough that two samples of the straight part are
# several ticks apart even though one `ctl` round trip is about six.
RUN_TUBES=20
FAR=$((X0 + 1 + RUN_TUBES))          # the far entrance's cell
EXIT_X=$(python3 -c "print($FAR + 0.5 + 1.5)")
PATH_BLOCKS=$(python3 -c "print(round(1.118033988749895 + $RUN_TUBES + 1 + 1.5, 3))")

command -v jq >/dev/null || { echo "missing jq (every assertion parses a ctl reply)" >&2; exit 1; }
[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || {
    echo "missing a game that carries this mod: set GAME=<launcher-built horizon-client>." >&2
    echo "Build one with: horizon-launcher native-build <port> --instance <instance> --trust-native-code" >&2
    exit 1
}
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }

SCRATCH=$(mktemp -d /tmp/opencode/create_hypertube-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")" "$XDG_CONFIG_HOME"
rm -f "$SOCK"

ctl() {
    local out
    if ! out=$("$CTL" --socket "$SOCK" "$@" 2>&1); then
        echo "FAIL: ctl $* failed" >&2
        echo "$out" >&2
        return 1
    fi
    printf '%s\n' "$out"
}
fail() { echo "FAIL: $*" >&2; ctl logs --lines 60 >&2 || true; exit 1; }
on_error() { echo "FAIL: line $1: '$2' exited $?" >&2; ctl logs --lines 40 >&2 || true; }
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

cleanup() {
    local status=$?
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    if [ "$KEEP" = 1 ]; then
        echo "kept scratch: $SCRATCH" >&2
    else
        rm -rf "$SCRATCH" 2>/dev/null || true
    fi
    # Last line of every run: `check-e2e-logs.py` reads it as the verdict.
    echo "EXIT:$status"
}
trap cleanup EXIT

launch() { # launch [WORLD]
    local world=${1:-$WORLD}
    rm -f "$SOCK"
    cd "$SCRATCH"
    # The launcher builds the mod into the game, so nothing is loaded from a separate
    # content directory. `DEV_MOD=<dir>` is the escape hatch for a content-only probe
    # (a plain `.hmod` folder, as `--dev-mod` always took).
    local args=(--game "$GAME" --world "$world" --seed 20261105 --creative --headless
                --wait --resources "$RES")
    if [ -n "${DEV_MOD:-}" ]; then
        args+=(--dev-mod "$DEV_MOD")
    fi
    "$CTL" --socket "$SOCK" launch "${args[@]}" >/dev/null
    ctl wait-ready 120
    ctl wait 40
}

block_state() { ctl block "$1" "$2" "$3" | jq -r '.state // .block // empty'; }

# The player's position and the game's tick counter in one reply.
sample() { ctl state | jq -r '[.player.position[0], .player.position[1], .player.position[2], .ticks] | @tsv'; }

# `execute in <dim> run …`: the End, whatever the player's level.
end_cmd() { ctl command "execute in minecraft:the_end run $1" >/dev/null; }

# The End's void at X0: a stone floor, clear air above it, no other entities.
arena() {
    end_cmd "tp @s $X0.5 104 0.5"
    local loaded=false
    for _ in $(seq 1 120); do
        ctl wait 5 >/dev/null
        if [ "$(ctl block "$X0" 100 0 | jq -r '.loaded // false')" = true ]; then
            loaded=true
            break
        fi
    done
    [ "$loaded" = true ] || fail "the End arena chunk never loaded"
    end_cmd "fill $((X0 - 6)) 100 -16 $((X0 + 34)) 100 16 minecraft:stone"
    ctl wait 6 >/dev/null
    end_cmd "fill $((X0 - 6)) 101 -16 $((X0 + 34)) 108 16 minecraft:air"
    ctl wait 6 >/dev/null
    end_cmd "kill @e[type=!player]"
    ctl wait 20 >/dev/null
    [ "$(block_state "$X0" 100 0)" = "minecraft:stone" ] || fail "the arena floor is not stone"
    [ "$(block_state "$X0" 101 0)" = "minecraft:air" ] || fail "the arena air above the floor is not air"
}

# One straight run along +X at z: an entrance facing east, `tubes` tubes, and
# (with `far`) an entrance facing west at the end.
build_run() { # build_run Z TUBES [far]
    local z=$1 tubes=$2 far=${3:-yes}
    end_cmd "setblock $X0 $Y $z ${ID}:hypertube_entrance[facing=east,open=false]"
    ctl wait 2 >/dev/null
    end_cmd "fill $((X0 + 1)) $Y $z $((X0 + tubes)) $Y $z ${TUBE_EW}"
    ctl wait 2 >/dev/null
    if [ "$far" = yes ]; then
        end_cmd "setblock $((X0 + 1 + tubes)) $Y $z ${ID}:hypertube_entrance[facing=west,open=false]"
        ctl wait 2 >/dev/null
    fi
    [ "$(block_state "$X0" "$Y" "$z")" = "$ENTRANCE_EAST" ] \
        || fail "the entrance did not place at $X0,$Y,$z (got '$(block_state "$X0" "$Y" "$z")')"
}

# Standing in the cell behind an entrance's mouth, at the mouth's y.
stand_behind() { # stand_behind X Z
    end_cmd "tp @s $(python3 -c "print($1 - 0.5)") $Y $(python3 -c "print($2 + 0.5)")"
    ctl wait 2 >/dev/null
}

pos_of() { echo "$1" | cut -f1; }

echo "== launch (The End arena, the launcher-built game carries the mod) =="
launch
arena

echo "== A/B: a run of $RUN_TUBES tubes between two entrances carries the player =="
build_run 0 "$RUN_TUBES"
echo "  run: entrance $X0, tubes $((X0 + 1))..$((X0 + RUN_TUBES)), entrance $FAR, path $PATH_BLOCKS blocks"
stand_behind "$X0" 0
before=$(sample)
echo "  before: $before"
ctl wait 3 >/dev/null

# The straight part of the path: sample every 2 ticks and keep the points
# between the first tube centre and the far entrance's centre.
SAMPLES=$SCRATCH/samples.tsv
: > "$SAMPLES"
for _ in $(seq 1 10); do
    ctl wait 1 >/dev/null
    read -r x y z ticks < <(sample)
    ticks=${ticks%.*}
    echo "  x=$x y=$y z=$z ticks=$ticks" >&2
    if python3 -c "import sys; sys.exit(0 if $((X0 + 1)) <= $x <= $((FAR)) else 1)"; then
        printf '%s\t%s\n' "$ticks" "$x" >> "$SAMPLES"
    fi
done
[ "$(wc -l < "$SAMPLES")" -ge 2 ] || fail "fewer than two samples landed on the straight part of the run"
MEASURED=$(python3 - "$SAMPLES" <<'PY'
import statistics
import sys
rows = [line.split() for line in open(sys.argv[1]) if line.strip()]
rates = []
for (t0, x0), (t1, x1) in zip(rows, rows[1:]):
    dt = int(t1) - int(t0)
    if dt > 0:
        rates.append((float(x1) - float(x0)) / dt)
print(round(statistics.median(rates), 4) if rates else "")
PY
)
echo "  measured $MEASURED blocks a tick over $(wc -l < "$SAMPLES") samples of the straight run"
python3 -c "import sys; sys.exit(0 if abs($MEASURED - $SPEED) <= 0.03 else 1)" \
    || fail "the ride moved $MEASURED blocks a tick, expected the jar's $SPEED"

# Let the ride finish, then read where it left the player.
ctl wait 12 >/dev/null
read -r ex ey ez eticks < <(sample)
echo "  after: x=$ex y=$ey z=$ez ticks=$eticks"
ARRIVED=$EXIT_X
if [ "$SELFTEST" = 1 ]; then
    echo "(selftest: expecting the traveller at $((X0 + 5)).0 instead of $ARRIVED)"
    ARRIVED=$((X0 + 5))
fi
python3 -c "import sys; sys.exit(0 if abs($ex - $ARRIVED) <= 0.15 else 1)" \
    || fail "the ride left the traveller at x=$ex, expected $ARRIVED (1.5 past the far entrance's centre)"
python3 -c "import sys; sys.exit(0 if abs($ez - 0.5) <= 0.15 else 1)" \
    || fail "the ride left the traveller at z=$ez, expected the run's z 0.5"
echo "  the ride ended at x=$ex (expected $ARRIVED), z=$ez"

echo "== C: control — an entrance whose mouth faces air moves nobody =="
end_cmd "setblock $X0 $Y 4 ${ID}:hypertube_entrance[facing=east,open=false]"
ctl wait 4 >/dev/null
stand_behind "$X0" 4
ctl wait 20 >/dev/null
read -r cx cy cz cticks < <(sample)
echo "  after 20 ticks: x=$cx y=$cy z=$cz"
python3 -c "import sys; sys.exit(0 if abs($cx - ($X0 - 0.5)) <= 0.15 and abs($cz - 4.5) <= 0.15 else 1)" \
    || fail "an entrance facing air moved the traveller to ($cx, $cy, $cz)"
echo "  the player stayed at the mouth's cell"

echo "== D: control — a lone tube with no entrance moves nobody =="
end_cmd "setblock $((X0 + 2)) $Y 8 ${TUBE_EW}"
ctl wait 4 >/dev/null
end_cmd "tp @s $((X0 + 2)).5 $Y 8.5"
ctl wait 20 >/dev/null
read -r dx dy dz dticks < <(sample)
echo "  after 20 ticks: x=$dx y=$dy z=$dz"
python3 -c "import sys; sys.exit(0 if abs($dx - ($X0 + 2.5)) <= 0.15 and abs($dz - 8.5) <= 0.15 else 1)" \
    || fail "a lone tube moved the traveller to ($dx, $dy, $dz)"
echo "  the player stayed in the tube"

echo "== E: a solid wall in the run stops it =="
# Entrance, two tubes, stone, two more tubes, a far entrance: the run ends at
# the tube before the wall, so the traveller never reaches the far entrance.
build_run -4 2 no
end_cmd "setblock $((X0 + 3)) $Y -4 minecraft:stone"
ctl wait 2 >/dev/null
end_cmd "setblock $((X0 + 4)) $Y -4 ${TUBE_EW}"
end_cmd "setblock $((X0 + 5)) $Y -4 ${TUBE_EW}"
end_cmd "setblock $((X0 + 6)) $Y -4 ${ID}:hypertube_entrance[facing=west,open=false]"
ctl wait 4 >/dev/null
stand_behind "$X0" -4
ctl wait 30 >/dev/null
read -r wx wy wz wticks < <(sample)
health=$(ctl state | jq -r '.player.health')
echo "  after 30 ticks: x=$wx y=$wy z=$wz health=$health"
python3 -c "import sys; sys.exit(0 if $wx < $((X0 + 3)) + 0.6 else 1)" \
    || fail "the traveller reached x=$wx past the wall at $((X0 + 3))"
python3 -c "import sys; sys.exit(0 if $wx < $((X0 + 5)) else 1)" \
    || fail "the traveller reached x=$wx, past the far entrance at $((X0 + 6))"
python3 -c "import sys; sys.exit(0 if $health > 0 else 1)" || fail "the traveller died at the wall"
echo "  the run stopped at the wall: x=$wx, the far entrance at $((X0 + 6)) was never reached"

echo "== F: a placed entrance takes the face its placer looks along =="
ctl command "item replace entity @s hotbar.0 with ${ID}:hypertube_entrance 1" >/dev/null
ctl wait 4 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
end_cmd "tp @s $((X0 + 9)).5 $Y 12.5"
ctl wait 4 >/dev/null
ctl look-at-block $((X0 + 11)) 100 12 up >/dev/null
ctl wait 2 >/dev/null
ctl place $((X0 + 11)) $Y 12 --item ${ID}:hypertube_entrance >/dev/null
ctl wait 6 >/dev/null
placed=$(block_state $((X0 + 11)) "$Y" 12)
echo "  placed: $placed"
[ "$placed" = "$ENTRANCE_EAST" ] \
    || fail "the placed entrance reads '$placed', expected facing=east"

echo "== G: a placed tube takes its axis from the tube beside it =="
end_cmd "setblock $((X0 + 2)) $Y 2 ${ID}:hypertube"
ctl wait 4 >/dev/null
ctl command "item replace entity @s hotbar.0 with ${ID}:hypertube 1" >/dev/null
ctl wait 4 >/dev/null
ctl select 1 >/dev/null
ctl wait 2 >/dev/null
end_cmd "tp @s $((X0 + 2)).5 $Y 4.5"
ctl wait 4 >/dev/null
ctl look-at-block $((X0 + 3)) 100 2 up >/dev/null
ctl wait 2 >/dev/null
ctl place $((X0 + 3)) "$Y" 2 --item ${ID}:hypertube >/dev/null
ctl wait 6 >/dev/null
mine=$(block_state $((X0 + 3)) "$Y" 2)
neighbour=$(block_state $((X0 + 2)) "$Y" 2)
echo "  placed tube: $mine"
echo "  its neighbour: $neighbour"
[ "$mine" = "${TUBE_EW}" ] \
    || fail "the placed tube reads '$mine', expected the east/west arm"
[ "$neighbour" = "${TUBE_EW}" ] \
    || fail "the tube beside it reads '$neighbour', expected its state to be worked out again"

echo "PASS: an entrance pulled the traveller into a straight run of $RUN_TUBES tubes and carried them at the jar's 0.5 blocks a tick to 1.5 blocks past the far entrance, an entrance facing air and a lone tube moved nobody, a solid wall stopped the run, and a placed entrance and tube took the facing and axis their placement gives them"
