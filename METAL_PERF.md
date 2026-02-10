# Metal (macOS) Performance Issues — Diagnosis & Patches

## Problem

After the multi-body black hole rewrite (commit `0b716d2`), the app froze completely on macOS while continuing to work fine on Windows. Symptoms:

- Window totally unresponsive, "Recent hangs: 7" in Activity Monitor
- ~396 GB virtual memory reported
- Rest of the system lagged (WindowServer starved of GPU time)
- 1.27% CPU — main thread blocked waiting on GPU

## Root Causes

### 1. Compute shader too heavy for Metal's GPU watchdog

macOS enforces a strict GPU command timeout (~5 seconds). The multi-body rewrite made the per-pixel compute cost ~20x higher:

| | Old (1D ODE) | New (3D multi-body) |
|---|---|---|
| State variables | 2 scalars (u, w) | 6 floats (pos.xyz, vel.xyz) |
| RK4 cost per step | `−u + 1.5·rs·u²` (1 multiply, 1 add) | 4× `gravitational_acceleration()` with cross products, per-body loops |
| Escape condition | `u < 1/30 && w < 0` (instant) | `r > 50` from ALL bodies (almost never true early) |
| Default steps | 500 @ step_size 0.01 | 600 @ step_size 0.1 |

The escape condition was the biggest problem: with `ESCAPE_RADIUS = 50` and bodies spread across the scene, almost every pixel exhausted all 600 steps because rays couldn't get 50 units from every body. On Windows, the GPU driver is more lenient with timeouts (or the discrete GPU is faster), so this wasn't visible.

### 2. Command buffer resource accumulation

Without explicit `device.poll()`, Metal's completed command buffers weren't being retired. With `ControlFlow::Poll` driving continuous rendering, command buffers piled up faster than they were cleaned up.

### 3. Missing initial redraw on macOS

On macOS (unlike Windows), the windowing system doesn't automatically send `RedrawRequested` after window creation. Without the initial redraw, `render()` was never called, meaning the self-sustaining `request_redraw()` chain at the end of `render()` never started. The window appeared but showed no content.

## Patches Applied

### Shader (`shaders/ray_march.wgsl`)

- **Adaptive step sizing**: Steps scale from 1x (near event horizon) to 10x (far from all bodies), based on `min(r/rs)` across bodies. Most pixels in open space now take far fewer effective iterations.
- **Smarter escape check**: Rays escape when heading away from a body OR far enough (`r >= 30`), matching the old shader's approach. Previously required `r > 50` from ALL bodies simultaneously.
- **Reduced escape radius**: 50 → 30 (matching old `SKY_RADIUS`).

### App (`src/app.rs`)

- **Reduced default `max_steps`**: 600 → 200.
- **Added `device.poll(Maintain::Poll)`** after present to retire completed command buffers each frame.

### Event loop (`src/main.rs`)

- **Added `window.request_redraw()`** after app creation to kick off the render loop on macOS.

## Visual Quality Impact

The aggressive performance tuning (fewer steps, larger adaptive steps, smaller escape radius) noticeably reduces visual quality — lensing is less precise and the accretion disk has artifacts. This is a checkpoint; next step is finding a better quality/performance tradeoff, potentially via:

- Multi-pass rendering (split compute across frames)
- Resolution-dependent step counts
- Separate near-field / far-field integration strategies
- Platform-specific defaults (higher quality on Windows/discrete GPUs)
