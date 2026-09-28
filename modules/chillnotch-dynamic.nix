{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.chillnotch-dynamic;

  jsonFormat = pkgs.formats.json { };

  rawDefaultsFile = ../config.jsonc;

  strictDefaultsJson = pkgs.runCommand "chillnotch-dynamic-default-settings.json" { } ''
    ${pkgs.gnused}/bin/sed -E 's/,([[:space:]]*[}\]])/\1/g' ${rawDefaultsFile} > $out
  '';

  defaultSettings = builtins.fromJSON (builtins.readFile strictDefaultsJson);

  mergedSettings = lib.recursiveUpdate defaultSettings cfg.settings;

  configFile = jsonFormat.generate "config.jsonc" mergedSettings;
in
{
  options.programs.chillnotch-dynamic = {
    enable = mkEnableOption "chillnotch-dynamic (quickshell-based Wayland bar)";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../default.nix { };
      description = "Package chillnotch-dynamic for use.";
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Panel settings. These override the defaults from the config.jsonc.
      '';
      example = literalExpression ''
        {
          clockFormat = "HH:mm";
          weatherLocation = "London";
          defaultTerminal = "alacritty";
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];
    xdg.configFile."chillnotch-dynamic/config.jsonc".source = configFile;
  };
}
