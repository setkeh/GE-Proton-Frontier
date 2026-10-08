# GE-Proton-Frontier

GE-Proton built with a DirectWrite patch so EVE Frontier's in-game browser
(the KEEP Monitor) works on Linux.

Each release is [GloriousEggroll's official GE-Proton release](https://github.com/GloriousEggroll/proton-ge-custom/releases)
with exactly one file replaced: `files/lib/wine/x86_64-windows/dwrite.dll`,
rebuilt from the Wine source that GE release is based on, with
[`patches/`](patches/) applied. Everything else is GE's build, untouched.

**Not affiliated with GloriousEggroll, Valve or CCP.** Report problems with
these builds here, not to GE.

## The problem

The missions page in the KEEP Monitor loads a web font
(`FavoritMonoStd-Light.woff2`) whose style name is empty. Windows' DirectWrite
copes with that. Wine's crashes on it, which leaves the in-game browser blank
or stuck on "Initializing" under every Proton version tested (GE-Proton9-27,
UMU-Proton-10.0-4, GE-Proton11-7).

The patch gives such a font an empty style name instead of none, and lets
Wine's existing naming rules take it from there (this font comes out as
"Light"). Fonts that have a style name, which is every other font we checked,
are not affected. The details are in the
[patch description](patches/0001-dwrite-synthesize-empty-face-name.patch).

The proper fix is for the font to have a style name; that has been reported
to CCP, and we plan to offer the patch upstream. Once either lands, this
project is no longer needed.

## Install

Download `GE-ProtonX-Y-FrontierN.tar.gz` and its `.sha512sum` from
[Releases](../../releases), then:

```sh
sha512sum -c GE-Proton11-7-Frontier1.sha512sum
tar -xf GE-Proton11-7-Frontier1.tar.gz -C ~/.local/share/Steam/compatibilitytools.d/
```

The tarball works on any distribution; Proton brings its own runtime.

- **Lutris:** restart Lutris, then EVE Frontier → *Configure* → *Runner
  options* → *Wine version* → `GE-Proton11-7-Frontier1`.
- **Steam:** restart Steam and pick it under the game's *Compatibility*
  settings.

Switching Proton versions makes Proton refresh its own files in the game's
prefix on the next launch, so the first start can be slower.

### Verify where a release came from

Releases are built by this repository's GitHub Actions workflow, which records
signed build provenance for each tarball:

```sh
gh attestation verify GE-Proton11-7-Frontier1.tar.gz --repo setkeh/GE-Proton-Frontier
```

Every tarball also contains `frontier/BUILDINFO` (the GE release and its
sha512, the Wine commit, the patch and DLL hashes, and the workflow run) and a
copy of the patches.

### NixOS / home-manager

```nix
# flake.nix
inputs.ge-proton-frontier.url = "github:setkeh/GE-Proton-Frontier";

# NixOS, for Steam
programs.steam.extraCompatPackages = [ inputs.ge-proton-frontier.packages.x86_64-linux.default ];

# home-manager, for Lutris and Steam
imports = [ inputs.ge-proton-frontier.homeManagerModules.default ];
programs.ge-proton-frontier.enable = true;
```

The package downloads the release named in [`release.json`](release.json) and
checks it against the hash recorded there.

## Building

Everything runs in the flake's dev shell, the same toolchain CI uses:

```sh
nix develop -c scripts/build.sh GE-Proton11-7-Frontier1
nix develop -c scripts/test.sh  GE-Proton11-7-Frontier1 [path/to/stock/GE-Proton11-7]
```

`build.sh` downloads the GE release (checked against GE's sha512), reads the
Wine commit from GE's tag, builds only `dlls/dwrite` with the patches applied,
and writes `dist/`. `test.sh` builds a DirectWrite probe and a font with an
empty style name, then checks that the build loads it, an intact font still
loads, and (given a stock GE directory) that stock GE still fails on it. It
needs `umu-run` on `PATH`.

Only the 64-bit `dwrite.dll` is rebuilt; EVE Frontier's browser is 64-bit.

## Releasing

1. Tag `GE-ProtonX-Y-FrontierN` and push the tag. `N` starts at 1 for each GE
   release and goes up when only our patches change.
2. The workflow builds the tarball, attests it and attaches it to a **draft**
   release.
3. Download the draft's tarball into `dist/`, run `scripts/test.sh` against
   it and check the KEEP Monitor in game, then publish the release.
4. Put the new tag and its hash in `release.json`:
   `nix store prefetch-file --unpack --name source <release tarball URL>`.

## License

The patches modify Wine and are licensed under the
[GNU LGPL 2.1 or later](LICENSE), like Wine. The rest of this repository is
under the same license. Release tarballs contain GE-Proton's components under
their own licenses, which ship inside the tarball.
