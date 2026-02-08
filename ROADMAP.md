# Spacetime Playground — Roadmap

## Vision

Evolve the Schwarzschild black hole ray marcher into a real-time GR physics sandbox/game. Players operate in "god mode" — dropping black holes, stars, and exotic objects into scenes and watching spacetime respond. Long-term, gameplay mechanics emerge from the physics: designing Alcubierre warp drives, building gravitational telescopes, navigating wormholes.

## Current State

- Single Schwarzschild black hole with gravitational lensing
- Novikov-Thorne thin accretion disk with Doppler shift and redshift
- Orbital camera, egui parameter UI
- GPU compute shader (RK4 geodesic integration per pixel)
- Native only (Metal/Vulkan/DX12)

## Phase 1: Multi-Body Black Holes

**Goal:** Drop multiple black holes into the scene and watch them lens, orbit, and interact.

### Rendering: Superimposed Metrics

Modify the ray marcher ODE to sum gravitational potentials from N bodies:

```
d²u/dφ² = Σᵢ [-uᵢ + (3/2) rsᵢ uᵢ²]
```

This is physically approximate (GR is nonlinear) but produces visually convincing results: double lensing, overlapping Einstein rings, interacting shadows. Cost is just a for-loop over body positions inside the existing per-pixel shader — negligible for 2-5 bodies.

### Orbital Dynamics (CPU-side)

- **Start with Newtonian N-body** — symplectic integrator (leapfrog/Verlet) for stable long-term orbits
- **Add post-Newtonian corrections** — orbital precession, energy loss from gravitational wave emission, inspiral behavior
- Pass body positions + masses to GPU each frame via a storage buffer

### Interaction

- God-mode UI: click to place black holes, drag to set initial velocity
- Adjust masses via sliders or scroll wheel on selected body
- Pause/slow-motion/speed-up time controls
- Trails showing orbital paths

### Stretch: Tidal Disruption Events

- Drop a "star" (particle cloud or textured sphere) near a black hole
- Simulate tidal stretching via Roche lobe overflow approximation
- Visualize spaghettification with particle streams falling into the accretion disk

## Phase 2: Kerr Metric (Rotating Black Holes)

**Goal:** Replace Schwarzschild with Kerr for rotating black holes. Adds frame dragging, ergosphere, and spin-dependent shadow shapes.

### Physics Changes

The Kerr geodesic equations are a 4-ODE system (vs 2 for Schwarzschild) using the Carter constant:

```
Σ dr/dλ = ±√R(r)
Σ dθ/dλ = ±√Θ(θ)
Σ dφ/dλ = -(aE - Lz/sin²θ) + a T/Δ
Σ dt/dλ = -a(aE sin²θ - Lz) + (r² + a²)T/Δ
```

where `a = J/M` is the spin parameter. Rays are no longer planar — full 3D integration required.

### Rendering Impact

- Shadow shape becomes asymmetric (D-shaped at high spin)
- Frame dragging visibly rotates the lensing pattern
- Accretion disk gains a brighter approaching side (stronger Doppler boost)
- Ergosphere region can be visualized

### Implementation

- New shader path or parameterized shader (a=0 reduces to Schwarzschild)
- Spin parameter slider in UI
- Per-body spin in multi-body mode (each body can be Kerr)

## Phase 3: Alcubierre Warp Drive

**Goal:** Visualize an Alcubierre warp bubble from the inside and outside. Let players design the envelope (shape) function.

### The Metric

```
ds² = -dt² + (dx - vₛf(rₛ)dt)² + dy² + dz²
```

where `f(rₛ)` is the envelope function (1 inside the bubble, 0 outside, smooth transition), `vₛ` is the ship velocity, and `rₛ` is the distance from the bubble center.

### Envelope Designer

- UI to define `f(rₛ)`: shell thickness, transition steepness, bubble radius
- Presets: top-hat, Gaussian, tanh profiles
- Real-time preview of the spacetime distortion
- Visualize the "warp field" — contracted space ahead, expanded behind

### Views

- **External view:** Watch a warp bubble transit across a star field, see the characteristic lensing signature
- **Interior cockpit view:** Camera inside the flat-space bubble, looking out through the warped shell at a blue-shifted forward sky and red-shifted aft sky

### Physics Considerations

- Exotic matter / energy condition violations are part of the fun — show negative energy density regions
- Horizon problem: the bubble wall is causally disconnected from the interior at v > c

## Phase 4: Einstein-Rosen Bridges (Wormholes)

**Goal:** Traversable wormholes connecting two regions of spacetime.

### The Metric (Ellis/Morris-Thorne)

```
ds² = -dt² + dl² + (b₀² + l²)(dθ² + sin²θ dφ²)
```

where `l` is the proper radial coordinate through the throat and `b₀` is the throat radius. This is the simplest traversable wormhole — no tidal forces at the throat.

### Rendering

- Rays that reach the throat emerge on the "other side" — a different background/scene
- Two-mouth visualization: place both mouths in the same scene, see through one to the other
- Lensing around the throat produces a characteristic double-image pattern

### Interaction

- Place wormhole mouths in the scene
- Adjust throat radius
- Fly the camera through the wormhole

## Phase 5: Game Mechanics & Sandbox

**Goal:** Turn the physics into gameplay.

### Gravitational Telescope

- Use a black hole (or binary) as a gravitational lens to image distant/faint objects
- Gameplay: position your "detector" at the right focal point, adjust magnification by choosing the right lens mass
- Score based on image clarity/resolution achieved

### Warp Drive Engineering

- Given a destination and energy budget, design an Alcubierre envelope that gets you there
- Trade-offs: thinner shell = less exotic matter but more tidal stress on the ship
- Optimize for passenger comfort (minimize tidal forces inside the bubble)

### Sandbox Mode

- Free-form placement of all object types: black holes (Schwarzschild/Kerr), stars, wormholes, warp bubbles
- Save/load scenes
- Time controls (pause, slow-mo, fast-forward)
- Measurement tools: proper distance, redshift, tidal forces at a point

## Parallel Track: WASM/WebGPU

See [WASM_PLAN.md](WASM_PLAN.md) — run the entire app in the browser. This is independent of the physics roadmap and can be done at any point.

## Technical Notes

### Multi-Body Shader Architecture

The current shader hardcodes a single mass at the origin. For multi-body:

- Add a storage buffer with body data (position, mass, spin)
- Modify the geodesic integrator to sum contributions from all bodies
- The ODE becomes position-dependent (not just radius-dependent), so integration happens in Cartesian coordinates rather than the current `u = 1/r` substitution
- This is the biggest architectural change and should be done carefully

### Performance Budget

- Current: ~500 RK4 steps per pixel for single Schwarzschild
- Multi-body: ~500-1000 steps per pixel (more complex potential landscape)
- Kerr: ~500-800 steps (4 ODEs instead of 2, but same step count)
- Alcubierre: ~200-500 steps (weaker curvature outside the bubble)
- Target: 60fps at 1080p on a mid-range discrete GPU, 30fps on integrated

### Phase Dependencies

```
Phase 1 (Multi-body) ──→ Phase 5 (Game Mechanics)
Phase 2 (Kerr) ────────→ Phase 5
Phase 3 (Alcubierre) ──→ Phase 5
Phase 4 (Wormholes) ───→ Phase 5

Phases 1-4 are independent of each other.
WASM is independent of all phases.
```
