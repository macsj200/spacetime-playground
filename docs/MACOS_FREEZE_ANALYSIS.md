# macOS freeze: analysis of the introducing diff

The lockup started after commit **0b716d2** ("Add multi-body black hole support"). Below is what that commit actually changed and which parts are plausible suspects.

---

## 1. Diff summary (only things that can affect frame loop / GPU)

### pipeline.rs (render pipeline)

| Change | What it does | Suspect for lockup? |
|--------|----------------|---------------------|
| **body_buffer** | New storage buffer, 8 × GpuBody, `STORAGE \| COPY_DST` | **Yes** – new GPU resource, new binding |
| **Bind group layout binding 2** | Read-only storage buffer for `array<Body>` | **Yes** – Metal can be strict about storage |
| **Bind group entry for body_buffer** | Binds buffer to the compute pipeline | **Yes** – same |
| **update_bodies()** | `queue.write_buffer(&body_buffer, 0, bodies)` every frame | **Yes** – per-frame write on Metal; ordering/sync could block |

No other pipeline logic changed (dispatch, blit, submit order are the same).

### app.rs (per-frame work)

| Change | What it does | Suspect for lockup? |
|--------|----------------|---------------------|
| **simulation.step(dt)** | CPU N-body step | Unlikely – CPU only |
| **gpu_bodies()** | Builds `[GpuBody; MAX_BODIES]` | Unlikely – CPU only |
| **pipeline.update_bodies(&queue, &gpu_bodies)** | Calls `queue.write_buffer` for body buffer | **Yes** – only new GPU work per frame |
| **Uniforms**: `num_bodies`, `_padding[3]` instead of `rs`, `disk_inner`, `disk_outer` | Different uniform layout | Low – usually crash/wrong image, not hang |
| **Drop for App** | `device.poll(Maintain::Wait)` on drop | No – only on window close |

### main.rs

| Change | What it does | Suspect for lockup? |
|--------|----------------|---------------------|
| **CloseRequested** handled first, then `app = None; exit` | Clean shutdown | No – only when closing |
| **mod simulation** | New module | No |

### shaders/ray_march.wgsl

| Change | What it does | Suspect for lockup? |
|--------|----------------|---------------------|
| **Body struct + binding 2** | Shader reads `bodies[i]` in loops | **Maybe** – Metal could hang on bad/strict storage access |
| **Loops over u.num_bodies** | More work, more storage reads | **Maybe** – different GPU path |

---

## 2. Most plausible suspects (from the diff only)

1. **Per-frame `queue.write_buffer` for the body buffer**  
   New per-frame GPU submission. On Metal, this can interact badly with the next `get_current_texture()` or the next submit (sync, drawable pool, or internal serialization) and cause a stall or deadlock.

2. **Having a read-only storage buffer bound in the compute pass**  
   Metal may enforce different rules or have a bug with this pattern; first frame could succeed, later frames hang.

3. **Shader reading from the storage buffer**  
   Less likely than (1)–(2), but possible (e.g. driver bug when that buffer is written then read in a tight loop).

---

## 3. Minimal test to confirm

To see if the bug is in the **body buffer path** (write + bind + read), we can disable only the **per-frame write** on macOS and keep everything else (buffer, binding, shader) the same:

- On macOS: **do not call** `pipeline.update_bodies(...)` and set **num_bodies = 1** in uniforms.
- Body buffer stays at its initial (zeroed) contents; shader still runs and reads one “body” (zeros).
- If the freeze **disappears** → the per-frame **write_buffer** (or its timing) on Metal is the trigger.
- If the freeze **remains** → the issue is either the mere presence of the body buffer in the pipeline, or the shader, or something outside this diff (e.g. event loop).

No other changes from the multi-body diff are reverted; we only skip the body update and clamp to one body on macOS for this test.

---

## 4. Params to reduce GPU cost (when UI is locked, edit defaults and recompile)

| Param        | Where (default)     | Effect |
|-------------|----------------------|--------|
| **max_steps** | `app.rs` in `App::new()` | Max RK4 steps per ray. **Lower = less work.** macOS default set low (e.g. 80); raise to improve quality once responsive. |
| **step_size** | `app.rs` in `App::new()` | Step length along ray. **Higher = bigger steps = fewer steps to escape/capture = less work.** macOS default set higher (e.g. 0.4). |
| **disk_enabled** | `ui.rs` `UiState::default()` | Off = no disk crossing/color work. Already `false` by default. |
| **debug_checkerboard** | `ui.rs` `UiState::default()` | `true` = skip ray march entirely (checkerboard only); use to confirm UI/input. |

Binary-search: start with macOS defaults (low max_steps, high step_size). If still locked, lower max_steps further (e.g. 40) and/or raise step_size (e.g. 0.8). Once the app is responsive, raise max_steps / lower step_size until you find a good tradeoff.
