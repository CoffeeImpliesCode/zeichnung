# zeichnung

## Project

`zeichnung` is a stalled `0.0.0` Zig prototype. It opens a Wayland window and renders an OpenGL triangle through EGL and glad.

`build.zig.zon` does not declare a minimum Zig version. Do not infer the old 0.16.0 pin from legacy guidance.

## Layout

- `build.zig` generates Wayland bindings, compiles glad, links Wayland EGL and EGL, and builds the `zeichnung` executable.
- `src/root.zig` owns the Wayland registry, EGL display and context, window surface, input events, and timer.
- `src/main.zig` loads OpenGL functions and shaders, creates buffers, and runs the triangle loop.
- `shader/quad.vert` and `shader/quad.frag` are runtime shader inputs.
- `glad/` contains the generated OpenGL loader. `EGL/` contains the local EGL and Wayland EGL headers.
- `default.nix` supplies Wayland, Wayland protocols, the scanner, EGL Wayland, and libglvnd.

## Contracts

- Target a Linux Wayland session. Initialization requires a compositor, seat, SHM, and XDG window-manager base.
- Keep the generated protocol versions aligned with the bindings: compositor 6, SHM 1, XDG shell 6, and seat 8.
- The EGL context requests desktop OpenGL 4.6.
- Keep the `wayland-egl` and `EGL` links, the glad C source, and the runtime `libGL.so` load aligned.
- `src/main.zig` currently changes the working directory to `/home/janis/projects/zeichnung` before it opens `shader/`. Update that behavior and both shader paths together if the repository moves.
- Treat `glad/src/gl.c` as C code. Do not apply C analyzers to Zig sources.

## Commands

- Enter the dependency shell: `nix-shell`
- Build and install the executable: `zig build`
- Build and run the triangle demo: `zig build run`
- The build graph defines no test step.

## NixOS, Development Environment & Shared Notes

- This host runs NixOS. Never install system or development libraries imperatively.
- Declare dependencies, headers, runtime libraries, and tools in `default.nix`.
- Use this repository's `default.nix` environment with `nix-shell`.
- Put durable architecture, design, protocol, and experiment notes in this repository's `docs/` directory.
- Put cross-project or private agent handoff notes in `~/.agents/agent-notes/`. Do not commit those notes.
