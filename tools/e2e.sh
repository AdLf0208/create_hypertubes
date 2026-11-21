#!/usr/bin/env bash
# In-game check for Create: Hypertube: a straight run of hypertubes between two
# entrances carries every living traveller the jar's default list allows along
# it at the jar's speed.
#
# STATUS (2026-11-21, slice 2, SDK `0a875da`): the mod is compiled into the game
# by the launcher (`horizon-launcher native-build <port> --instance <instance>
# --trust-native-code`), so `GAME=` and `CTL=` must point at that build's pair
# (`eval "$(ports/tools/launcher-game.sh env create_hypertube)"`), and there is
# no `--dev-mod` any more: the package carries its own `assets/` and `data/`.
#
# The arena is The End's void at x=200 (away from the central island, its dragon
# egg and the ambient item entities of a generated level), floor y=100, blocks
# at y=101, runs along +X.
#
# Default run:
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
#     state is worked out again (`east_west=true, connected=true` on both);
#  H  slice 2: a villager (not a player) is pulled from the same mouth cell and
#     rides the same run to the same 1.5-blocks-past exit;
#  I  slice 2 control: a dropped item in a mouth cell is not a traveller and
#     does not move — the jar pulls `LivingEntity` only;
#  K  slice 2: a wither in a mouth cell does not move — the jar's default
#     `BLACKLIST` names `minecraft:wither`;
#  L  both carried recipes are crafted in a real crafting table (the tube's
#     `BGB/GG/BGB` -> 16, the entrance's tube/iron/hopper -> 1) with their
#     ingredients consumed, and a wrong pattern leaves the result empty;
#  M  both blocks broken in survival drop one of themselves — the carried loot
#     tables, whose two shapes 26.3's own tables never use;
#  J  slice 2: a player holding sneak is not pulled, and the same player
#     standing (sneak released) is: the jar's `isShiftKeyDown` refusal.
#
# SELFTEST=1 flips B's and H's arrival assertion (they must FAIL), proving the
# scenario can fail; SELFTEST=2 flips only H's, so the new traveller leg is the
# one that is shown to be able to fail. NEGATIVE=1 inverts leg I (it expects the
# item to move, which it must not), proving that assertion can fail too.
set -Eeuo pipefail
export LC_ALL=C
[ -z "${CH_DEBUG:-}" ] || set -x

CLONE=${CLONE:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/create_hypertube
CTL=${CTL:-}
GAME=${GAME:-}
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/create_hypertube-e2e.sock}
SELFTEST=${SELFTEST:-0}
NEGATIVE=${NEGATIVE:-0}
KEEP=${KEEP:-0}
WORLD=CreateHypertubeE2E
ID=create_hypertube
# The tube's state text as the game prints it: properties in name order.
TUBE_EW="${ID}:hypertube[connected=true,east_west=true,north_south=false,up_down=false]"
ENTRANCE_EAST="${ID}:hypertube_entrance[facing=east,open=false]"
ENTRANCE_WEST="${ID}:hypertube_entrance[facing=west,open=false]"

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
[ -x "$CTL" ] || {
    echo "missing the game's horizon-ctl: set CTL=<launcher-built horizon-ctl>." >&2
    echo "Build the pair with: ports/tools/launcher-game.sh build create_hypertube" >&2
    echo "and read it with:   eval \"\$(ports/tools/launcher-game.sh env create_hypertube)\"" >&2
    exit 1
}
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
    local args=(--game "$GAME" --world "$world" --seed 20261105 --creative --offscreen
                --wait --resources "$RES")
    if [ -n "${DEV_MOD:-}" ]; then
        args+=(--dev-mod "$DEV_MOD")
    fi
    # `--offscreen`, not `--headless`: leg L opens a crafting-table menu and
    # clicks its grid, and a headless client never opens a screen.
    "$CTL" --socket "$SOCK" launch "${args[@]}" >/dev/null
    ctl wait-ready 120
    ctl wait 40
}

block_state() { ctl block "$1" "$2" "$3" | jq -r '.state // .block // empty'; }

# The player's position and the game's tick counter in one reply.
sample() { ctl state | jq -r '[.player.position[0], .player.position[1], .player.position[2], .ticks] | @tsv'; }

# One mob's or item's position, from the entities the client tracks in lane Z:
# "x y z", or empty when nothing of that type is there. `ctl entities` reports
# a mob as kind `mob` and prints its feet position as `pos`.
mob_pos() { # mob_pos TYPE Z
    ctl entities 48 "$1" | jq -r --argjson z "$2" '
        [.entities[] | select((.pos[2] - $z) < 1.5 and (.pos[2] - $z) > -1.5)]
        | if length == 0 then empty
          else .[0] | "\(.pos[0]) \(.pos[1]) \(.pos[2])" end'
}

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
# (with `far`) an entrance facing west at the end. The far entrance goes in
# **before** the tubes so a sweep can never catch a half-built run (the near
# entrance alone is too short to ride, and the fill completes the run in one
# command).
build_run() { # build_run Z TUBES [far]
    local z=$1 tubes=$2 far=${3:-yes}
    end_cmd "setblock $X0 $Y $z ${ID}:hypertube_entrance[facing=east,open=false]"
    ctl wait 2 >/dev/null
    if [ "$far" = yes ]; then
        end_cmd "setblock $((X0 + 1 + tubes)) $Y $z ${ID}:hypertube_entrance[facing=west,open=false]"
        ctl wait 2 >/dev/null
    fi
    end_cmd "fill $((X0 + 1)) $Y $z $((X0 + tubes)) $Y $z ${TUBE_EW}"
    ctl wait 2 >/dev/null
    [ "$(block_state "$X0" "$Y" "$z")" = "$ENTRANCE_EAST" ] \
        || fail "the entrance did not place at $X0,$Y,$z (got '$(block_state "$X0" "$Y" "$z")')"
    if [ "$far" = yes ]; then
        [ "$(block_state $((X0 + 1 + tubes)) "$Y" "$z")" = "$ENTRANCE_WEST" ] \
            || fail "the far entrance did not place at $((X0 + 1 + tubes)),$Y,$z (got '$(block_state $((X0 + 1 + tubes)) "$Y" "$z")')"
    fi
    [ "$(block_state $((X0 + 1)) "$Y" "$z")" = "$TUBE_EW" ] \
        || fail "the first tube did not place at $((X0 + 1)),$Y,$z (got '$(block_state $((X0 + 1)) "$Y" "$z")')"
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

# Let the ride finish, then read where it left the player. The ride is 23.6
# blocks at 0.5 a tick (48 ticks) and a few of them are already spent by the
# samples above; 24 more is a comfortable margin, and a fixed short wait was
# one tick short on 2026-11-21.
ctl wait 24 >/dev/null
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

echo "== H: a villager (not a player) rides the same run =="
# The villager is summoned into the mouth cell **before** the entrance exists, so its
# starting position is stable to read; then the run goes up around it and the sweep
# finds it.
end_cmd "summon minecraft:villager $((X0 - 1)).5 $Y 6.5 {NoAI:1b,Silent:1b,Invulnerable:1b,PersistenceRequired:1b}"
ctl wait 4 >/dev/null
h0=$(mob_pos villager 6.5)
[ -n "$h0" ] || fail "the villager is not in its mouth cell (ctl entities found none in lane z=6.5)"
read -r hx0 hy0 hz0 <<< "$h0"
echo "  villager at: $h0"
python3 -c "import sys; sys.exit(0 if abs($hx0 - ($X0 - 0.5)) <= 0.2 and abs($hz0 - 6.5) <= 0.2 else 1)" \
    || fail "the villager stands at ($hx0, $hy0, $hz0), expected the mouth cell's centre ($(python3 -c "print($X0 - 0.5)"), 6.5)"
build_run 6 "$RUN_TUBES"
# The sweep runs every 10 ticks, then the ride takes ~47 ticks at 0.5 a tick.
ctl wait 30 >/dev/null
h1=$(mob_pos villager 6.5)
[ -n "$h1" ] || fail "the villager vanished from lane z=6.5 during the ride"
read -r hx1 hy1 hz1 <<< "$h1"
echo "  after 30 ticks: $h1"
python3 -c "import sys; sys.exit(0 if $hx1 > $X0 + 1.0 else 1)" \
    || fail "the villager was not pulled into the run: x=$hx1, from $hx0"
ctl wait 50 >/dev/null
h2=$(mob_pos villager 6.5)
[ -n "$h2" ] || fail "the villager is gone after its ride"
read -r hx2 hy2 hz2 <<< "$h2"
echo "  after 80 ticks: $h2"
VILLAGER_ARRIVED=$EXIT_X
if [ "$SELFTEST" = 1 ] || [ "$SELFTEST" = 2 ]; then
    echo "(selftest: expecting the villager at $((X0 + 5)).0 instead of $VILLAGER_ARRIVED)"
    VILLAGER_ARRIVED=$((X0 + 5))
fi
python3 -c "import sys; sys.exit(0 if abs($hx2 - $VILLAGER_ARRIVED) <= 0.2 else 1)" \
    || fail "the villager ended at x=$hx2, expected $VILLAGER_ARRIVED (1.5 past the far entrance's centre)"
python3 -c "import sys; sys.exit(0 if abs($hz2 - 6.5) <= 0.2 else 1)" \
    || fail "the villager ended at z=$hz2, expected its lane 6.5"
echo "  the villager rode to x=$hx2, the same 1.5 past the far entrance"

echo "== I: control — a dropped item in a mouth is not a traveller =="
build_run -8 "$RUN_TUBES"
end_cmd "summon minecraft:item $((X0 - 1)).5 $Y -7.5 {Item:{id:\"minecraft:stone\",count:1},NoGravity:1b,Age:1}"
ctl wait 4 >/dev/null
i0=$(mob_pos minecraft:item -7.5)
[ -n "$i0" ] || fail "the item is not in the mouth cell (ctl entities found none in lane z=-7.5)"
read -r ix0 iy0 iz0 <<< "$i0"
echo "  item at: $i0"
ctl wait 40 >/dev/null
i1=$(mob_pos minecraft:item -7.5)
[ -n "$i1" ] || fail "the item is gone after 40 ticks (it despawned, so the run proves nothing)"
read -r ix1 iy1 iz1 <<< "$i1"
echo "  after 40 ticks: $i1"
if [ "$NEGATIVE" = 1 ]; then
    echo "(negative: expecting the item to be pulled, which it must not be)"
    python3 -c "import sys; sys.exit(0 if $ix1 > $ix0 + 1.0 else 1)" \
        || fail "negative run: the item stayed put, so the inverted assertion failed as designed (this proves leg I's own assertion can fail)"
else
    python3 -c "import sys; sys.exit(0 if abs($ix1 - $ix0) <= 0.2 and abs($iz1 - $iz0) <= 0.2 else 1)" \
        || fail "a dropped item was pulled into the run: it moved from ($ix0, $iy0, $iz0) to ($ix1, $iy1, $iz1)"
fi
echo "  the item stayed where it was dropped"

echo "== K: the jar's blacklist — a wither in a mouth does not travel =="
build_run 12 "$RUN_TUBES"
end_cmd "summon minecraft:wither $((X0 - 1)).5 $Y 12.5 {NoAI:1b,Silent:1b,Invulnerable:1b,PersistenceRequired:1b}"
ctl wait 4 >/dev/null
k0=$(mob_pos wither 12.5)
[ -n "$k0" ] || fail "the wither is not in its mouth cell (ctl entities found none in lane z=12.5)"
read -r kx0 ky0 kz0 <<< "$k0"
echo "  wither at: $k0"
ctl wait 40 >/dev/null
k1=$(mob_pos wither 12.5)
[ -n "$k1" ] || fail "the wither is gone after 40 ticks, so the run proves nothing"
read -r kx1 ky1 kz1 <<< "$k1"
echo "  after 40 ticks: $k1"
python3 -c "import sys; sys.exit(0 if abs($kx1 - $kx0) <= 0.2 and abs($kz1 - $kz0) <= 0.2 else 1)" \
    || fail "a wither was pulled into the run: it moved from ($kx0, $ky0, $kz0) to ($kx1, $ky1, $kz1)"
echo "  the wither stayed: the default blacklist refused it"

echo "== L: both carried recipes are craftable, and consume their ingredients =="
CRAFT_X=$((X0 + 10))
CRAFT_Z=-12
end_cmd "setblock $CRAFT_X $Y $CRAFT_Z minecraft:crafting_table"
ctl wait 4 >/dev/null
[ "$(block_state "$CRAFT_X" "$Y" "$CRAFT_Z")" = "minecraft:crafting_table" ] \
    || fail "the crafting table did not place at $CRAFT_X,$Y,$CRAFT_Z"
python3 "$PORT/tools/craft_check.py" "$SOCK" "$CTL" "$CRAFT_X" "$Y" "$CRAFT_Z" \
    || fail "the carried recipes did not craft as declared"
ctl close >/dev/null 2>&1 || true
ctl wait 4 >/dev/null
echo "  both recipes crafted (16 tubes, 1 entrance) and their ingredients were consumed"

echo "== M: both blocks drop themselves (the carried loot tables) =="
# The loot tables carry two shapes 26.3's own tables never use (`bonus_rolls`
# and `"rolls": 1.0`); breaking the blocks in survival is what proves the game
# accepts them.
LOOT_Z=-13
LOOT_A=$((X0 + 14))
LOOT_B=$((X0 + 16))
end_cmd "setblock $LOOT_A $Y $LOOT_Z ${ID}:hypertube"
end_cmd "setblock $LOOT_B $Y $LOOT_Z ${ID}:hypertube_entrance[facing=east,open=false]"
ctl wait 4 >/dev/null
TUBE_LONE="${ID}:hypertube[connected=false,east_west=false,north_south=false,up_down=false]"
[ "$(block_state "$LOOT_A" "$Y" "$LOOT_Z")" = "$TUBE_LONE" ] \
    || fail "the loot tube did not place (got '$(block_state "$LOOT_A" "$Y" "$LOOT_Z")')"
ctl command "gamemode survival @s" >/dev/null
ctl command "clear @s" >/dev/null 2>&1 || true
ctl command "item replace entity @s hotbar.0 with minecraft:iron_pickaxe 1" >/dev/null
ctl select 1 >/dev/null
ctl wait 4 >/dev/null
end_cmd "tp @s $(python3 -c "print($LOOT_A + 0.5)") $Y $(python3 -c "print($LOOT_Z + 1.5)")"
ctl wait 6 >/dev/null
ctl break "$LOOT_A" "$Y" "$LOOT_Z" >/dev/null
ctl wait 20 >/dev/null
[ "$(block_state "$LOOT_A" "$Y" "$LOOT_Z")" = "minecraft:air" ] \
    || fail "the loot tube was not broken (it reads '$(block_state "$LOOT_A" "$Y" "$LOOT_Z")')"
tubes_held=$(ctl inventory | jq -r '.counts["create_hypertube:hypertube"] // 0')
echo "  broke the tube in survival: inventory holds $tubes_held tube(s)"
[ "$tubes_held" = 1 ] || fail "breaking a tube dropped $tubes_held tube(s), expected 1"
end_cmd "tp @s $(python3 -c "print($LOOT_B + 0.5)") $Y $(python3 -c "print($LOOT_Z + 1.5)")"
ctl wait 6 >/dev/null
ctl break "$LOOT_B" "$Y" "$LOOT_Z" >/dev/null
ctl wait 20 >/dev/null
[ "$(block_state "$LOOT_B" "$Y" "$LOOT_Z")" = "minecraft:air" ] \
    || fail "the loot entrance was not broken (it reads '$(block_state "$LOOT_B" "$Y" "$LOOT_Z")')"
entrances_held=$(ctl inventory | jq -r '.counts["create_hypertube:hypertube_entrance"] // 0')
echo "  broke the entrance in survival: inventory holds $entrances_held entrance(s)"
[ "$entrances_held" = 1 ] || fail "breaking an entrance dropped $entrances_held entrance(s), expected 1"
ctl command "gamemode creative @s" >/dev/null
ctl wait 4 >/dev/null
echo "  both loot tables dropped one of their own block"

echo "== J: control — a sneaking traveller is not pulled, standing one is =="
build_run 8 "$RUN_TUBES"
# Sneak **before** stepping into the mouth: the entrance pulls a standing
# traveller on the very next tick, so pressing shift afterwards would already be
# too late to test the refusal.
ctl key shift down >/dev/null
ctl wait 2 >/dev/null
KEYS=$(ctl status 2>/dev/null | jq -c '.keys // []' 2>/dev/null || true)
echo "  keys held: ${KEYS:-unavailable}"
stand_behind "$X0" 8
ctl wait 6 >/dev/null
j0=$(sample)
ctl wait 30 >/dev/null
j1=$(sample)
echo "  sneaking, after 30 ticks: $j1"
read -r jx0 jy0 jz0 _ < <(echo "$j0")
read -r jx1 jy1 jz1 _ < <(echo "$j1")
python3 -c "import sys; sys.exit(0 if abs($jx1 - $jx0) <= 0.2 else 1)" \
    || fail "a sneaking traveller was pulled into the run: x=$jx1, from $jx0"
ctl key shift up >/dev/null
ctl wait 30 >/dev/null
j2=$(sample)
read -r jx2 jy2 jz2 _ < <(echo "$j2")
echo "  standing, after 30 more ticks: $j2"
python3 -c "import sys; sys.exit(0 if $jx2 > $jx0 + 1.0 else 1)" \
    || fail "the same traveller standing was not pulled: x=$jx2, from $jx0 (sneak released)"
echo "  sneak refused the pull, and the same player standing rode"

echo "PASS: an entrance pulled the traveller into a straight run of $RUN_TUBES tubes and carried them at the jar's 0.5 blocks a tick to 1.5 blocks past the far entrance, an entrance facing air and a lone tube moved nobody, a solid wall stopped the run, a placed entrance and tube took the facing and axis their placement gives them; a villager was pulled from the same mouth cell and rode the same run to the same exit, while a dropped item and a wither in a mouth cell stayed put (the jar's LivingEntity rule and its default blacklist) and a player holding sneak was refused until the sneak was released; both carried recipes crafted in a crafting table (16 tubes, 1 entrance) with their ingredients consumed and a wrong pattern crafted nothing; and both blocks broke in survival dropped one of themselves"
