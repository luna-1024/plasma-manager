{ lib
, config
, ...
} @ args:
let
  cfg = config.programs.plasma;

  widgets = import ./widgets args;

  panelType = lib.types.submodule ({ config, ... }: {
    options = {
      height = lib.mkOption {
        type = lib.types.int;
        default = 32;
        description = "The height of the panel.";
      };
      offset = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 100;
        description = "The offset of the panel from the anchor-point.";
      };
      minLength = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 1000;
        description = "The minimum required length/width of the panel.";
      };
      maxLength = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 1600;
        description = "The maximum allowed length/width of the panel.";
      };
      lengthMode = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "fit" "fill" "custom" ]);
        default =
          if config.minLength != null || config.maxLength != null then
            "custom"
          else
            null;
        example = "fit";
        description = "(Plasma 6 only) The length mode of the panel. Defaults to `custom` if either `minLength` or `maxLength` is set.";
      };
      location = lib.mkOption {
        type = lib.types.str;
        default = lib.types.nullOr (lib.types.enum [ "top" "bottom" "left" "right" "floating" ]);
        example = "left";
        description = "The location of the panel.";
      };
      alignment = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "left" "center" "right" ]);
        default = "center";
        example = "right";
        description = "The alignment of the panel.";
      };
      hiding = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [
          "none"
          "autohide"
          # Plasma 5 only
          "windowscover"
          "windowsbelow"
          # Plasma 6 only
          "dodgewindows"
          "normalpanel"
          "windowsgobelow"
        ]);
        default = null;
        example = "autohide";
        description = ''
          The hiding mode of the panel. Here windowscover and windowsbelow are
          plasma 5 only, while dodgewindows, windowsgobelow and normalpanel are
          plasma 6 only.
        '';
      };
      floating = lib.mkEnableOption "Enable or disable floating style (plasma 6 only).";
      widgets = lib.mkOption {
        type = lib.types.listOf widgets.type;
        default = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.pager"
          "org.kde.plasma.icontasks"
          "org.kde.plasma.marginsseperator"
          "org.kde.plasma.systemtray"
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
        example = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.icontasks"
          "org.kde.plasma.marginsseperator"
          "org.kde.plasma.digitalclock"
        ];
        description = ''
          The widgets to use in the panel. To get the names, it may be useful
          to look in the share/plasma/plasmoids folder of the nix-package the
          widget/plasmoid is from. Some packages which include some
          widgets/plasmoids are for example plasma-desktop and
          plasma-workspace.
        '';
        apply = map widgets.convert;
      };
      screen = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "The screen the panel should appear on";
      };
      extraSettings = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Extra lines to add to the layout.js. See
          https://develop.kde.org/docs/plasma/scripting/ for inspiration.
        '';
      };
    };
  });

  anyPanelOrWallpaperSet = ((cfg.workspace.wallpaper != null) ||
    (cfg.workspace.wallpaperSlideShow != null) ||
    (cfg.workspace.wallpaperPictureOfTheDay != null) ||
    ((builtins.length cfg.panels) > 0));
in
{
  options.programs.plasma.panels = lib.mkOption {
    type = lib.types.listOf panelType;
    default = [ ];
  };

  # Wallpaper and panels are in the same script since the resetting of the
  # panels in the panels-script also has a tendency to reset the wallpaper, so
  # these should run at the same time.
  config = (lib.mkIf cfg.enable {
    programs.plasma.startup.desktopScript."panels_and_wallpaper" = (lib.mkIf anyPanelOrWallpaperSet
      (
        let
          anyPanels = ((builtins.length cfg.panels) > 0);
          anyNonDefaultScreens = ((builtins.any (panel: panel.screen != 0)) cfg.panels);
          panelPreCMD = (if anyPanels then ''
            # We delete plasma-org.kde.plasma.desktop-appletsrc to hinder it
            # growing indefinitely. See:
            # https://github.com/pjones/plasma-manager/issues/76
            [ -f ${config.xdg.configHome}/plasma-org.kde.plasma.desktop-appletsrc ] && rm ${config.xdg.configHome}/plasma-org.kde.plasma.desktop-appletsrc
          '' else "");
          panelLayoutStr = (if anyPanels then (import ../lib/panel.nix { inherit lib; inherit config; }) else "");
          panelPostCMD = (if anyNonDefaultScreens then ''
            if [ -f ${config.xdg.configHome}/plasma-org.kde.plasma.desktop-appletsrc ]; then
              sed -i 's/^lastScreen\\x5b$i\\x5d=/lastScreen[$i]=/' ${config.xdg.configHome}/plasma-org.kde.plasma.desktop-appletsrc
              # We sleep a second in order to prevent some bugs (like the incorrect height being set)
              sleep 1; nohup plasmashell --replace &
            fi
          '' else "");
          # This meaningless comment inserts the URL into the desktop-script
          # which means that when the wallpaper is updated, the sha256 hash
          # changes and the script will be re-run.
          wallpaperDesktopScript = (if (cfg.workspace.wallpaper != null) then ''
            // Wallpaper to set later: ${cfg.workspace.wallpaper}
          '' else "");
          wallpaperPostCMD = (if (cfg.workspace.wallpaper != null) then ''
            plasma-apply-wallpaperimage ${cfg.workspace.wallpaper}
          '' else "");
          wallpaperSlideShow = (if (cfg.workspace.wallpaperSlideShow != null) then ''
            // Wallpaper slideshow
            let allDesktops = desktops();
            for (var desktopIndex = 0; desktopIndex < allDesktops.length; desktopIndex++) {
                var desktop = allDesktops[desktopIndex];
                desktop.wallpaperPlugin = "org.kde.slideshow";
                desktop.currentConfigGroup = Array("Wallpaper", "org.kde.slideshow", "General");
                desktop.writeConfig("SlidePaths", ${if (builtins.isPath cfg.workspace.wallpaperSlideShow.path) then
                  "\"" + cfg.workspace.wallpaperSlideShow.path + "\"" else
                  "[" + (builtins.concatStringsSep "," (map (s: "\"" + s + "\"") cfg.workspace.wallpaperSlideShow.path)) + "]"});
                desktop.writeConfig("SlideInterval", "${builtins.toString cfg.workspace.wallpaperSlideShow.interval}");
            }
          '' else "");
          wallpaperPOTD = (if (cfg.workspace.wallpaperPictureOfTheDay != null) then ''
            // Wallpaper POTD
            let allDesktops = desktops();
            for (const desktop of allDesktops) {
                desktop.wallpaperPlugin = "org.kde.potd";
                desktop.currentConfigGroup = ["Wallpaper", "org.kde.potd", "General"];
                desktop.writeConfig("Provider", "${cfg.workspace.wallpaperPictureOfTheDay.provider}");
                desktop.writeConfig("UpdateOverMeteredConnection", "${if (cfg.workspace.wallpaperPictureOfTheDay.updateOverMeteredConnection) then "1" else "0"}");
              }
          '' else ""
          );
        in
        {
          preCommands = panelPreCMD;
          text = panelLayoutStr + wallpaperDesktopScript + wallpaperSlideShow + wallpaperPOTD;
          postCommands = panelPostCMD + wallpaperPostCMD;
          priority = 2;
        }
      ));
  });
}

