# zeichnung

`zeichnung` is a stalled Zig `0.0.0` prototype. It opens a Wayland window and renders an OpenGL triangle through EGL and glad. `build.zig.zon` declares no minimum Zig version; do not infer the old 0.16.0 pin from legacy guidance.

## Structure and contracts

- `build.zig` generates Wayland bindings, compiles glad, links Wayland EGL and EGL, and builds the executable. `default.nix` supplies Wayland, protocols, scanner, EGL Wayland, and libglvnd.
- `src/root.zig` owns the registry, EGL display/context, window surface, input, and timer. `src/main.zig` loads GL functions and shaders, creates buffers, and runs the triangle loop.
- `shader/quad.vert` and `shader/quad.frag` are runtime inputs. `glad/` is generated GL loader code; `EGL/` has local EGL headers.
- Target Linux Wayland. Initialization needs a compositor, seat, SHM, and XDG window-manager base. Keep protocol versions aligned: compositor 6, SHM 1, XDG shell 6, seat 8.
- The EGL context requests desktop OpenGL 4.6. Keep `wayland-egl`/`EGL` links, glad C source, and runtime `libGL.so` load aligned.
- `src/main.zig` changes to `/home/janis/projects/zeichnung` before opening `shader/`. If the repository moves, update this behavior and both shader paths together.
- `glad/src/gl.c` is C; do not apply C analyzers to Zig sources.

## Commands

- `nix-shell` enters the dependency environment; `zig build` builds and installs; `zig build run` runs the triangle demo.
- The build graph has no test step.
