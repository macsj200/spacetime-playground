# Plan: Run Spacetime Playground in the Browser (WASM/WebGPU)

## Context

The black hole ray marcher currently runs natively via wgpu on Metal/Vulkan/DX12. The goal is to make it compile to WASM and run in the browser using WebGPU. The good news: **~60% of the code needs zero changes** (shaders, pipeline setup, camera math, physics, UI). The changes are concentrated in initialization and the entry point.

**Build tool:** [Trunk](https://trunkrs.dev/) — purpose-built for Rust WASM apps. Handles wasm-bindgen, asset bundling, and dev server automatically.

**Browser requirement:** Chrome 113+, Edge 113+, or Firefox 141+ (WebGPU support).

## What stays unchanged

- `shaders/ray_march.wgsl` and `shaders/fullscreen.wgsl` — standard WGSL, fully WebGPU compatible
- `src/renderer/pipeline.rs` — standard wgpu API, works on web
- `src/renderer/camera.rs` — winit input types work on web
- `src/renderer/uniforms.rs` — pure bytemuck struct
- `src/metrics/schwarzschild.rs` — pure math
- `src/ui.rs` — pure egui API

## Changes (6 items, in order)

### 1. Update `Cargo.toml`

Add a `[lib]` section (trunk builds a cdylib), move `pollster`/`env_logger` to native-only, add web deps:

```toml
[lib]
crate-type = ["cdylib", "rlib"]

[dependencies]
wgpu = "24"
winit = "0.30"
egui = "0.31"
egui-wgpu = "0.31"
egui-winit = "0.31"
glam = "0.29"
bytemuck = { version = "1", features = ["derive"] }
log = "0.4"
web-time = "1"              # cross-platform Instant (works on native too)

[target.'cfg(not(target_arch = "wasm32"))'.dependencies]
pollster = "0.4"
env_logger = "0.11"

[target.'cfg(target_arch = "wasm32")'.dependencies]
wasm-bindgen = "0.2"
wasm-bindgen-futures = "0.4"
web-sys = { version = "0.3", features = ["Document", "Window", "Element", "HtmlCanvasElement"] }
console_log = "1"
console_error_panic_hook = "0.1"
```

Note: `web-time` replaces `std::time::Instant` on both platforms (it re-exports `std::time::Instant` on native, uses `performance.now()` on WASM). This avoids `#[cfg]` blocks everywhere we use `Instant`.

### 2. Create `src/lib.rs` — new crate root

Move `SpacetimeApp` and the `ApplicationHandler` impl from `main.rs` into `lib.rs`. Key additions:

- All `mod` declarations (`mod app; mod metrics; mod renderer; mod ui;`)
- A `pub fn run()` function containing the event loop setup
- Platform-conditional logging init (`env_logger` vs `console_log`)
- Platform-conditional window creation (canvas attachment on WASM)
- Platform-conditional async App init (`pollster::block_on` vs `wasm_bindgen_futures::spawn_local`)
- A `#[cfg(target_arch = "wasm32")] #[wasm_bindgen::prelude::wasm_bindgen(start)]` entry point that calls `run()`

**Async init pattern (WASM):** Since `App::new()` becomes async and WASM can't block, use `Rc<RefCell<Option<App>>>` shared between `SpacetimeApp` and the `spawn_local` closure. On each `window_event`, check if the pending app is ready via `.borrow_mut().take()`. This is safe because WASM is single-threaded.

**Canvas attachment (WASM):** In `resumed()`, use `winit::platform::web::WindowAttributesExtWebSys::with_canvas()` to attach the winit window to the `<canvas id="canvas">` element in the HTML.

### 3. Simplify `src/main.rs`

Reduce to just:
```rust
fn main() {
    spacetime_playground::run();
}
```

### 4. Modify `src/app.rs`

Three changes:
- **Make `App::new()` async** — replace `pollster::block_on(...)` with `.await` (2 call sites: `request_adapter` and `request_device`)
- **Replace `std::time::Instant`** with `web_time::Instant` (import change only, same API)
- **Conditional backends** — use `wgpu::Backends::BROWSER_WEBGPU` on WASM, `wgpu::Backends::all()` on native

### 5. Create `.cargo/config.toml`

Required for `web-sys` WebGPU API access:
```toml
[target.wasm32-unknown-unknown]
rustflags = ["--cfg=web_sys_unstable_apis"]
```

### 6. Create `index.html` (Trunk template)

Minimal HTML with a fullscreen `<canvas id="canvas">`, CSS for no margins/scrollbars, a `<link data-trunk rel="rust" data-wasm-opt="z" />` directive for Trunk, and a WebGPU support check that shows a message on unsupported browsers.

## Build & run commands

```bash
# Install trunk (one-time)
cargo install trunk

# Native (unchanged)
cargo run --release

# Web — dev server with auto-rebuild
trunk serve --open

# Web — production build (outputs to dist/)
trunk build --release
```

## Verification

1. `cargo run --release` — confirm native still works identically
2. `cargo build --target wasm32-unknown-unknown` — confirm WASM compiles
3. `trunk serve --open` — opens browser, should see the black hole render in the canvas
4. Resize browser window — should resize correctly
5. Mouse drag / scroll / WASD — camera controls should work
6. egui panel — sliders should appear and function
7. Tab key — should toggle UI visibility

## Risks & notes

- **WebGPU browser support is still limited** — Safari support is partial. The HTML page will show a fallback message on unsupported browsers.
- **WASM binary size** may be several MB. The `data-wasm-opt="z"` flag in index.html helps. For further reduction, add `lto = true` and `opt-level = "s"` to `[profile.release]`.
- **`ControlFlow::Poll`** on web is fine — winit uses `requestAnimationFrame` internally on WASM regardless.
- **First frame** may have 0x0 size on web — the existing `.max(1)` guards handle this, and the subsequent resize event corrects it.
