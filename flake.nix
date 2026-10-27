{
  description = "Conquest development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        mkMingwGcc = { name, cross }: let
          gcc = cross.buildPackages.gcc;
          mcfg = cross.windows.mcfgthreads;
        in pkgs.writeShellScriptBin name ''
          args=()
          for a in "$@"; do [ "$a" = "-ldl" ] || args+=("$a"); done
          exec ${gcc}/bin/${name} -L${mcfg}/lib "''${args[@]}"
        '';
        winGccX64 = mkMingwGcc { name = "x86_64-w64-mingw32-gcc"; cross = pkgs.pkgsCross.mingwW64; };
        winGccX86 = mkMingwGcc { name = "i686-w64-mingw32-gcc";   cross = pkgs.pkgsCross.mingw32;  };
      in
      {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            nim
            nimble
            gcc
            gnumake
            pkg-config
            git
            winGccX64
            winGccX86
          ];

          buildInputs = with pkgs; [
            glfw
            libGL
            libGLU
            mesa
            libx11
            libxrandr
            libxinerama
            libxcursor
            libxi
            gtk2
            python3
            sqlite
            openssl
            fontconfig
          ];

          shellHook = ''
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.python3 pkgs.sqlite pkgs.fontconfig ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            if [ -n "$ZSH_VERSION" ]; then
              PROMPT="%F{magenta}(conquest)%f $PROMPT"
            else
              PS1="\[\033[35m\](conquest)\[\033[0m\] $PS1"
            fi
          '';
        };
      });
}
