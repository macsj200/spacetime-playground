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
@group(0) @binding(1) var output: texture_storage_2d<rgba16float, write>;

const PI: f32 = 3.14159265358979;
const SKY_RADIUS: f32 = 30.0;

// ── Hash / noise ──────────────────────────────────────────────────────

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(127.1, 311.7)));
}

// Smooth value noise for disk turbulence
fn value_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let sm = f * f * (3.0 - 2.0 * f); // smoothstep interpolation

    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));

    return mix(mix(a, b, sm.x), mix(c, d, sm.x), sm.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i = i + 1) {
        val = val + amp * value_noise(pos);
        pos = pos * 2.3 + vec2<f32>(1.7, 3.2);
        amp = amp * 0.5;
    }
    return val;
}

// ── Background ────────────────────────────────────────────────────────

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

fn starfield(theta: f32, phi: f32) -> vec3<f32> {
    var col = vec3<f32>(0.003, 0.003, 0.006);

    let uv = vec2<f32>(phi / (2.0 * PI), theta / PI);
    let grid_size = 80.0;
    let cell = floor(uv * grid_size);
    let cell_uv = fract(uv * grid_size);

    for (var dx = -1i; dx <= 1i; dx = dx + 1i) {
        for (var dy = -1i; dy <= 1i; dy = dy + 1i) {
            let neighbor = cell + vec2<f32>(f32(dx), f32(dy));
            let star_pos = hash22(neighbor);
            let offset = star_pos - cell_uv + vec2<f32>(f32(dx), f32(dy));

            let aspect = sin(theta + 0.001);
            let corrected = vec2<f32>(offset.x * aspect, offset.y);
            let dist = length(corrected) * grid_size;

            let brightness = hash21(neighbor + vec2<f32>(42.0, 17.0));
            if brightness > 0.7 {
                let star_bright = (brightness - 0.7) / 0.3;
                let glow = exp(-dist * dist * 12.0) * star_bright;

                let color_hash = hash21(neighbor + vec2<f32>(91.0, 53.0));
                var star_color = vec3<f32>(1.0, 0.98, 0.95);
                if color_hash < 0.12 {
                    star_color = vec3<f32>(0.85, 0.92, 1.0);
                } else if color_hash < 0.35 {
                    star_color = vec3<f32>(1.0, 0.95, 0.85);
                } else if color_hash < 0.55 {
                    star_color = vec3<f32>(1.0, 0.85, 0.6);
                } else if color_hash < 0.72 {
                    star_color = vec3<f32>(1.0, 0.7, 0.4);
                } else if color_hash < 0.85 {
                    star_color = vec3<f32>(1.0, 0.5, 0.3);
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

// ── Accretion disk ────────────────────────────────────────────────────

// Tanner Helland blackbody approximation
fn blackbody(temp: f32) -> vec3<f32> {
    let t = temp / 100.0;
    var r: f32;
    var g: f32;
    var b: f32;

    if t <= 66.0 {
        r = 1.0;
        g = clamp(0.39008 * log(t) - 0.63184, 0.0, 1.0);
    } else {
        r = clamp(1.2929 * pow(t - 60.0, -0.1332), 0.0, 1.0);
        g = clamp(1.1298 * pow(t - 60.0, -0.0755), 0.0, 1.0);
    }

    if t >= 66.0 {
        b = 1.0;
    } else if t <= 19.0 {
        b = 0.0;
    } else {
        b = clamp(0.5432 * log(t - 10.0) - 1.1962, 0.0, 1.0);
    }

    return vec3<f32>(r, g, b);
}

// Procedural disk detail: rings, spiral structure, turbulence
fn disk_detail(r: f32, azimuth: f32, rs: f32) -> f32 {
    let rn = r / rs; // normalized radius
    var detail = 1.0;

    // Concentric ring structure (density waves)
    detail *= 0.85 + 0.15 * sin(rn * 25.0);
    detail *= 0.92 + 0.08 * sin(rn * 63.0 + 1.3);
    detail *= 0.96 + 0.04 * sin(rn * 150.0 + 0.7);

    // Spiral density waves
    let spiral1 = sin(azimuth * 2.0 - rn * 5.0 + u.time * 0.3);
    let spiral2 = sin(azimuth * 3.0 + rn * 3.0 - u.time * 0.15);
    detail *= 0.90 + 0.10 * spiral1;
    detail *= 0.95 + 0.05 * spiral2;

    // Fine turbulence (fbm noise)
    let noise_uv = vec2<f32>(rn * 8.0, azimuth * 4.0 / PI);
    let turb = fbm(noise_uv);
    detail *= 0.80 + 0.20 * turb;

    // Hot spots near inner edge
    let inner_turb = fbm(vec2<f32>(azimuth * 6.0 / PI + u.time * 0.2, rn * 20.0));
    let inner_weight = exp(-(rn - u.disk_inner / rs) * 2.0);
    detail += inner_turb * inner_weight * 0.3;

    return max(detail, 0.0);
}

fn disk_color(r: f32, azimuth: f32, rs: f32) -> vec3<f32> {
    let inner = u.disk_inner;

    // Novikov-Thorne luminosity profile for thin disk
    // L(r) ~ 1/r² * (1 - sqrt(r_isco/r)) for r > r_isco
    let r_isco = 3.0 * rs;
    var luminosity: f32;
    if r > r_isco {
        luminosity = (1.0 / (r * r)) * (1.0 - sqrt(r_isco / r));
    } else {
        luminosity = 0.0;
    }
    // Normalize so peak luminosity ≈ 1
    let r_peak = r_isco * 49.0 / 36.0; // peak of Novikov-Thorne profile
    let l_peak = (1.0 / (r_peak * r_peak)) * (1.0 - sqrt(r_isco / r_peak));
    luminosity = luminosity / max(l_peak, 0.001);

    // Temperature profile: T ~ (L/r²)^(1/4) ~ r^(-3/4) approximately
    let t_normalized = pow(clamp(inner / r, 0.0, 1.0), 0.75);
    let temp = mix(1500.0, 6500.0, t_normalized);
    var col = blackbody(temp);

    // Apply luminosity and detail
    let detail = disk_detail(r, azimuth, rs);
    col = col * luminosity * detail * 3.0;

    // Doppler shift from Keplerian orbital velocity: v = sqrt(M/r) = sqrt(rs/(2r))
    let v_orb = sqrt(rs / (2.0 * r));
    let doppler = 1.0 / (1.0 + v_orb * sin(azimuth));
    let doppler3 = doppler * doppler * doppler;
    col = col * clamp(doppler3, 0.1, 4.0);

    // Gravitational redshift
    let grav_redshift = sqrt(max(1.0 - rs / r, 0.001));
    col = col * grav_redshift;

    return col;
}

// ── Geometry / integration ────────────────────────────────────────────

fn dir_to_spherical(dir: vec3<f32>) -> vec2<f32> {
    let r = length(dir);
    let theta = acos(clamp(dir.y / r, -1.0, 1.0));
    let phi = atan2(dir.z, dir.x) + PI;
    return vec2<f32>(theta, phi);
}

fn orbit_rhs_w(u_val: f32, rs: f32) -> f32 {
    return -u_val + 1.5 * rs * u_val * u_val;
}

// ACES filmic tonemapping
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Main compute shader ──────────────────────────────────────────────

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let pixel = vec2<i32>(i32(id.x), i32(id.y));
    let dims = vec2<i32>(textureDimensions(output));

    if pixel.x >= dims.x || pixel.y >= dims.y {
        return;
    }

    let ndc = vec2<f32>(
        (f32(pixel.x) + 0.5 - f32(dims.x) * 0.5) / (f32(dims.x) * 0.5),
        -(f32(pixel.y) + 0.5 - f32(dims.y) * 0.5) / (f32(dims.y) * 0.5),
    );

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

    let r_hat = cam_pos / cam_r;
    let cos_angle = dot(ray_dir, r_hat);
    let sin_angle = sqrt(max(1.0 - cos_angle * cos_angle, 0.0));

    var u_val = 1.0 / cam_r;
    var w_val = 0.0;
    if sin_angle > 1e-6 {
        w_val = -cos_angle / (cam_r * sin_angle);
    }

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

    // Disk: accumulate color from multiple equatorial crossings
    var disk_color_accum = vec3<f32>(0.0);
    var disk_opacity_accum = 0.0;
    var disk_crossings = 0u;

    let initial_angle = atan2(sin_angle, -cos_angle);
    var prev_y = cam_pos.y;
    var prev_u = u_val;
    var prev_phi = 0.0;

    // RK4 integration
    for (var i = 0u; i < u.max_steps; i = i + 1u) {
        if u_val > 1.0 / rs {
            captured = true;
            break;
        }
        if u_val < 1.0 / SKY_RADIUS && w_val < 0.0 {
            escaped = true;
            break;
        }

        // Store pre-step values for interpolation
        let u_before = u_val;
        let phi_before = phi_total;

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

        // Disk crossing detection with sub-step interpolation
        if u.disk_enabled == 1u {
            let r_now = 1.0 / max(u_val, 1e-8);
            let pos_3d = r_now * (cos(phi_total) * r_hat + sin(phi_total) * tangent);
            let cur_y = pos_3d.y;

            if prev_y * cur_y < 0.0 {
                // Interpolate exact crossing point
                let t_cross = abs(prev_y) / (abs(prev_y) + abs(cur_y));
                let cross_phi = phi_before + t_cross * dphi;
                let cross_u = u_before + t_cross * (u_val - u_before);
                let cross_r = 1.0 / max(cross_u, 1e-8);
                let cross_pos = cross_r * (cos(cross_phi) * r_hat + sin(cross_phi) * tangent);

                if cross_r > u.disk_inner && cross_r < u.disk_outer {
                    let azimuth = atan2(cross_pos.z, cross_pos.x) + u.time * 0.5;
                    let col = disk_color(cross_r, azimuth, rs);

                    // Edge opacity
                    let inner_fade = smoothstep(u.disk_inner, u.disk_inner + 0.3 * rs, cross_r);
                    let outer_fade = 1.0 - smoothstep(u.disk_outer - 2.0 * rs, u.disk_outer, cross_r);
                    var opacity = inner_fade * outer_fade;

                    // Higher-order images (photon ring) are thinner but we render them
                    // at full brightness — they're actually amplified by lensing
                    if disk_crossings > 0u {
                        opacity = opacity * 0.8;
                    }

                    // Composite over previous crossings
                    let remaining = 1.0 - disk_opacity_accum;
                    disk_color_accum = disk_color_accum + col * opacity * remaining;
                    disk_opacity_accum = min(disk_opacity_accum + opacity * remaining, 1.0);
                    disk_crossings = disk_crossings + 1u;
                }
            }
            prev_y = cur_y;
        }
    }

    if !captured && !escaped {
        if w_val < 0.0 {
            escaped = true;
        } else {
            captured = true;
        }
    }

    // ── Coloring ──

    var color = vec3<f32>(0.0);

    if disk_crossings > 0u {
        if escaped {
            let exit_phi = initial_angle + phi_total;
            let exit_dir = cos(exit_phi) * (-r_hat) + sin(exit_phi) * tangent;
            let angles = dir_to_spherical(exit_dir);
            let bg = background(angles.x, angles.y);
            color = mix(bg, disk_color_accum, disk_opacity_accum);
        } else {
            color = disk_color_accum;
        }
    } else if captured {
        // Pure black shadow
        color = vec3<f32>(0.0);
    } else {
        let exit_phi = initial_angle + phi_total;
        let exit_dir = cos(exit_phi) * (-r_hat) + sin(exit_phi) * tangent;
        let angles = dir_to_spherical(exit_dir);
        color = background(angles.x, angles.y);
    }

    // ACES tonemapping for HDR → display
    color = aces(color);

    // Gamma correction (linear → sRGB)
    color = pow(color, vec3<f32>(1.0 / 2.2));

    textureStore(output, pixel, vec4<f32>(color, 1.0));
}
