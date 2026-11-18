# Licence notice — Create: Hypertube slice 1

- **Upstream:** Create: Hypertube 0.6.0 for Minecraft 1.21.1 / NeoForge
  (`PedroRok/CreateHypertubes`, author "Rok").
- **Licence as read:** `license = "Apache License 2.0"` in the pack jar's
  `META-INF/neoforge.mods.toml`
  (`ports/_shared/licence-cache/create_hypertube-0.6.0-NEOFORGE.jar`, SHA-256
  `7bdb8979c7ff7d3b29f7a23771b6ae4870a6dcb7ce2e4a3214fdd6059aacace8`). The jar
  bundles no separate `LICENSE`/`NOTICE` file, so the mods.toml declaration is
  the licence; the upstream repository's own `LICENSE` is the Apache License
  2.0 text, agreeing with it. **Apache-2.0, rank 0 (permissive).**
- **Carried material:** this port ships upstream's own Apache-2.0 assets for the
  two blocks of the slice — the `hypertube` and `hypertube_entrance` blockstates,
  their models, five textures, and their loot tables and lang lines (see
  `tools/assemble_content.py`). Upstream's copyright and licence travel with
  them: `LICENSE` in this folder is the Apache License 2.0 text.
- **Rust:** a clean-room rewrite against the pin's documented API, from the
  behaviour recorded in `FINDINGS.md`; no Java is copied or translated.
- **Rank:** 0 (permissive). Publishable under Apache-2.0 with the notices kept,
  and only with the maintainer's approval (ARCHITECTURE.md §8).
