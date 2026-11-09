{
  description = "KeePass multi-device synchronization engine with GCS, KeePassXC and Android";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "keepass-sync-devshell";

          buildInputs = with pkgs; [
            keepassxc
            rclone
            libsecret
            libnotify
            google-cloud-sdk
            jq
            inotify-tools
            coreutils
            util-linux
            findutils

            # Nix linting & formatting tools
            nixfmt
            statix
            deadnix
          ];

          shellHook = ''
            echo "🔐 Environnement KeePass Sync activé."
            echo "Outils disponibles : keepassxc-cli, rclone, secret-tool, notify-send, gcloud."
            echo "Tapez './scripts/keepass-sync.sh' pour tester la synchronisation."
          '';
        };
      }
    )
    // {
      # Exportable Home Manager module
      homeManagerModules.default = import ./nix/home-manager-module.nix;
      # Exportable NixOS module
      nixosModules.default = import ./nix/nixos-module.nix;
    };
}
