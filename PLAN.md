# Spacetime Playground: Schwarzschild Black Hole Ray Marcher

## Context

Build an interactive, real-time ray marcher that renders a Schwarzschild black hole with gravitational lensing. The project uses Rust + wgpu to target both native (Metal on Apple Silicon, leveraging unified memory) and WASM (WebGPU in browser). This is the first milestone of a larger spacetime simulator that will eventually include Alcubierre warp drive visualization and a game loop for designing warp bubble envelopes.

The repo is currently empty (just README + .gitignore). We're building from scratch.

## Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Language | Rust | Performance, safety, compiles to WASM |
| GPU | `wgpu` | Metal on macOS (unified memory), WebGPU in browser, Vulkan/DX12 elsewhere |
| Shaders | WGSL | wgpu's native shader language, works everywhere |
| Windowing | `winit` | Cross-platform, works in WASM via canvas |
| UI | `egui` + `egui-wgpu` + `egui-winit` | Parameter sliders, works native + WASM |
| Math | `glam` | Fast SIMD vector math |
| Serialization | `bytemuck` | Zero-cost GPU buffer casting |
| Async | `pollster` | Simple `block_on` for wgpu async (native only) |

## Architecture

```
spacetime-playground/
├── Cargo.toml
├── rust-toolchain.toml          # Pin toolchain, add wasm32 target
├── src/
│   ├── main.rs                  # Entry point, winit event loop
│   ├── app.rs                   # Application state, ties render + UI + input
│   ├── renderer/
│   │   ├── mod.rs
│   │   ├── pipeline.rs          # wgpu compute + render pipeline setup
│   │   ├── camera.rs            # Orbital camera with mouse controls
│   │   └── uniforms.rs          # GPU uniform buffer structs (bytemuck)
│   ├── metrics/
│   │   ├── mod.rs               # Trait/interface for spacetime metrics
│   │   └── schwarzschild.rs     # Schwarzschild parameters (mass, rs)
│   └── ui.rs                    # egui panels for parameter tuning
├── shaders/
│   ├── ray_march.wgsl           # Compute shader: full ray marcher
│   └── fullscreen.wgsl          # Vertex/fragment: blit compute texture to screen
├── web/
│   └── index.html               # WASM host page (later milestone)
```

## Physics: Schwarzschild Ray Tracing

### The Metric
Schwarzschild in coordinates (t, r, theta, phi):
```
ds² = -(1 - rs/r)dt² + (1 - rs/r)⁻¹dr² + r²(dθ² + sin²θ dφ²)
```
where `rs = 2GM/c²` is the Schwarzschild radius (set rs = 1 in natural units).

### Ray Tracing Strategy

Since Schwarzschild is spherically symmetric, every light ray orbit is planar. For each pixel:

1. **Cast ray** from camera through pixel into scene
2. **Compute impact parameter** `b = L/E` from the ray's closest approach geometry
3. **Rotate into equatorial plane** — exploit spherical symmetry so the ray lies in θ = π/2
4. **Integrate the orbit equation** for light (null geodesic):
   ```
   d²u/dφ² = -u + (3/2) rs u²
   ```
   where `u = 1/r`, using RK4. This is a single 1D second-order ODE (equivalently two first-order ODEs), very cheap per pixel.
5. **Terminate** when:
   - `r < rs` (ray captured by black hole) → render black / accretion disk color
   - `r > r_max` (ray escaped) → map final (θ_exit, φ_exit) to background
   - Max steps exceeded → fallback color
6. **Map exit direction** back from equatorial plane to 3D sky coordinates → sample a checkerboard celestial sphere or star texture

### Why This Works on GPU
The orbit equation is per-pixel independent — perfect for a compute shader. Each GPU thread traces one ray. The 1D ODE (u vs φ) needs ~100-500 RK4 steps, which is very fast in a compute shader.

### Uniform Buffer (CPU → GPU)
```rust
#[repr(C)]
struct Uniforms {
    camera_pos: [f32; 4],      // Camera position in Schwarzschild coords
    camera_forward: [f32; 4],  // View direction
    camera_up: [f32; 4],       // Up vector
    camera_right: [f32; 4],    // Right vector
    resolution: [f32; 2],      // Window size
    fov: f32,                  // Field of view
    rs: f32,                   // Schwarzschild radius
    max_steps: u32,            // RK4 iteration limit
    step_size: f32,            // dφ per RK4 step
    _padding: [f32; 2],
}
```

## Implementation Steps

### Step 1: Project Scaffold
- `cargo init` with proper dependencies in Cargo.toml
- Set up module structure (empty files with mod declarations)
- Verify it compiles

**Cargo.toml dependencies:**
```toml
[dependencies]
wgpu = "24"
winit = "0.30"
egui = "0.31"
egui-wgpu = "0.31"
egui-winit = "0.31"
glam = "0.29"
bytemuck = { version = "1", features = ["derive"] }
pollster = "0.4"
log = "0.4"
env_logger = "0.11"
```

### Step 2: Window + wgpu Surface
- Create winit window with event loop
- Initialize wgpu instance, adapter, device, queue
- Create surface and configure swap chain
- Render a solid color to confirm pipeline works

### Step 3: Compute Shader — Flat Space Ray Marcher
- Write `ray_march.wgsl` with a trivial ray marcher (no curvature yet)
- Cast rays from camera, intersect with a checkerboard sphere at r = 20
- Output to a storage texture
- Write `fullscreen.wgsl` to blit the texture to screen
- Set up the compute pipeline + render pipeline in `pipeline.rs`
- Verify: see a checkerboard sphere background from the camera

### Step 4: Add Schwarzschild Geodesic Integration
- In `ray_march.wgsl`, add the orbit equation integration:
  ```wgsl
  // For each ray, compute impact parameter b
  // Integrate: du/dφ = w, dw/dφ = -u + 1.5 * rs * u * u
  // Using RK4
  ```
- Compute impact parameter from ray direction and camera position
- Handle ray capture (u > 1/rs → black pixel)
- Handle ray escape (map exit angle to background)
- Verify: see gravitational lensing distortion of the checkerboard

### Step 5: Camera Controls
- Implement orbital camera in `camera.rs` (orbit around the black hole)
- Mouse drag to rotate, scroll to zoom
- Keyboard WASD for position adjustment
- Pass updated camera uniforms to GPU each frame

### Step 6: egui Integration
- Wire up egui-winit for input and egui-wgpu for rendering
- Add parameter panel:
  - Black hole mass / Schwarzschild radius slider
  - Camera distance slider
  - FOV slider
  - Step count / precision slider
  - Toggle: checkerboard vs star field background
- Overlay egui on top of the ray-marched output

### Step 7: Visual Polish (Future)
- Add an accretion disk (thin disk at equatorial plane)
- Color grading: Doppler shift / redshift visualization
- Better background (procedural star field or texture)

### Step 8: WASM Build (Future)
- Add `wasm-bindgen`, `web-sys` dependencies behind `#[cfg(target_arch = "wasm32")]`
- Create `web/index.html` with canvas element
- Set up `wasm-pack` build script
- Test in browser with WebGPU-capable browser

## Verification Plan
1. **Step 2**: Window opens, solid color renders → wgpu pipeline works
2. **Step 3**: Checkerboard sphere visible → ray casting + compute shader works
3. **Step 4**: Checkerboard distorts near center, black disk appears at Schwarzschild radius, Einstein ring visible at critical impact parameter `b = 3√3/2 rs ≈ 2.6 rs` → physics is correct
4. **Step 5**: Can orbit camera around black hole, lensing updates in real-time
5. **Step 6**: Sliders change black hole size and camera params in real-time
