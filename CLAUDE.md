# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Real-time interactive Schwarzschild black hole ray marcher with gravitational lensing, built with Rust + wgpu. Renders light paths in curved spacetime using GPU compute shaders for per-pixel geodesic integration via RK4.

## Build & Run

```bash
cargo build                # Debug build
cargo build --release      # Optimized build
cargo run                  # Debug run
cargo run --release        # Release run (recommended - much faster rendering)
```

Rust stable toolchain is pinned via `rust-toolchain.toml`. Requires a GPU with Metal, Vulkan, or DX12 support. No test suite or linting configuration exists currently.

## Architecture

The app follows an event-driven architecture using winit's `ApplicationHandler` trait:

- **`src/main.rs`** - Entry point. Creates a `SpacetimeApp` wrapper that initializes `App` on window resume and dispatches events.
- **`src/app.rs`** - Central orchestrator. Holds all state (wgpu device/queue/surface, camera, physics params, egui context). The `render()` method runs each frame: updates camera, builds uniforms, runs egui UI, dispatches compute shader, blits result, renders egui overlay.
- **`src/renderer/pipeline.rs`** - Sets up wgpu compute + render pipelines and bind groups. `RayMarchPipeline` dispatches compute with 8x8 workgroups and renders a fullscreen blit.
- **`src/renderer/camera.rs`** - Orbital camera in spherical coordinates (distance, azimuth, elevation). Handles mouse drag rotation, scroll zoom, WASD pan.
- **`src/renderer/uniforms.rs`** - `Uniforms` struct (bytemuck Pod) sent to GPU each frame. Contains camera vectors, resolution, FOV, Schwarzschild radius, integration params, disk params, background mode, time.
- **`src/metrics/schwarzschild.rs`** - Physics parameters struct with computed properties: critical impact parameter, photon sphere radius, ISCO radius.
- **`src/ui.rs`** - egui panel with sliders for all tunable parameters.

### Shader Pipeline

- **`shaders/ray_march.wgsl`** - Compute shader (the core of the project). For each pixel: casts a ray, computes impact parameter b = L/E, integrates the null geodesic ODE `d²u/dφ² = -u + (3/2) rs u²` via RK4, detects disk crossings, applies Doppler/gravitational redshift, Novikov-Thorne luminosity, procedural turbulence (FBM), and ACES tonemapping.
- **`shaders/fullscreen.wgsl`** - Vertex/fragment shader that blits the compute output texture to screen using a fullscreen triangle.

### Data Flow Per Frame

1. Input events update `OrbitalCamera` state
2. Camera + `SchwarzschildParams` + `UiState` build a `Uniforms` struct
3. Uniforms written to GPU buffer
4. Compute shader traces rays per-pixel (each pixel independent)
5. Result stored in `Rgba16Float` storage texture
6. Fullscreen blit renders texture to screen
7. egui overlay rendered on top

## Physics Model

Uses Schwarzschild metric with spherical symmetry to reduce 3D ray tracing to a 1D ODE. All light rays are planar (equatorial plane). The orbit equation `u = 1/r` is integrated with RK4. Rays terminate when captured (r < rs), escaped, or max steps exceeded. The accretion disk uses a Novikov-Thorne thin-disk model with blackbody temperature profile and Keplerian velocity for Doppler shift.

## Key Dependencies

| Crate | Purpose |
|---|---|
| wgpu 24 | GPU abstraction (Metal/Vulkan/DX12/WebGPU) |
| winit 0.30 | Cross-platform windowing and input |
| egui 0.31 / egui-wgpu / egui-winit | Immediate-mode GUI for parameter sliders |
| glam 0.29 | SIMD vector math |
| bytemuck 1 | Zero-cost struct-to-bytes for GPU buffers |
| pollster 0.4 | Simple async block_on for wgpu initialization |

## Development Notes

- Shaders are loaded at build time via `include_str!` - changes to `.wgsl` files require recompilation.
- The `wasm32-unknown-unknown` target is configured but WASM support is not yet implemented (Step 8 in PLAN.md).
- The uniform buffer must maintain `#[repr(C)]` layout with proper alignment for GPU compatibility.
- Compute workgroup size is 8x8; dispatch dimensions are calculated from window resolution.
