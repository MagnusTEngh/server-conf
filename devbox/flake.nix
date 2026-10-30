{
  description = "Minimal hardened NixOS dev box (SSH over Tailscale)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.devbox = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux"; # use "aarch64-linux" on ARM
      modules = [
        ./configuration.nix

        # Pin `nix shell nixpkgs#foo` etc. to the same nixpkgs as the system.
        { nix.registry.nixpkgs.flake = nixpkgs; }
      ];
    };
  };
}