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
              engine=()
              game=()
              while [ \$# -gt 0 ]; do
                case "\$1" in
                  --rendering-driver|--rendering-method|--display-driver|--audio-driver|--resolution|--position|--screen)
                    engine+=("\$1" "\$2"); shift 2 ;;
                  --fullscreen|--maximized|--windowed|--headless|--verbose|--print-fps)
                    engine+=("\$1"); shift ;;
                  --server)
                    engine+=("--headless"); game+=("\$1"); shift ;;
                  *) game+=("\$1"); shift ;;
                esac
              done
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
