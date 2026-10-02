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

- **Carrying is about 38% slower** (858 vs 534 px/s). On open *fairways*, throwing the disc ahead and sprinting
  after it wins. In tight *tunnels*, throws just bounce off the walls, so carrying it and
  making one final throw wins. The generator builds both kinds of section and signposts them.
- **Throwing while moving** adds aim sway, random spray and lost range.
- **Instant restart** with `R`. Recall the disc with `T` for a +3s penalty. Out of bounds
  costs +2s. In multiplayer these freeze you for that long instead, so everyone's clock
  stays comparable.
- **Medals** are based on a par time (ACE, GOLD = par, SILVER, BRONZE). Personal-best
  ghosts replay against you.
- **Splits.** Each course is cut into 3-8 splits along its route (a long throw carries you
  through split lines too). The column under the medals shows your PB splits and, as you
  cross each line, how far ahead (green) or behind (red) you are, gold for a best-ever
  segment, LiveSplit style.
- **Wind readout.** Holding the disc, every wind zone along your aim line gets a chevron
  marker where the line enters it (direction and strength 1-5); in flight the disc shows
  the wind it is in.
- **Rumble.** Controllers vibrate on snaps (stronger the better the snap), catches,
  grapples, hard landings, chains, deaths, and versus hits. Strength in Settings.

## Controls

| Action | Keyboard + mouse | Controller |
|---|---|---|
| Run / aim | A D / mouse | left stick / right stick |
| Jump / double jump / wall-jump | Space | A |
| Slide / crouch / fast-fall | S | stick down |
| Grapple swing (hold) · reel | RMB · W/S | LT · stick up/down |
| Zip to point (hold, or tap while swinging) | E | LB |
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
  back. There is also an air pivot (up to ~1 s, once per airtime).
- **Six throws.** Backhand (glider), forehand (fast, dips late), hammer (flips, drops over
  walls), roller (rolls along floors and up ramps), scoober (short, half the moving penalty)
  and thumber (fast, cuts down hard).
- **Smooth jumps.** Letting go of jump early eases into a short hop (extra gravity rather
  than a sudden stop), held jumps hang briefly at the top, coyote time is 0.12 s and jump
  buffering 0.15 s. Jumping into a wall whose top is within ~1.5 tiles of your feet climbs
  onto it instead of wall-jumping away, and clipping a ceiling corner by a few pixels slides
  you past it. The camera's look-ahead is smoothed so it doesn't bob with every jump.
- **Double jump.** One extra jump in the air, refreshed by landing, grappling, launch
  pads and sky catches. There is no dash.
- **Sky catch.** Catching the disc midair refreshes your double jump and your air pivot.
- **Grapple.** 680 px range. Points behind a platform can still be grabbed: the rope starts
  wrapped around the platform corner. A point is chosen by aim direction (±40°) or by
  having the cursor near it. Clicks are buffered for 0.15 s. Zip follows the rope around
  corners and only lets go when it's truly stuck. Fragile (red) points hold for 1.1 s and
  flash before they break.
- **Rope physics.** Inelastic rope, pumping, reeling that conserves angular momentum,
  wrapping around corners, fragile, moving and boost anchors, and grapple-anywhere ceilings.
- **Movement tech.** Bunny-hop speed conservation, slide boost, slide-jumps, double jumps,
  downhill slide acceleration, ice floors and speed boosters.

## Replays

**Race a friend.** SHARE FILE on a replay saves it as a `.ugr` file in
`~/Documents/Ultimate Grapple/`. Your friend drops it on the game window (or uses IMPORT
FRIEND'S RUN on the REPLAYS page) and races your ghost, name and all, on the same course;
the results card says who won and by how much.

**Disc cam.** The results card plays the last 10 seconds of the run from the disc's
point of view: carried in your hand, thrown, and into the chains (with a slow-mo moment as
it hits). With **LOCK TO DISC** on (the default, remembered, also in Settings) the disc
stays level in the middle and the world turns around it, so a hammer that flips over shows
the world upside down. Turn it off to keep the world upright and watch the disc tilt.
In couch and online versus, the round winner's disc cam pops up in the corner for everyone
(online it is rebuilt from the frames their client already streams), and if someone else
won, you get your own once you sink it.

**Match recordings.** Every couch and online round is recorded too (the last 40), listed
under MATCHES on the REPLAYS page. Watching one replays the whole round with every runner
and their disc on their real paths; left / right switch who the camera follows, and the
end card has the finishing order. Online, the other players' paths are the ones their
clients streamed to you (30 Hz). Recordings show runners and discs only, not each
player's personal gates or glass. `tools/test_match.gd` covers it.

Every new personal best saves a replay of that run. **REPLAYS** on the title screen lists
them, most recently played course first.
- **WATCH** plays the run back looking exactly as it did live (HUD, particles, sound),
  with a keystroke overlay of the keys the runner actually had bound.
- **EXPORT MP4** renders the replay at 60 fps with game audio and saves it to
  `~/Videos/Ultimate Grapple/`, ready to send. It uses Godot's movie maker in a second
  window, then ffmpeg, which the nix package bundles.

A replay stores the course, the run's random seed and every tick of input, and is
re-simulated on playback. It also stores the player and disc state per tick and pins
playback to it, so tiny physics differences between sessions can never make a replay
drift. `tools/test_replay.gd` checks that playback is exact, and that a real finish
saves a replay which, when watched, finishes in the same time.

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
- **Online.** PLAY ONLINE joins the public dedicated server at `joshammer.com:24680` (or
  any `host[:port]` you type). Nobody has to port-forward. The first player in the lobby is
  the leader: they pick wins, course source and difficulty, and start the set. Otherwise
  the set starts when everyone is READY. To run your own server on NixOS:
  `imports = [ ultimate-grapple.nixosModules.server ]; services.ultimate-grapple-server = {
  enable = true; openFirewall = true; };` (cloud firewalls need UDP 24680 too).
  `tools/test_online.gd` is a two-client smoke test against a running server.
- **Versus contact** (couch and online). Penalties freeze you instead of adding time.
  Discs collide in the air: hit another player's disc with yours and both bounce off and
  lose spin, which ruins the throw. Slide into another runner to tackle them: they get
  knocked away and are dizzy for a moment. Throw your disc at another runner (rollers along
  the ground count too): a head hit knocks them down, an arm hit makes them drop their
  disc, and a leg hit trips them into a slide. A faster disc hits harder; a slow one just
  bounces off. Online, each client decides contacts against
  what it sees and tells the other one (`tools/test_online_versus.gd`).
- **LAN.** ENet host/join with LAN discovery. Everyone races the same course at the
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
