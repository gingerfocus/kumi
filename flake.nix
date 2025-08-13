{
  description = "";

  inputs.nixpkgs.url = "nixpkgs"; # use the system nixpkgs if not locked

  outputs = {
    self,
    nixpkgs,
  }: let
    lib = nixpkgs.lib;
    systems = ["aarch64-linux" "x86_64-linux"];
    eachSystem = f:
      lib.foldAttrs lib.mergeAttrs {}
      (map (s: lib.mapAttrs (_: v: {${s} = v;}) (f s)) systems);
  in
    eachSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      packages.default = pkgs.stdenv.mkDerivation {
        pname = "kumi";
        version = "0.0.1";

        nativeBuildInputs = with pkgs; [
          # zig.hook
        ];
        buildInputs = with pkgs; [];

        src = ./.;

        # buildPhase = "${pkgs.zig}/bin/zig build --prefix $out --cache-dir /build/zig-cache --global-cache-dir /build/global-cache -Doptimize=ReleaseSmall";

        meta = {
          maintainers = ["Evan Stokdyk <evan.stokdyk@gmail.com>"];
          description = "An init system based on sinit";
        };
      };
    });
}
