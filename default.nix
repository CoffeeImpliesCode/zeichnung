{ pkgs ? import <nixpkgs> {} }:
  with pkgs;
  mkShell rec {
    buildInputs = [
      pkg-config
      wayland
      wayland-protocols
      wayland-scanner
      egl-wayland
      # libGL
      libglvnd
      libdecor
      # libxkbcommon
      # vulkan-loader
      # vulkan-headers
      # vulkan-extension-layer
      # vulkan-validation-layers
      # pipewire
    ];
    LD_LIBRARY_PATH = "${lib.makeLibraryPath buildInputs}";
  }
