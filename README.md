# spacetime-playground

Real-time interactive Schwarzschild black hole ray marcher with gravitational lensing, built with Rust + wgpu.

## Prerequisites

- [Rust](https://rustup.rs/) (stable toolchain)
- A GPU with Metal (macOS), Vulkan, or DX12 support

## Running

```bash
cargo run
```

For an optimized build (much faster rendering):

```bash
cargo run --release
```

## Controls

| Input | Action |
|---|---|
| Left mouse drag | Orbit camera around black hole |
| Scroll wheel | Zoom in/out |
| WASD | Pan camera target |
| Tab | Toggle UI panel |

## UI Parameters

The egui panel (toggle with Tab) exposes:

- **Schwarzschild radius** - size of the black hole event horizon
- **Camera distance** - orbital radius
- **FOV** - field of view in radians
- **Max RK4 steps** - geodesic integration precision
- **Step size (dphi)** - integration step size
- **Checkerboard background** - toggle background pattern
