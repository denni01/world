# Wayland desktop: Hyprland under UWSM, greetd for login, PipeWire for audio.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Offer only the UWSM session. programs.hyprland also registers a bare
  # `hyprland` one, which starts the compositor but never activates
  # graphical-session.target — so elephant, walker and xremap stay dead, with no
  # error anywhere. Anything wantedBy that target depends on this filtering.
  # If UWSM breaks, fall back to a TTY or an older generation.
  sessions = pkgs.runCommandLocal "hyprland-uwsm-session" { } ''
    mkdir -p $out/share/wayland-sessions
    cp ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions/hyprland-uwsm.desktop \
       $out/share/wayland-sessions/
  '';
in
{
  programs.hyprland = {
    enable = true;
    # Real systemd user session: environment propagation and per-app scoping.
    withUWSM = true;
    xwayland.enable = true;
  };

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = lib.concatStringsSep " " [
        (lib.getExe pkgs.tuigreet)
        "--time"
        "--remember"
        "--remember-session"
        "--sessions ${sessions}/share/wayland-sessions"
      ];
      user = "greeter";
    };
  };

  # The GTK portal supplies the file chooser; programs.hyprland adds its own.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Stops VS Code, Chromium and gh re-prompting for credentials every launch.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  security.polkit.enable = true;

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";

    # AQ_DRM_DEVICES is deliberately unset. Pinning the GPU is unnecessary (the
    # iGPU has no display attached) and aquamarine does not resolve symlinks in
    # it, so a by-path value yields no GPU at all and Hyprland aborts with
    # "CBackend::create() failed!". A real /dev/dri/cardN path would work, but
    # card numbering is not stable across boots.
    #
    # Also deliberately unset: GBM_BACKEND (breaks Firefox/Chromium on current
    # drivers) and WLR_NO_HARDWARE_CURSORS (wlroots-only). Both appear in older
    # guides.
  };

  environment.systemPackages = with pkgs; [
    waybar
    walker
    mako
    hyprlock
    hypridle
    hyprshot
    hyprpicker
    hyprpolkitagent

    wl-clipboard
    cliphist

    ghostty

    nautilus
    pavucontrol
    playerctl
    brightnessctl
    libnotify
  ];

  # walker is a thin client — every provider (desktop apps, calc, clipboard,
  # window switching) lives in elephant, and walker refuses to start without it.
  services.elephant.enable = true;

  # elephant launches apps by BARE COMMAND NAME, so its PATH is what every
  # launched application resolves against — including user packages, which live
  # outside the system path.
  systemd.user.services.elephant.environment.PATH = lib.mkForce (
    lib.concatStringsSep ":" [
      "/run/wrappers/bin"
      "/etc/profiles/per-user/dennis/bin"
      "/run/current-system/sw/bin"
    ]
  );

  # walker ships no D-Bus service file, so nothing activates it on demand.
  systemd.user.services.walker = {
    description = "walker application launcher service";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [
      "graphical-session.target"
      "elephant.service"
    ];
    path = [ pkgs.elephant ];
    serviceConfig = {
      ExecStart = "${pkgs.walker}/bin/walker --gapplication-service";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  systemd.user.services.hyprpolkitagent = {
    description = "Hyprland polkit authentication agent";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
      Restart = "on-failure";
    };
  };
}
