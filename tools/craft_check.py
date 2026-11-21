#!/usr/bin/env python3
"""Craft the port's two carried recipes in a real crafting table.

Called by `tools/e2e.sh` with the open game's control socket. Uses the
harness's crafting grid (`ctl screen`: slots 100-108 row-major, result 200),
gives the ingredients, and asserts each recipe's real shape:

1. `create_hypertube:hypertube` — `BGB / G G / BGB` (B = copper ingot,
   G = glass pane) -> 16 tubes, and the four copper and the four glass panes
   are consumed;
2. `create_hypertube:hypertube_entrance` — the tube above an iron ingot above a
   hopper -> 1 entrance, and those three are consumed;
3. control: eight copper around a glass centre leaves the result empty, so a
   matcher that crafted anything would be caught.

Exits 1 with the observed result on the first mismatch. The GameTest-style
"shapeless" checks are not needed: both recipes are shaped.
"""
import json
import subprocess
import sys


def main() -> None:
    sock, ctl, x, y, z = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

    def run(*args):
        out = subprocess.run([ctl, "--socket", sock, *args], text=True, capture_output=True)
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            raise SystemExit(f"ctl {' '.join(args)}: {out.stdout}{out.stderr}")

    def wait(ticks: int = 4) -> None:
        run("wait", str(ticks))

    def slots():
        screen = run("screen")
        if "slots" not in screen:
            raise SystemExit(f"no menu is open: {screen}")
        return screen["slots"]

    def counts() -> dict:
        return run("inventory").get("counts", {})

    def find(item: str) -> int:
        for slot in slots():
            if slot.get("item") == item:
                return slot["slot"]
        raise SystemExit(f"missing ingredient {item} in the inventory")

    def result():
        stack = [s for s in slots() if s["slot"] == 200]
        if not stack or not stack[0].get("item"):
            return None
        return stack[0]

    def place(item: str, cells) -> None:
        """One of `item` into each grid cell: take the stack, right-click each
        cell (one item per click), put the rest back."""
        slot = find(item)
        run("click-slot", str(slot))
        wait(1)
        for cell in cells:
            run("click-slot", str(cell), "right")
            wait(1)
        run("click-slot", str(slot))
        wait(2)

    def free_slot() -> int:
        for slot in slots():
            if slot["slot"] >= 9 and not slot.get("item"):
                return slot["slot"]
        raise SystemExit("no empty inventory slot for the crafted stack")

    def setup(items) -> None:
        try:
            run("close")
        except SystemExit:
            pass
        wait(5)
        # A fresh table: its block entity and therefore the grid start empty.
        run("setblock", x, y, z, "minecraft:air")
        run("setblock", x, y, z, "minecraft:crafting_table")
        wait(2)
        run("command", f"tp @s {float(x) - 0.5} {y} {float(z) + 0.5}")
        wait(3)
        run("command", "clear @s")
        for item, count in items:
            run("give", item, str(count))
        wait(3)
        run("interact", x, y, z)
        wait(5)

    def craft(label: str, items, placements, want_item: str, want_count: int, consumed) -> None:
        setup(items)
        before = counts()
        for item, cells in placements:
            place(item, cells)
        got = result()
        print(f"{label} ->", json.dumps(got), flush=True)
        if not got or got.get("item") != want_item or got.get("count") != want_count:
            raise SystemExit(f"{label}: expected {want_count} {want_item}, got {got}")
        # Take the result, then read what the craft consumed.
        run("click-slot", "200")
        wait(2)
        run("click-slot", str(free_slot()))
        wait(3)
        after = counts()
        for item, spent in consumed:
            delta = after.get(item, 0) - before.get(item, 0)
            print(f"  {item}: {before.get(item, 0)} -> {after.get(item, 0)}", flush=True)
            if delta != spent:
                raise SystemExit(f"{label}: {item} changed by {delta}, expected {spent}")
        made = after.get(want_item, 0) - before.get(want_item, 0)
        if made != want_count:
            raise SystemExit(f"{label}: the inventory gained {made} {want_item}, expected {want_count}")
        run("close")
        wait(4)

    def empty_control(label: str, items, placements) -> None:
        setup(items)
        for item, cells in placements:
            place(item, cells)
        got = result()
        print(f"{label} ->", json.dumps(got), flush=True)
        if got is not None:
            raise SystemExit(f"{label}: control crafted {got['item']} x{got['count']}")
        run("close")
        wait(4)

    # 1. BGB / G G / BGB -> 16 tubes.
    craft(
        "hypertube BGB/GG/BGB",
        [("minecraft:copper_ingot", 16), ("minecraft:glass_pane", 16)],
        [
            ("minecraft:copper_ingot", [100, 102, 106, 108]),
            ("minecraft:glass_pane", [101, 103, 105, 107]),
        ],
        "create_hypertube:hypertube",
        16,
        [("minecraft:copper_ingot", -4), ("minecraft:glass_pane", -4)],
    )

    # 2. tube / iron ingot / hopper -> 1 entrance.
    craft(
        "entrance F/G/C",
        [
            ("create_hypertube:hypertube", 1),
            ("minecraft:iron_ingot", 1),
            ("minecraft:hopper", 1),
        ],
        [
            ("create_hypertube:hypertube", [101]),
            ("minecraft:iron_ingot", [104]),
            ("minecraft:hopper", [107]),
        ],
        "create_hypertube:hypertube_entrance",
        1,
        [
            ("create_hypertube:hypertube", -1),
            ("minecraft:iron_ingot", -1),
            ("minecraft:hopper", -1),
        ],
    )

    # 3. Control: the tube recipe's ring, but all copper — no result.
    empty_control(
        "control 9 copper",
        [("minecraft:copper_ingot", 16), ("minecraft:glass_pane", 16)],
        [
            ("minecraft:copper_ingot", [100, 101, 102, 103, 105, 106, 107, 108]),
            ("minecraft:glass_pane", [104]),
        ],
    )

    print("craft_check: both carried recipes crafted with their ingredients consumed", flush=True)


if __name__ == "__main__":
    main()
