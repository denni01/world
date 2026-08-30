# Input: Apple keyboard behaviour and macOS-style key remapping.
#
# Three layers, which must stay disjoint because xremap intercepts at the evdev
# layer before the compositor sees a key:
#
#   xremap    macOS text bindings, rewritten to Ctrl — but NOT in terminals
#   Ghostty   handles Super+C/V itself; this is why terminals are excluded, as a
#             blind Super+C -> Ctrl+C would send SIGINT (likewise Ctrl+Z, Ctrl+R,
#             Ctrl+A, Ctrl+W and Ctrl+S)
#   Hyprland  everything xremap does not claim — window management only
#
# See home/dotfiles/hypr/bindings.conf for the other half.
{ inputs, ... }:

{
  imports = [ inputs.xremap.nixosModules.default ];

  # hid_apple already maps Cmd to Super, so no swapping is needed. fnmode=2 makes
  # F1-F12 primary with media on Fn. (Touch ID does not work on Linux.)
  boot.extraModprobeConfig = ''
    options hid_apple fnmode=2 swap_opt_cmd=0
  '';

  services.xremap = {
    enable = true;
    withHypr = true;
    # Must run as the user: app detection needs the session's Hyprland IPC
    # socket. The module supplies the uinput group and udev rule.
    serviceMode = "user";
    userName = "dennis";

    config.keymap = [
      {
        name = "macOS text editing (everything except terminals)";
        application.not = [
          "com.mitchellh.ghostty"
          "kitty"
          "foot"
          "Alacritty"
          "org.wezfurlong.wezterm"
        ];
        remap = {
          "SUPER-c" = "C-c";
          "SUPER-v" = "C-v";
          "SUPER-x" = "C-x";
          "SUPER-a" = "C-a";
          "SUPER-z" = "C-z";
          "SUPER-Shift-z" = "C-Shift-z";
          "SUPER-s" = "C-s";
          "SUPER-f" = "C-f";
          "SUPER-t" = "C-t";
          "SUPER-w" = "C-w";
          "SUPER-n" = "C-n";
          "SUPER-r" = "C-r";
          "SUPER-o" = "C-o";
          "SUPER-p" = "C-p";
          "SUPER-comma" = "C-comma";

          # Line and document ends, as on macOS.
          "SUPER-left" = "home";
          "SUPER-right" = "end";
          "SUPER-up" = "C-home";
          "SUPER-down" = "C-end";

          # Option+arrow moves by word.
          "ALT-left" = "C-left";
          "ALT-right" = "C-right";
        };
      }
    ];
  };
}
