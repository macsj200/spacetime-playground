struct Uniforms {
    camera_pos: vec4<f32>,
    camera_forward: vec4<f32>,
    camera_up: vec4<f32>,
    camera_right: vec4<f32>,
    resolution: vec2<f32>,
    fov: f32,
    num_bodies: u32,
    max_steps: u32,
    step_size: f32,
    disk_enabled: u32,
    background_mode: u32,
    time: f32,
    grid_enabled: u32,
    _pad0: f32,
    _pad1: f32,
};

struct Body {
    position: vec4<f32>,
    rs: f32,
    disk_inner: f32,
    disk_outer: f32,
    _padding: f32,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var output: texture_storage_2d<rgba16float, write>;
@group(0) @binding(2) var<storage, read> bodies: array<Body>;

const PI: f32 = 3.14159265358979;
const MAX_BODIES: u32 = 8u;
const ESCAPE_RADIUS: f32 = 50.0;

// ── Hash / noise ──────────────────────────────────────────────────────

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(127.1, 311.7)));
}

fn value_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let sm = f * f * (3.0 - 2.0 * f);

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

// Cartesian 3D grid: lines at x,y,z = n*spacing. Returns line strength (0..1) at a world-space position.
// The grid lives in flat space; we sample it along the curved ray path so it appears distorted.
fn grid_strength_at_pos(P: vec3<f32>) -> f32 {
    let spacing = 12.0;
    let line_width = 0.12;

    let to_line_x = spacing * length(vec2<f32>(fract(P.y / spacing + 0.5) - 0.5, fract(P.z / spacing + 0.5) - 0.5));
    let to_line_y = spacing * length(vec2<f32>(fract(P.x / spacing + 0.5) - 0.5, fract(P.z / spacing + 0.5) - 0.5));
    let to_line_z = spacing * length(vec2<f32>(fract(P.x / spacing + 0.5) - 0.5, fract(P.y / spacing + 0.5) - 0.5));

    let line_x = 1.0 - smoothstep(0.0, line_width, to_line_x);
    let line_y = 1.0 - smoothstep(0.0, line_width, to_line_y);
    let line_z = 1.0 - smoothstep(0.0, line_width, to_line_z);

    return min(line_x + line_y + line_z, 1.0);
}

fn dir_to_spherical(dir: vec3<f32>) -> vec2<f32> {
    let r = length(dir);
    let theta = acos(clamp(dir.y / r, -1.0, 1.0));
    let phi = atan2(dir.z, dir.x) + PI;
    return vec2<f32>(theta, phi);
}

// ── Accretion disk ────────────────────────────────────────────────────

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

fn disk_detail(r: f32, azimuth: f32, rs: f32, disk_inner: f32) -> f32 {
    let rn = r / rs;
    var detail = 1.0;

    detail *= 0.95 + 0.05 * sin(rn * 6.0);
    detail *= 0.97 + 0.03 * sin(rn * 15.0 + 2.0);

    let spiral = sin(azimuth * 2.0 - rn * 4.0 + u.time * 0.2);
    detail *= 0.96 + 0.04 * spiral;

    let noise_uv = vec2<f32>(rn * 4.0, azimuth * 3.0 / PI);
    let turb = fbm(noise_uv);
    detail *= 0.88 + 0.12 * turb;

    let inner_turb = fbm(vec2<f32>(azimuth * 5.0 / PI + u.time * 0.15, rn * 10.0));
    let inner_weight = exp(-max(rn - disk_inner / rs, 0.0) * 1.5);
    detail += inner_turb * inner_weight * 0.2;

    return max(detail, 0.0);
}

fn disk_color_for_body(pos: vec3<f32>, body_pos: vec3<f32>, rs: f32, disk_inner: f32, disk_outer: f32) -> vec3<f32> {
    let delta = pos - body_pos;
    let r = length(vec2<f32>(delta.x, delta.z));
    let azimuth = atan2(delta.z, delta.x) + u.time * 0.5;

    let r_isco = 3.0 * rs;
    var luminosity: f32;
    if r > r_isco {
        luminosity = (1.0 / (r * r)) * (1.0 - sqrt(r_isco / r));
    } else {
        luminosity = 0.0;
    }
    let r_peak = r_isco * 49.0 / 36.0;
    let l_peak = (1.0 / (r_peak * r_peak)) * (1.0 - sqrt(r_isco / r_peak));
    luminosity = luminosity / max(l_peak, 0.001);

    let t_normalized = pow(clamp(disk_inner / r, 0.0, 1.0), 0.75);
    let temp = mix(1500.0, 6500.0, t_normalized);
    var col = blackbody(temp);

    let detail = disk_detail(r, azimuth, rs, disk_inner);
    col = col * luminosity * detail * 3.0;

    // Doppler shift from Keplerian orbital velocity
    let v_orb = sqrt(rs / (2.0 * r));
    let doppler = 1.0 / (1.0 + v_orb * sin(azimuth));
    let doppler3 = doppler * doppler * doppler;
    col = col * clamp(doppler3, 0.1, 4.0);

    // Gravitational redshift from all bodies
    var grav_potential = 0.0;
    for (var i = 0u; i < u.num_bodies; i = i + 1u) {
        let bp = bodies[i].position.xyz;
        let dist = length(pos - bp);
        if dist > 0.01 {
            grav_potential += bodies[i].rs / dist;
        }
    }
    let grav_redshift = sqrt(max(1.0 - grav_potential, 0.001));
    col = col * grav_redshift;

    // Soft outer edge
    let outer_fade = 1.0 - smoothstep(disk_outer - 1.0 * rs, disk_outer, r);
    col = col * outer_fade;

    return col;
}

// ── Multi-body gravitational acceleration ─────────────────────────────

fn gravitational_acceleration(pos: vec3<f32>, vel: vec3<f32>) -> vec3<f32> {
    var accel = vec3<f32>(0.0);

    for (var i = 0u; i < u.num_bodies; i = i + 1u) {
        let body_pos = bodies[i].position.xyz;
        let rs_i = bodies[i].rs;
        let delta = pos - body_pos;
        let r = length(delta);

        // Skip if too close (inside event horizon)
        if r < rs_i * 0.5 {
            continue;
        }

        let r2 = r * r;
        let r5 = r2 * r2 * r;

        // |cross(delta, vel)|^2
        let c = cross(delta, vel);
        let L2 = dot(c, c);

        // a = -1.5 * rs / r^5 * L^2 * delta
        accel -= 1.5 * rs_i / r5 * L2 * delta;
    }

    return accel;
}

fn check_capture(pos: vec3<f32>) -> i32 {
    for (var i = 0u; i < u.num_bodies; i = i + 1u) {
        let body_pos = bodies[i].position.xyz;
        let rs_i = bodies[i].rs;
        let r = length(pos - body_pos);
        if r < rs_i {
            return i32(i);
        }
    }
    return -1i;
}

fn check_escape(pos: vec3<f32>) -> bool {
    for (var i = 0u; i < u.num_bodies; i = i + 1u) {
        let body_pos = bodies[i].position.xyz;
        let r = length(pos - body_pos);
        if r < ESCAPE_RADIUS {
            return false;
        }
    }
    return true;
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

    // 3D ray integration state
    var pos = u.camera_pos.xyz;
    var vel = ray_dir; // normalized direction (null geodesic, speed = 1)

    let dt = u.step_size;
    var captured = false;
    var escaped = false;

    // Disk crossing state
    var disk_color_accum = vec3<f32>(0.0);
    var disk_hit = false;
    var prev_y = pos.y;

    // Grid volume state: composite grid lines along the curved ray path
    var grid_accum_color = vec3<f32>(0.0);
    var grid_accum_alpha = 0.0;
    let grid_line_color = vec3<f32>(0.1, 0.6, 0.8);
    let grid_step_alpha = 0.12;

    // RK4 integration in 3D
    for (var i = 0u; i < u.max_steps; i = i + 1u) {
        // Check capture
        if check_capture(pos) >= 0i {
            captured = true;
            break;
        }

        // Check escape
        if check_escape(pos) {
            escaped = true;
            break;
        }

        // Sample Cartesian grid at current position (grid lives in flat space, ray is bent)
        if u.grid_enabled == 1u {
            let strength = grid_strength_at_pos(pos);
            let line_alpha = strength * grid_step_alpha;
            grid_accum_color += (1.0 - grid_accum_alpha) * line_alpha * grid_line_color;
            grid_accum_alpha += (1.0 - grid_accum_alpha) * line_alpha;
        }

        // Store pre-step y for disk crossing detection
        let y_before = pos.y;
        let pos_before = pos;

        // RK4 step: state = (pos, vel), derivative = (vel, accel)
        let a1 = gravitational_acceleration(pos, vel);
        let k1_pos = vel;
        let k1_vel = a1;

        let p2 = pos + 0.5 * dt * k1_pos;
        let v2 = vel + 0.5 * dt * k1_vel;
        let a2 = gravitational_acceleration(p2, v2);
        let k2_pos = v2;
        let k2_vel = a2;

        let p3 = pos + 0.5 * dt * k2_pos;
        let v3 = vel + 0.5 * dt * k2_vel;
        let a3 = gravitational_acceleration(p3, v3);
        let k3_pos = v3;
        let k3_vel = a3;

        let p4 = pos + dt * k3_pos;
        let v4 = vel + dt * k3_vel;
        let a4 = gravitational_acceleration(p4, v4);
        let k4_pos = v4;
        let k4_vel = a4;

        pos = pos + (dt / 6.0) * (k1_pos + 2.0 * k2_pos + 2.0 * k3_pos + k4_pos);
        vel = vel + (dt / 6.0) * (k1_vel + 2.0 * k2_vel + 2.0 * k3_vel + k4_vel);

        // Disk crossing detection
        if u.disk_enabled == 1u && !disk_hit {
            let cur_y = pos.y;
            if y_before * cur_y < 0.0 {
                // Interpolate crossing point
                let t_cross = abs(y_before) / (abs(y_before) + abs(cur_y));
                let cross_pos = pos_before + t_cross * (pos - pos_before);

                disk_hit = true;

                // Check each body's disk
                for (var b = 0u; b < u.num_bodies; b = b + 1u) {
                    let body_pos = bodies[b].position.xyz;
                    let delta = cross_pos - body_pos;
                    let r_disk = length(vec2<f32>(delta.x, delta.z));

                    if r_disk > bodies[b].disk_inner && r_disk < bodies[b].disk_outer {
                        let col = disk_color_for_body(
                            cross_pos,
                            body_pos,
                            bodies[b].rs,
                            bodies[b].disk_inner,
                            bodies[b].disk_outer
                        );
                        // Additive blending for overlapping disks
                        disk_color_accum += col;
                    }
                }
            }
        }
    }

    // If we ran out of steps, determine outcome from velocity
    if !captured && !escaped {
        // Check if heading away from all bodies
        var heading_away = true;
        for (var i = 0u; i < u.num_bodies; i = i + 1u) {
            let delta = pos - bodies[i].position.xyz;
            if dot(vel, delta) < 0.0 {
                heading_away = false;
                break;
            }
        }
        if heading_away {
            escaped = true;
        } else {
            captured = true;
        }
    }

    // ── Coloring ──

    var color = vec3<f32>(0.0);
    let has_disk = disk_hit && (disk_color_accum.x > 0.0 || disk_color_accum.y > 0.0 || disk_color_accum.z > 0.0);

    if has_disk {
        if escaped {
            let exit_dir = normalize(vel);
            let angles = dir_to_spherical(exit_dir);
            let bg = background(angles.x, angles.y);
            let disk_lum = max(disk_color_accum.x, max(disk_color_accum.y, disk_color_accum.z));
            let opacity = clamp(disk_lum, 0.0, 1.0);
            let behind = mix(bg, disk_color_accum, opacity);
            if u.grid_enabled == 1u {
                color = grid_accum_color + (1.0 - grid_accum_alpha) * behind;
            } else {
                color = behind;
            }
        } else {
            color = disk_color_accum;
        }
    } else if captured {
        color = vec3<f32>(0.0);
    } else {
        let exit_dir = normalize(vel);
        let angles = dir_to_spherical(exit_dir);
        let bg = background(angles.x, angles.y);
        if u.grid_enabled == 1u {
            color = grid_accum_color + (1.0 - grid_accum_alpha) * bg;
        } else {
            color = bg;
        }
    }

    // ACES tonemapping
    color = aces(color);

    textureStore(output, pixel, vec4<f32>(color, 1.0));
}
