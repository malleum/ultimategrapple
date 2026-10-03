{
  description = "Ultimate Grapple - neon speed disc golf with a grappling hook (Godot 4)";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs:
        let
          godot = pkgs.godot_4;
          game = pkgs.stdenvNoCC.mkDerivation {
            pname = "ultimate-grapple";
            version = "0.2.0";
            src = pkgs.lib.cleanSourceWith {
              src = ./.;
              filter = path: type:
                let base = baseNameOf path; in
                !(builtins.elem base [ ".godot" "build" "result" ".git" ]);
            };
            nativeBuildInputs = [ godot ];
            buildPhase = ''
              runHook preBuild
              export HOME=$TMPDIR
              export XDG_DATA_HOME=$TMPDIR/data XDG_CONFIG_HOME=$TMPDIR/config XDG_CACHE_HOME=$TMPDIR/cache
              # first pass builds the script class cache / imports
              godot4 --headless --import || true
              mkdir -p build
              godot4 --headless --export-pack "Linux" build/ultimate-grapple.pck
              test -s build/ultimate-grapple.pck
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out/share/ultimate-grapple $out/bin
              cp build/ultimate-grapple.pck $out/share/ultimate-grapple/
              cat > $out/bin/ultimate-grapple <<SH
              #!${pkgs.runtimeShell}
              # Engine flags are passed to Godot; everything else goes to the game.
              #   ultimate-grapple                      play
              #   ultimate-grapple --server [--port=N --wins=N --source=random|pinned]
              #   ultimate-grapple --rendering-driver opengl3   (older GPUs)
              #   ultimate-grapple --x11 | --wayland     (native Wayland is the default;
              #                                          falls back to X11 automatically)
              engine=()
              game=()
              while [ \$# -gt 0 ]; do
                case "\$1" in
                  --rendering-driver|--rendering-method|--display-driver|--audio-driver|--resolution|--position|--screen)
                    engine+=("\$1" "\$2"); shift 2 ;;
                  --fullscreen|--maximized|--windowed|--headless|--verbose|--print-fps)
                    engine+=("\$1"); shift ;;
                  --x11)
                    engine+=("--display-driver" "x11"); shift ;;
                  --wayland)
                    engine+=("--display-driver" "wayland"); shift ;;
                  --server)
                    engine+=("--headless"); game+=("\$1"); shift ;;
                  *) game+=("\$1"); shift ;;
                esac
              done
              # ffmpeg turns exported replays (Godot movie maker AVI) into MP4
              export PATH="${pkgs.ffmpeg-headless}/bin:\$PATH"
              # Godot doesn't list --main-pack in OS.get_cmdline_args(); the MP4
              # export relaunches the game and finds the pack here
              export UG_MAIN_PACK="$out/share/ultimate-grapple/ultimate-grapple.pck"
              exec ${godot}/bin/godot4 --main-pack $out/share/ultimate-grapple/ultimate-grapple.pck "\''${engine[@]}" -- "\''${game[@]}"
              SH
              chmod +x $out/bin/ultimate-grapple
              runHook postInstall
            '';
            meta = {
              description = "Neon speed-running disc golf with a grappling hook";
              mainProgram = "ultimate-grapple";
              platforms = pkgs.lib.platforms.linux;
            };
          };
        in
        {
          ultimate-grapple = game;
          default = game;
        });

      apps = forAll (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/ultimate-grapple";
        };
        server = {
          type = "app";
          program = "${pkgs.writeShellScript "ultimate-grapple-server" ''
            exec ${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/ultimate-grapple --server "$@"
          ''}";
        };
      });

      # Dedicated server as a NixOS service (headless Godot, UDP).
      #   imports = [ ultimate-grapple.nixosModules.server ];
      #   services.ultimate-grapple-server = { enable = true; openFirewall = true; };
      # Players reach it with PLAY ONLINE (host[:port]); no port forwarding on
      # their side. Cloud firewalls (e.g. Oracle VCN) need UDP <port> and
      # <servicePort> too. The server keeps only the built-in courses'
      # leaderboards (in its StateDirectory); everything else is relayed.
      nixosModules.server = { config, lib, pkgs, ... }:
        let cfg = config.services.ultimate-grapple-server;
        in {
          options.services.ultimate-grapple-server = {
            enable = lib.mkEnableOption "the Ultimate Grapple dedicated race server";
            port = lib.mkOption {
              type = lib.types.port;
              default = 24680;
              description = "UDP port the server listens on.";
            };
            servicePort = lib.mkOption {
              type = lib.types.port;
              default = 24682;
              description = "UDP port for online services (leaderboards of the built-in courses, who's online, relaying runs between players).";
            };
            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Open the server's UDP ports (game + services) in the NixOS firewall.";
            };
            wins = lib.mkOption {
              type = lib.types.ints.between 1 15;
              default = 3;
              description = "Default round wins needed to take a set (the lobby leader can change it).";
            };
            source = lib.mkOption {
              type = lib.types.enum [ "random" "pinned" ];
              default = "random";
              description = "Default course source: freshly generated or the built-in pinned courses.";
            };
            difficulty = lib.mkOption {
              type = lib.types.numbers.between 0 1;
              default = 0.5;
              description = "Default course difficulty, 0..1.";
            };
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              description = "Ultimate Grapple package (its --server mode runs headless).";
            };
          };
          config = lib.mkIf cfg.enable {
            systemd.services.ultimate-grapple-server = {
              description = "Ultimate Grapple dedicated race server";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = lib.concatStringsSep " " [
                  "${cfg.package}/bin/ultimate-grapple --server"
                  "--port=${toString cfg.port}"
                  "--service-port=${toString cfg.servicePort}"
                  "--wins=${toString cfg.wins}"
                  "--source=${cfg.source}"
                  "--difficulty=${toString cfg.difficulty}"
                ];
                DynamicUser = true;
                StateDirectory = "ultimate-grapple-server";
                Environment = [ "HOME=/var/lib/ultimate-grapple-server" ];
                Restart = "always";
                RestartSec = 5;
                # Hardening: it needs the network and nothing else.
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                PrivateDevices = true;
                NoNewPrivileges = true;
                RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
                MemoryMax = "512M";
              };
            };
            networking.firewall.allowedUDPPorts = lib.mkIf cfg.openFirewall [ cfg.port cfg.servicePort ];
          };
        };

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.godot_4 ];
          shellHook = ''
            echo "godot4 -e      # open the editor"
            echo "godot4 --path . # run from source"
          '';
        };
      });
    };
}
