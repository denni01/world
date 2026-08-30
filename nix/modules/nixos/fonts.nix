# Fonts.
{ pkgs, ... }:

{
  fonts = {
    packages = with pkgs; [
      # Fallback monospace, and the glyphs waybar expects — Berkeley Mono ships
      # unpatched unless you bought the Nerd Font build.
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only

      inter
      noto-fonts
      noto-fonts-color-emoji
    ];

    # Berkeley Mono is not here: it is licensed and gitignored, so the flake
    # cannot see it. Home Manager installs it as a user font instead. This list
    # falls through to JetBrainsMono when it is absent, so a fresh clone still
    # renders sensibly rather than failing.
    fontconfig.defaultFonts = {
      monospace = [
        "Berkeley Mono"
        "JetBrainsMono Nerd Font"
      ];
      sansSerif = [
        "Inter"
        "Noto Sans"
      ];
      serif = [ "Noto Serif" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
