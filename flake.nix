{
  description = "";

  inputs = {
    nixpkgs.url = "nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
  in {
    # packages.${system} = {};

    formatter."${system}" = pkgs.alejandra;

    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        zig zls
      ];

    };
  };
}
