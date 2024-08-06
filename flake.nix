{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    systems.url = "github:nix-systems/x86_64-linux";

    flake-utils.url = "github:numtide/flake-utils";
    flake-utils.inputs.systems.follows = "systems";

    zig.url = "github:mitchellh/zig-overlay";
    zig.inputs.nixpkgs.follows = "nixpkgs";

    zls.url = "github:zigtools/zls";
    zls.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      flake-utils,
      zig,
      zls,
      nixpkgs,
      ...
    }:
    # Now eachDefaultSystem is only using ["x86_64-linux"], but this list can also
    # further be changed by users of your flake.
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        llvmPackages = pkgs.llvmPackages_18;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            zig.packages.${system}."0.13.0"
            zls.packages.${system}.default

            (pkgs.aflplusplus.override {
              llvm = pkgs.llvm_18;
              clang = llvmPackages.clang;
              inherit llvmPackages;
            })
            llvmPackages.clang
            llvmPackages.libcxxStdenv
            llvmPackages.libcxxClang
          ];
        };
      }
    );
}
