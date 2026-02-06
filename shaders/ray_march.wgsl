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
    _padding: vec2<f32>,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var output: texture_storage_2d<rgba8unorm, write>;

const PI: f32 = 3.14159265358979;
const SKY_RADIUS: f32 = 30.0;

// Checkerboard pattern on the celestial sphere
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

// Convert Cartesian direction to spherical angles (theta, phi)
fn dir_to_spherical(dir: vec3<f32>) -> vec2<f32> {
    let r = length(dir);
    let theta = acos(clamp(dir.y / r, -1.0, 1.0));
    let phi = atan2(dir.z, dir.x) + PI; // [0, 2*PI]
    return vec2<f32>(theta, phi);
}

// RK4 integration of the Schwarzschild orbit equation
// d²u/dφ² = -u + (3/2) * rs * u²
// Split into: du/dφ = w,  dw/dφ = -u + 1.5 * rs * u²
fn orbit_rhs_w(u_val: f32, rs: f32) -> f32 {
    return -u_val + 1.5 * rs * u_val * u_val;
}

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

    // Compute the impact parameter b for this ray
    // b = |r × d| where r is camera position, d is ray direction
    let cross_rd = cross(cam_pos, ray_dir);
    let b = length(cross_rd);

    // Check if impact parameter is below critical value — ray will be captured
    // Also handle the case where camera is very close
    let rs = u.rs;

    // For the geodesic integration, we work in the orbital plane.
    // The ray starts at radius cam_r, and we need initial conditions for u = 1/r.
    //
    // Initial conditions:
    //   u0 = 1/cam_r
    //   The initial du/dφ (= w0) comes from the radial component of the ray.
    //
    // We project the ray direction onto radial and tangential components.
    let r_hat = cam_pos / cam_r;
    let cos_angle = dot(ray_dir, r_hat);
    let sin_angle = sqrt(max(1.0 - cos_angle * cos_angle, 0.0));

    // Impact parameter: b = r * sin(angle between ray and radial)
    // b = cam_r * sin_angle (this should match our cross product computation)

    // Initial u and w = du/dφ
    // u = 1/r, so du/dr = -1/r²
    // du/dφ = (du/dr)(dr/dφ)
    // For a ray: dr/dφ = -r² * cos_angle / (r * sin_angle) = -r * cos_angle / sin_angle
    // So: w0 = du/dφ = (-1/r²)(-r * cos_angle / sin_angle) = cos_angle / (r * sin_angle)
    var u_val = 1.0 / cam_r;
    var w_val = 0.0;
    if sin_angle > 1e-6 {
        w_val = cos_angle / (cam_r * sin_angle);
    }

    // Determine if the ray goes inward or outward initially
    // (sign of w_val handles this via cos_angle sign)

    let dphi = u.step_size;
    var phi_total = 0.0;
    var captured = false;
    var escaped = false;
    var final_u = u_val;

    // RK4 integration
    for (var i = 0u; i < u.max_steps; i = i + 1u) {
        // Check termination conditions
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
    }

    if !captured && !escaped {
        // Max steps reached — treat as escaped if heading outward
        if w_val < 0.0 {
            escaped = true;
            final_u = u_val;
        } else {
            captured = true;
        }
    }

    var color = vec3<f32>(0.0, 0.0, 0.0);

    if captured {
        // Black hole - dark with subtle reddish glow at edge
        color = vec3<f32>(0.02, 0.0, 0.0);
    } else {
        // Ray escaped — map exit angle to background
        // The total deflection angle is phi_total.
        // We need to map this back to a 3D direction.

        // Build the orbital plane basis:
        // e1 = r_hat (radial direction from BH to camera)
        // e2 = perpendicular component of ray_dir in the orbital plane
        var tangent = ray_dir - cos_angle * r_hat;
        let tang_len = length(tangent);
        if tang_len > 1e-6 {
            tangent = tangent / tang_len;
        } else {
            tangent = vec3<f32>(1.0, 0.0, 0.0);
        }

        // The initial ray direction in the orbital plane makes angle
        // (PI - arctan2(sin_angle, cos_angle)) with the radial toward BH.
        // After integrating phi_total, the exit direction in the orbital plane is:
        let exit_phi = atan2(sin_angle, -cos_angle) + phi_total;

        // Exit direction in 3D (in the orbital plane)
        let exit_dir = cos(exit_phi) * (-r_hat) + sin(exit_phi) * tangent;

        let angles = dir_to_spherical(exit_dir);
        color = checkerboard(angles.x, angles.y);
    }

    textureStore(output, pixel, vec4<f32>(color, 1.0));
}
