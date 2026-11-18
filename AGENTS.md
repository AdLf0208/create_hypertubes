# Working on this Horizon native mod

This is a **flat SDK package** (mod API 0.2): `horizon-mod.toml` + `Cargo.toml` + `src/lib.rs`
(`impl mod_api::Hooks`) + `src/runtime.rs` (the pure rules and their tests) + `assets/` + `data/`.
Horizon retired the `.hnmod` container in the mod-API merge (#16941), so there is no
`compatibility.json`, `mixins/<id>/`, `horizon-mixin.toml`, plan/injection schema or
`rust-toolchain.toml` here, and none of them should be recreated.

> **Build slots (v2):** every build/test goes through the campaign runner
> (`ports/tools/build-slot.sh` from the campaign root). It **blocks in the kernel** until a slot is
> free, so **never poll and never background a build**; a timeout exits **75**. It does **not**
> `cd` into the port — wrap the command (`bash -c 'cd ports/<id> && …'`) and never pass
> `--target-dir`.

```sh
ports/tools/build-slot.sh run --job sdk-cht --port ports/create_hypertube --step test \
    -- bash -c 'cd ports/create_hypertube && cargo test'
ports/tools/build-slot.sh run --job sdk-cht --port ports/create_hypertube --step build \
    -- bash -c 'cd ports/create_hypertube && rm -f Cargo.lock && cargo horizon-mod build'
ports/tools/build-slot.sh run --job sdk-cht --port ports/create_hypertube --step check \
    -- bash -c 'cd ports/create_hypertube && cargo horizon-mod check create_hypertube.hmod'
```

- `cargo horizon-mod` fetches the pinned SDK into `.horizon/sdk/` (gitignored, never packed).
  `build` packs the `.hmod`; it does **not** compile against the game — that is
  `horizon-launcher native-build . --instance <instance> --trust-native-code`, which is not
  installed here.
- **`src/runtime.rs` is byte-identical to the retired bundle's `runtime.rs` and must stay so**
  (`cmp` it): the travel rules live there, `src/lib.rs` only converts SDK types to theirs. New rule
  → a test in `runtime.rs`; new glue → a private fn and a test in `lib.rs`.
- **The travel is the `server_tick` hook, not a Part** (a run belongs to no single block); the two
  blocks' shapes are `BlockPart`s (`state_for_placement`, `update_shape`). The movement is
  `EntityRef::teleport_to(host, pos, None)` — the handle methods are the mod-facing host API, not
  `ServerHost`'s area methods.
- Only the API the SDK publishes: `cargo horizon-mod hooks <text>` finds the exact method; never
  guess a name, and record an API gap in `notes.md` instead of faking one.
- The delivered package is `create_hypertube.hmod` **in the port root**, never in `target/`;
  `LICENSE` and `LICENSE-NOTICE.md` travel inside it, and `rm -f Cargo.lock` before a build (a
  packed lock changes the artifact).
- Keep the port separate from Horizon and horizon-mixins; never modify the pin checkouts, never
  commit binaries, exported sources or Minecraft assets, and never put Mojang files in the tree.
- `python3 ports/tools/check-skills.py --notes ports/create_hypertube` must stay green, and
  `notes.md` records every claim with its command and output.
