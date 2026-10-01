# Ultimate Grapple — notes for Claude

- Sole developer project: commit and push directly to `main`. No feature branches, no PRs.
- Engine: Godot 4.7 (GDScript). Run from source: `godot4 --path .`; package: `nix run .`.
- Before pushing, run the headless checks:
  - `godot4 --headless --import` (refreshes script class cache)
  - `godot4 --headless -s tools/test_gen.gd` (300-seed generator validity + determinism)
  - `godot4 --headless --fixed-fps 120 -s tools/test_play.gd` (scripted gameplay + couch isolation)
  - `godot4 --headless --fixed-fps 120 -s tools/fuzz.gd -- 21 1500` (random-input fuzz)
  - `godot4 --headless --fixed-fps 120 -s tools/test_tunnels.gd` (slides through every spike-ceiling tunnel)
  - `godot4 --headless -s tools/test_bindings.gd` (rebinding, side mouse buttons, wheel taps, pad)
  - `nix build .#default` (pck export + wrapper)
- Avoid `:=` on Variant values (Dictionary/Array element access) — Godot treats failed inference as a parse error.
- Course fairness checks live in `src/level/validator.gd` (used by test_gen on generated + `levels/*.json`). Changing generator geometry: bump `Gen.VERSION` and add a `Validator.repair()` step so old pinned saves get fixed on load.
- Controls are rebindable (`src/core/bindings.gd`, saved in settings.json). Never hard-code key names in UI; use `Bindings.label()/labels()`.
- Per-player state (gates, glass, grapple points) lives in `src/level/runner.gd` on per-runner physics/visibility layer bits; shared world in `src/level/level.gd`.
