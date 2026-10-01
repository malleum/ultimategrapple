# Ultimate Grapple

A 2D, side-view, Neon White-flavoured speedrunning game. You have a grappling hook
and a disc-golf disc, and the goal is to put the disc in the basket at the end of a course
as fast as possible. Courses are procedurally generated. You can pin the ones you like as
permanent levels, then race them against friends in split-screen or online.

Built with **Godot 4.7**, in GDScript. Every visual and every sound is procedural, so there
are no external assets.

```sh
nix run .                    # play
nix run . -- --server        # headless dedicated server (port 24680)
nix run .#server -- --wins=5 --source=pinned
nix run . -- --rendering-driver opengl3   # for GPUs without Vulkan
nix run . -- --x11           # force XWayland/X11 (native Wayland is the default)
nix develop                  # shell with godot4 (godot4 -e opens the editor)
```

Without Nix you can run `godot4 --path .` with any Godot 4.7 build.

**Wayland:** the project sets `display/display_server/driver.linuxbsd="wayland"`, so on a
Wayland session it runs natively (no XWayland). If there is no Wayland compositor, Godot
falls back to X11 automatically. `--x11` / `--wayland` (or `--display-driver x11|wayland`
when running `godot4` directly) override this. On compositors without server-side
decorations, window decorations come from libdecor (bundled in the nixpkgs Godot);
`GODOT_WAYLAND_DISABLE_LIBDECOR=1` turns that off.

## The loop

Carry the disc, throw it, chase it, catch it, and chain your movement until it hits the chains.

- **Carrying is about 25% slower** (520 vs 395 px/s). On open *fairways*, throwing the disc ahead and sprinting
  after it wins. In tight *tunnels*, throws just bounce off the walls, so carrying it and
  making one final throw wins. The generator builds both kinds of section and signposts them.
- **Throwing while moving** adds aim sway, random spray and lost range.
- **Instant restart** with `R`. Recall the disc with `T` for a +3s penalty. Out of bounds
  costs +2s.
- **Medals** are based on a par time (ACE, GOLD = par, SILVER, BRONZE). Personal-best
  ghosts replay against you.

## Controls

| Action | Keyboard + mouse | Controller |
|---|---|---|
| Run / aim | A D / mouse | left stick / right stick |
| Jump / wall-jump | Space | A |
| Slide / crouch / fast-fall | S | stick down |
| Dash (8-way) | Shift | X |
| Grapple swing (hold) · reel | RMB · W/S | LT · stick up/down |
| Zip to point (hold) | E | LB |
| Charge + throw | hold / release LMB | hold / release RT |
| **Snap** (spin) | F right as you release | RB right as you release |
| **Pivot** (hold) | Ctrl | B |
| Throw type | 1-6 / Q | D-pad left/right |
| Nose angle | wheel / Z X | D-pad up/down |
| Recall disc | T | Y |
| Restart / pause / pin | R / Esc / P | Back / Start / – |

Every keyboard, mouse and controller binding can be changed under **Controls → Rebind
controls** (two slots per action). Any mouse button works, including the side buttons
(MOUSE 4 / MOUSE 5) and the wheel (a wheel notch acts as a single tap). Bindings are saved in
`settings.json`. ESC/START (pause), TAB (scoreboard) and the sticks are fixed. The aim
reticle reads the screen behind it and switches to dark ink over bright skies.

### Mechanics with a high skill ceiling

- **Snap timing.** Press snap as close as possible to releasing the throw (before or
  after). The exact gap sets a continuous snap score: 1.0 when frame-perfect, about 0.98
  one physics tick off, 0.80 at ±35 ms (still shown as PERFECT), 0.45 at ±90 ms (GOOD), and
  0 by 200 ms. Spin, lift/drag stability, wobble and launch speed all scale with the score,
  so a tighter snap always flies further: a frame-perfect backhand carries about 119 m,
  the edge of PERFECT 105 m, GOOD 80–105 m, no snap 53 m. The HUD shows the label plus the
  exact ms and score. Snapping late gives the same throw as snapping early by the same
  margin. `tools/snap_table.gd` and `tools/range_table.gd` measure this exactly.
- **Nose angle.** Tilt the nose up to float or stall, down to punch through wind.
- **Comebacks.** Backhands and forehands are gyroscopic: spin holds the disc's angle in the
  world instead of letting it nose over into the flight path. Thrown steep (60°+) with the
  nose up and a strong snap, the disc climbs, stalls with its leading edge still up, and
  slides back down its own plane toward you. A 75° perfect backhand goes ~14 m out and lands
  ~3 m away. Weak snaps lose the attitude and land forward. Past the stall the disc acts as a
  flat plate. `tools/flight_path.gd` prints and plots these flights.
- **Pivot.** Plant your feet to freeze and store your momentum, then throw clean. Let go of
  pivot within 0.3 s after the throw for a **PIVOT LAUNCH** that gives the stored momentum
  back. There is also a short one-per-airtime air pivot.
- **Six throws.** Backhand (glider), forehand (fast, dips late), hammer (flips, drops over
  walls), roller (rolls along floors and up ramps), scoober (short, half the moving penalty)
  and thumber (fast, cuts down hard).
- **Sky catch.** Catching the disc midair refreshes your dash and your air pivot.
- **Rope physics.** Inelastic rope, pumping, reeling that conserves angular momentum,
  wrapping around corners, fragile, moving and boost anchors, and grapple-anywhere ceilings.
- **Movement tech.** Bunny-hop speed conservation, slide boost, slide-jumps, dash-jumps,
  downhill slide acceleration, ice floors and speed boosters.

## Course generator (`src/level/generator.gd`)

A seeded, deterministic walker places segments from a weighted grammar. There are 27 segment
types: gaps, stairs, wall-jump chimneys, swing chains, zip ledges, zip towers, slide tunnels,
moving platforms, bounce pads, disc gates (throw through a ring to open a door), disc bridges,
updrafts, crosswinds, laser gauntlets, saws, breakable glass, drop shafts, hammer walls, ramp
jumps, grip ceilings, pillar hops, booster gaps, rope-wrap blocks, fairways (open field,
valley, or high tailwind lane), tunnels and slope runs.

- Difficulty scales gap sizes, heights, hazard timing and which segments are allowed.
- Each theme biases segment weights.
- The generator keeps the course inside a vertical band and forces a disc challenge at least
  every 5 segments.
- It adds optional high-skill sky shortcuts, decoration and one of five basket finales.
- Par and medal times are estimated per segment.
- `src/level/validator.gd` checks for unfair geometry: ceiling spikes too low to slide
  under, gaps too tight to crawl through, buried or floating spikes, route points inside
  solids or hazards, and grapple points in walls. `tools/test_gen.gd` runs it over 300 seeds
  (plus a determinism check) and the shipped courses. `tools/test_tunnels.gd` drives the real
  player through every spike tunnel. Courses saved by older generator versions are repaired
  when they load.

## Themes

Ultimate Field, Neon Sprawl (cyberpunk), Elderwood Ruins (fantasy), Celestial Arcade,
Iron Foundry, Frost Peak (ice floors, slide slopes) and Sunset Canyon (mesas, crosswinds,
tailwind fairways). Each has its own palette, sky shader, parallax layers, ambient particles,
decoration, and a generated music loop.

## Pinning courses

Press **P** in a random course, or use PIN on the results screen. The course is saved as JSON
to `~/.local/share/godot/app_userdata/Ultimate Grapple/pinned/`. When running from source,
it is also saved to `levels/`. Commit files in `levels/` to make them permanent built-in
courses. `levels/` ships with seven starter courses (regenerate them with
`godot4 --headless -s tools/make_starters.gd`).

## Multiplayer

- **Couch versus.** Split-screen for up to 4 players, each on their own device. From the menu,
  press A or Space to join. Every player has a **personal world state**, so gates, glass,
  bridges and fragile anchors are per player: your disc opening a gate never opens it for
  anyone else. This works through per-runner physics layers and viewport visibility layers
  (see `src/level/runner.gd`).
- **Online / LAN.** ENet host/join with LAN discovery. Everyone races the same course at the
  same time as non-colliding ghosts. First to sink the disc wins the round, and the first
  player to reach X round wins takes the set. You can use a listen server or a dedicated
  server (`--server --port= --wins= --source= --difficulty=`).

## Layout

```
src/core     game state, settings, input (per-device PlayerInput), themes
src/level    generator, level (shared world), runner (per-player context), overlay
src/player   player controller, procedural visual, ghosts
src/disc     disc aerodynamics, throw archetypes
src/world    solids, grapple points, zones/hazards, movers, gates, glass, basket, decor
src/audio    synth, SFX bank, generative music
src/net      ENet lobby / race sets / LAN discovery
src/ui       HUD, menus, UI theme
tools/       headless tests (generator, gameplay, disc flight), screenshot helper
```
