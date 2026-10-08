{
  description = "GE-Proton with a DirectWrite fix for EVE Frontier's in-game browser";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mingw = pkgs.pkgsCross.mingwW64;
    in
    {
      # The published release, fetched by hash (see release.json). Absent
      # until the first release is published and its hash recorded.
      packages.${system} = pkgs.lib.optionalAttrs ((pkgs.lib.importJSON ./release.json).hash != "") {
        default = pkgs.callPackage ./nix/package.nix { };
      };

      # Puts the release in Steam's compatibilitytools.d, where Lutris finds it too.
      homeManagerModules.default = import ./nix/home-manager.nix self;

      # Everything scripts/build.sh and scripts/test.sh need. CI builds inside
      # this shell too, so a local build uses the same pinned toolchain.
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          mingw.stdenv.cc
          mingw.buildPackages.binutils
          pkgs.gcc
          pkgs.gnumake
          pkgs.autoconf
          pkgs.flex
          pkgs.bison
          pkgs.perl
          pkgs.python3
          pkgs.gnupatch
          pkgs.git
          pkgs.curl
          pkgs.gnutar
          pkgs.gzip
        ];
        # A libre font to build the broken test font from (scripts/test.sh).
        TEST_FONT_SRC = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf";
      };
    };
}
