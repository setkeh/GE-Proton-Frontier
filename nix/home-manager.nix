self:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.ge-proton-frontier;
in
{
  options.programs.ge-proton-frontier = {
    enable = lib.mkEnableOption "GE-Proton-Frontier in Steam's compatibilitytools.d (Lutris lists it from there too)";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "ge-proton-frontier.packages.\${system}.default";
      description = "The GE-Proton-Frontier release to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file.".local/share/Steam/compatibilitytools.d/${cfg.package.version}".source =
      cfg.package.steamcompattool;
  };
}
