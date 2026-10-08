# The published GE-Proton-Frontier release, laid out like nixpkgs' proton-ge-bin:
# `out` is a breadcrumb, `steamcompattool` is the tool directory.
#
# Use it through programs.steam.extraCompatPackages (NixOS) or this flake's
# home-manager module. The tag and hash live in release.json and are updated
# after each release is published.
{
  lib,
  stdenvNoCC,
  fetchzip,
}:
let
  release = lib.importJSON ../release.json;
in
stdenvNoCC.mkDerivation {
  pname = "ge-proton-frontier";
  version = release.tag;

  src =
    if release.hash == "" then
      throw "ge-proton-frontier: release.json has no hash yet; publish ${release.tag} and fill it in (see README)"
    else
      fetchzip {
        url = "https://github.com/setkeh/GE-Proton-Frontier/releases/download/${release.tag}/${release.tag}.tar.gz";
        inherit (release) hash;
      };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  outputs = [
    "out"
    "steamcompattool"
  ];

  installPhase = ''
    runHook preInstall

    echo "ge-proton-frontier should not be installed into environments. Use programs.steam.extraCompatPackages or the home-manager module." > $out

    mkdir $steamcompattool
    ln -s $src/* $steamcompattool

    runHook postInstall
  '';

  meta = {
    description = "GE-Proton with a DirectWrite fix for EVE Frontier's in-game browser";
    homepage = "https://github.com/setkeh/GE-Proton-Frontier";
    license = with lib.licenses; [
      lgpl21Plus
      bsd3
    ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
