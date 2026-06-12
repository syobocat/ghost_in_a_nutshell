{
  description = "Build Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
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
        packages = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = packages.mkShell {
          buildInputs = with packages; [
            zig_0_16
            zip
          ];
        };

        pure = true;
      }
    );
}
