# Modules shared by every host. Host-specific settings live in ../../hosts/<name>.
{
  imports = [
    ./boot.nix
    ./networking.nix
    ./nvidia.nix
    ./desktop.nix
    ./docker.nix
    ./filesystems.nix
    ./fonts.nix
    ./input.nix
    ./performance.nix
    ./pihole.nix
  ];
}
