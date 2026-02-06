struct Uniforms {
    camera_pos: vec4<f32>,
    camera_forward: vec4<f32>,
    camera_up: vec4<f32>,
    camera_right: vec4<f32>,
    resolution: vec2<f32>,
    fov: f32,
    rs: f32,
    max_steps: u32,
    step_size: f32,
    disk_enabled: u32,
    disk_inner: f32,
    disk_outer: f32,
    background_mode: u32,
    time: f32,
    _padding: f32,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var output: texture_storage_2d<rgba8unorm, write>;

const PI: f32 = 3.14159265358979;
const SKY_RADIUS: f32 = 30.0;

// ── Background functions ──────────────────────────────────────────────

fn checkerboard(theta: f32, phi: f32) -> vec3<f32> {
    let u_coord = phi / (2.0 * PI);
    let v_coord = theta / PI;
    let checks = 20.0;
    let cx = floor(u_coord * checks);
    let cy = floor(v_coord * checks);
    let pattern = (cx + cy) % 2.0;
    if pattern < 0.5 {
        return vec3<f32>(0.1, 0.1, 0.3);
    } else {
        return vec3<f32>(0.9, 0.9, 1.0);
    }
}

// Hash function for procedural star field
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(127.1, 311.7)));
}

fn starfield(theta: f32, phi: f32) -> vec3<f32> {
    // Deep space background color
    var col = vec3<f32>(0.01, 0.01, 0.03);

    let uv = vec2<f32>(phi / (2.0 * PI), theta / PI);
    let grid_size = 80.0;
    let cell = floor(uv * grid_size);
    let cell_uv = fract(uv * grid_size);

    // Check 3x3 neighborhood for stars that might bleed into this cell
    for (var dx = -1i; dx <= 1i; dx = dx + 1i) {
        for (var dy = -1i; dy <= 1i; dy = dy + 1i) {
            let neighbor = cell + vec2<f32>(f32(dx), f32(dy));
            let star_pos = hash22(neighbor);
            let offset = star_pos - cell_uv + vec2<f32>(f32(dx), f32(dy));

            // Correct for aspect ratio of spherical projection
            let aspect = sin(theta + 0.001);
            let corrected = vec2<f32>(offset.x * aspect, offset.y);
            let dist = length(corrected) * grid_size;

            // Star brightness — only ~30% of cells have visible stars
            let brightness = hash21(neighbor + vec2<f32>(42.0, 17.0));
            if brightness > 0.7 {
                let star_bright = (brightness - 0.7) / 0.3;
                let glow = exp(-dist * dist * 8.0) * star_bright;

                // Star color variation
                let color_hash = hash21(neighbor + vec2<f32>(91.0, 53.0));
                var star_color = vec3<f32>(1.0, 1.0, 1.0);
                if color_hash < 0.3 {
                    star_color = vec3<f32>(0.8, 0.9, 1.0); // blue-white
                } else if color_hash < 0.5 {
                    star_color = vec3<f32>(1.0, 0.95, 0.8); // warm white
                } else if color_hash < 0.6 {
                    star_color = vec3<f32>(1.0, 0.7, 0.4); // orange
                }

                col = col + star_color * glow;
            }
        }
    }

    return col;
}

fn background(theta: f32, phi: f32) -> vec3<f32> {
    if u.background_mode == 1u {
        return starfield(theta, phi);
    }
    return checkerboard(theta, phi);
}

// ── Accretion disk coloring ───────────────────────────────────────────

// Black body approximation: temperature → RGB
fn blackbody(temp: f32) -> vec3<f32> {
    // Simplified blackbody for T in [1000, 40000] K range
    // Normalized so 6500K ≈ white
    let t = temp / 6500.0;
    var col: vec3<f32>;
    // Red channel
    if t < 0.55 {
        col.x = 1.0;
    } else {
        col.x = clamp(1.35 - 0.65 * (t - 0.55), 0.0, 1.0);
    }
    // Green channel
    if t < 0.5 {
        col.y = clamp(0.8 * t / 0.5, 0.0, 1.0);
    } else {
        col.y = clamp(1.0 - 0.3 * (t - 0.5), 0.0, 1.0);
    }
    // Blue channel
    if t < 0.6 {
        col.z = clamp(0.5 * t / 0.6, 0.0, 1.0);
    } else {
        col.z = 1.0;
    }
    return col;
}

fn disk_color(r: f32, azimuth: f32, rs: f32) -> vec3<f32> {
    let inner = u.disk_inner;
    let outer = u.disk_outer;

    // Radial temperature profile: T ~ r^(-3/4) for thin disk
    // Normalize so inner edge is hottest
    let t_normalized = pow(inner / r, 0.75);

    // Temperature range: ~20000K at inner edge → ~3000K at outer
    let temp = mix(2500.0, 20000.0, t_normalized);
    var col = blackbody(temp);

    // Brightness falls off with radius (luminosity ~ T^4 ~ r^-3)
    let brightness = pow(inner / r, 1.5);
    col = col * brightness * 2.5;

    // Doppler shift from orbital velocity
    // For circular Keplerian orbit: v = sqrt(rs / (2r)) in natural units
    let v_orb = sqrt(rs / (2.0 * r));

    // Doppler factor: approaching side is blueshifted, receding is redshifted
    // g = 1 / sqrt(1 - v²) / (1 + v * sin(azimuth))
    // Simplified: use first-order Doppler
    let doppler = 1.0 / (1.0 + v_orb * sin(azimuth));
    let doppler4 = doppler * doppler * doppler * doppler;

    // Apply Doppler beaming (I ~ g^4 for optically thick emission)
    col = col * clamp(doppler4, 0.1, 4.0);

    // Slight reddening near inner edge from gravitational redshift
    let grav_redshift = sqrt(1.0 - rs / r);
    col = col * grav_redshift;

    return col;
}

// ── Geometry helpers ──────────────────────────────────────────────────

fn dir_to_spherical(dir: vec3<f32>) -> vec2<f32> {
    let r = length(dir);
    let theta = acos(clamp(dir.y / r, -1.0, 1.0));
    let phi = atan2(dir.z, dir.x) + PI;
    return vec2<f32>(theta, phi);
}

// RK4 right-hand side for d²u/dφ² = -u + (3/2) rs u²
fn orbit_rhs_w(u_val: f32, rs: f32) -> f32 {
    return -u_val + 1.5 * rs * u_val * u_val;
}

// ── Main compute shader ──────────────────────────────────────────────

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let pixel = vec2<i32>(i32(id.x), i32(id.y));
    let dims = vec2<i32>(textureDimensions(output));

    if pixel.x >= dims.x || pixel.y >= dims.y {
        return;
    }

    // Normalized device coordinates [-1, 1]
    let ndc = vec2<f32>(
        (f32(pixel.x) + 0.5 - f32(dims.x) * 0.5) / (f32(dims.x) * 0.5),
        -(f32(pixel.y) + 0.5 - f32(dims.y) * 0.5) / (f32(dims.y) * 0.5),
    );

    // Ray direction in world space
    let aspect = f32(dims.x) / f32(dims.y);
    let half_fov = tan(u.fov * 0.5);
    let ray_dir = normalize(
        u.camera_forward.xyz
        + ndc.x * aspect * half_fov * u.camera_right.xyz
        + ndc.y * half_fov * u.camera_up.xyz
    );

    let cam_pos = u.camera_pos.xyz;
    let cam_r = length(cam_pos);
    let rs = u.rs;

    // Orbital plane basis
    let r_hat = cam_pos / cam_r;
    let cos_angle = dot(ray_dir, r_hat);
    let sin_angle = sqrt(max(1.0 - cos_angle * cos_angle, 0.0));

    // Initial conditions for geodesic integration
    var u_val = 1.0 / cam_r;
    var w_val = 0.0;
    if sin_angle > 1e-6 {
        w_val = cos_angle / (cam_r * sin_angle);
    }

    // Tangent vector in orbital plane (perpendicular to r_hat, in ray direction)
    var tangent = ray_dir - cos_angle * r_hat;
    let tang_len = length(tangent);
    if tang_len > 1e-6 {
        tangent = tangent / tang_len;
    } else {
        tangent = vec3<f32>(1.0, 0.0, 0.0);
    }

    let dphi = u.step_size;
    var phi_total = 0.0;
    var captured = false;
    var escaped = false;
    var final_u = u_val;

    // Accretion disk intersection tracking
    var hit_disk = false;
    var disk_r = 0.0;
    var disk_azimuth = 0.0;
    let initial_angle = atan2(sin_angle, -cos_angle);

    // Track y-component of 3D position for equatorial plane crossings
    var prev_y = 0.0;
    {
        let pos_angle = initial_angle;
        let pos_3d = (1.0 / u_val) * (cos(pos_angle) * (-r_hat) + sin(pos_angle) * tangent);
        prev_y = pos_3d.y;
    }

    // RK4 integration
    for (var i = 0u; i < u.max_steps; i = i + 1u) {
        // Check termination
        if u_val > 1.0 / rs {
            captured = true;
            break;
        }
        if u_val < 1.0 / SKY_RADIUS && w_val < 0.0 {
            escaped = true;
            final_u = u_val;
            break;
        }

        // RK4 step
        let k1_u = w_val;
        let k1_w = orbit_rhs_w(u_val, rs);

        let u2 = u_val + 0.5 * dphi * k1_u;
        let w2 = w_val + 0.5 * dphi * k1_w;
        let k2_u = w2;
        let k2_w = orbit_rhs_w(u2, rs);

        let u3 = u_val + 0.5 * dphi * k2_u;
        let w3 = w_val + 0.5 * dphi * k2_w;
        let k3_u = w3;
        let k3_w = orbit_rhs_w(u3, rs);

        let u4 = u_val + dphi * k3_u;
        let w4 = w_val + dphi * k3_w;
        let k4_u = w4;
        let k4_w = orbit_rhs_w(u4, rs);

        u_val = u_val + (dphi / 6.0) * (k1_u + 2.0 * k2_u + 2.0 * k3_u + k4_u);
        w_val = w_val + (dphi / 6.0) * (k1_w + 2.0 * k2_w + 2.0 * k3_w + k4_w);
        phi_total = phi_total + dphi;

        // Check for accretion disk crossing (equatorial plane y=0)
        if u.disk_enabled == 1u && !hit_disk {
            let current_angle = initial_angle + phi_total;
            let r_now = 1.0 / max(u_val, 1e-8);
            let pos_3d = r_now * (cos(current_angle) * (-r_hat) + sin(current_angle) * tangent);
            let cur_y = pos_3d.y;

            if prev_y * cur_y < 0.0 {
                // Crossed equatorial plane — check if within disk bounds
                if r_now > u.disk_inner && r_now < u.disk_outer {
                    hit_disk = true;
                    disk_r = r_now;
                    // Compute azimuthal angle in the equatorial plane for Doppler
                    disk_azimuth = atan2(pos_3d.z, pos_3d.x) + u.time * 0.5;
                }
            }
            prev_y = cur_y;
        }
    }

    if !captured && !escaped {
        if w_val < 0.0 {
            escaped = true;
            final_u = u_val;
        } else {
            captured = true;
        }
    }

    // ── Coloring ──

    var color = vec3<f32>(0.0, 0.0, 0.0);

    if hit_disk {
        // Accretion disk hit — use disk coloring with Doppler
        color = disk_color(disk_r, disk_azimuth, rs);

        // If the ray also escapes, blend a bit of background for transparency at edges
        if escaped {
            let edge_factor = smoothstep(u.disk_inner, u.disk_inner + 0.5 * rs, disk_r);
            let outer_fade = 1.0 - smoothstep(u.disk_outer - 2.0 * rs, u.disk_outer, disk_r);
            let opacity = edge_factor * outer_fade * 0.95 + 0.05;

            let exit_phi = initial_angle + phi_total;
            let exit_dir = cos(exit_phi) * (-r_hat) + sin(exit_phi) * tangent;
            let angles = dir_to_spherical(exit_dir);
            let bg = background(angles.x, angles.y);

            color = mix(bg, color, opacity);
        }
    } else if captured {
        // Black hole shadow
        color = vec3<f32>(0.02, 0.0, 0.0);
    } else {
        // Ray escaped — map exit angle to background
        let exit_phi = initial_angle + phi_total;
        let exit_dir = cos(exit_phi) * (-r_hat) + sin(exit_phi) * tangent;
        let angles = dir_to_spherical(exit_dir);
        color = background(angles.x, angles.y);
    }

    textureStore(output, pixel, vec4<f32>(color, 1.0));
}
