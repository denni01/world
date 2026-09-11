# Borderless Chromium windows for canned URLs, as launcher entries.
# `--app=URL` drops the tab strip, omnibox and frame. Uses the default profile.
{
  lib,
  pkgs,
  ...
}:

let
  # --class beats Chromium's derived "chrome-youtube.com__-Default" for
  # windowrules; StartupWMClass has to match it. Icons are absolute paths so no
  # icon-theme cache has to be regenerated.
  webapp =
    {
      name,
      url,
      icon,
      class,
    }:
    {
      inherit name icon;
      exec = "${lib.getExe pkgs.chromium} --app=${url} --class=${class}";
      categories = [ "Network" ];
      terminal = false;
      settings.StartupWMClass = class;
    };
in
{
  xdg.desktopEntries = {
    youtube = webapp {
      name = "YouTube";
      url = "https://youtube.com";
      class = "youtube";
      icon = "${./webapp-icons/youtube.svg}";
    };

    pihole = webapp {
      name = "Pi-hole";
      # / not /admin — pihole-web sets webhome = "/".
      url = "http://pi.hole:8080/";
      class = "pihole";
      icon = "${pkgs.pihole-web}/share/img/favicons/android-chrome-512x512.png";
    };
  };
}
