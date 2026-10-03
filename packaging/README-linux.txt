Ultimate Grapple (Linux, x86_64)

Run:   ./ultimate-grapple.x86_64
       (if your file manager won't start it: chmod +x ultimate-grapple.x86_64)

Uses your system's graphics driver (Nvidia, AMD, Intel): no Nix needed.
NixOS: this generic binary can't find its libraries there; use
  nix run github:malleum/ultimategrapple
(or steam-run ./ultimate-grapple.x86_64, or enable programs.nix-ld).
Engine options go before the game:
  --display-driver x11            force X11 instead of Wayland
  --rendering-driver opengl3      older GPUs without Vulkan
  --fullscreen
Game options go after "--", e.g.  ./ultimate-grapple.x86_64 -- --perf-log

Saves, replays and settings: ~/.local/share/godot/app_userdata/Ultimate Grapple
MP4 replay export needs ffmpeg installed.
Newest build: https://github.com/malleum/ultimategrapple/releases/latest
