# Home Manager installs packages, sets session variables and symlinks dotfiles.
# It does not generate the configs themselves — see home/dotfiles/.
{ config, pkgs, ... }:

let
  # mkOutOfStoreSymlink points at the WORKING TREE, so edits apply immediately
  # with no rebuild. The cost is a baked absolute path: this repo has to be
  # cloned here for the home configuration to be complete.
  repo = "${config.home.homeDirectory}/Developer/world/nix";
  dotfile = path: config.lib.file.mkOutOfStoreSymlink "${repo}/home/dotfiles/${path}";
in
{
  home.username = "dennis";
  home.homeDirectory = "/home/dennis";
  home.stateVersion = "26.05";

  # These land in /etc/profiles/per-user/dennis/bin, which is why that directory
  # has to be on elephant's PATH (modules/nixos/desktop.nix).
  home.packages = with pkgs; [
    claude-code

    chromium
    firefox

    vscode
    neovim
    lazygit
    gh

    tmux
    jq
    ripgrep
    fd
    bat
    eza
    zoxide
    fzf
    btop

    direnv
    nix-direnv
  ];

  # Whole directories, so a new config file appears without a rebuild.
  xdg.configFile = {
    "hypr".source = dotfile "hypr";
    "waybar".source = dotfile "waybar";
    "ghostty".source = dotfile "ghostty";
    "tmux".source = dotfile "tmux";
    "nvim".source = dotfile "nvim";
  };

  home.file.".zshrc".source = dotfile "zsh/zshrc";

  # Only settings.json is managed. The rest of ~/.claude is state — sessions,
  # projects, credentials — and must not be symlinked into the repo.
  # settings.local.json stays unmanaged too: it accumulates per-machine
  # permission grants that are not worth version-controlling.
  home.file.".claude/settings.json".source = dotfile "claude/settings.json";

  # Berkeley Mono is licensed, so it is gitignored — and a flake only copies
  # git-tracked files into the store, which means it can never be packaged as a
  # system font. Symlinking the working tree into the user font path sidesteps
  # the store the same way the dotfiles do; fontconfig scans this directory.
  home.file.".local/share/fonts/berkeley-mono".source =
    config.lib.file.mkOutOfStoreSymlink "${repo}/fonts/berkeley-mono";

  # The one typed module kept: includeIf makes work/personal identity splitting
  # nicer here than in raw gitconfig.
  programs.git = {
    enable = true;
    settings = {
      user.name = "Dennis";
      user.email = "denniswolfejr@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      rebase.autoStash = true;
      diff.algorithm = "histogram";
    };
  };

  programs.home-manager.enable = true;
}
