use bytemuck::{Pod, Zeroable};
use glam::Vec3;

pub const MAX_BODIES: usize = 8;

#[derive(Clone)]
pub struct Body {
    pub position: Vec3,
    pub velocity: Vec3,
    pub rs: f32,
    pub disk_inner_mult: f32,
    pub disk_outer_mult: f32,
}

impl Body {
    pub fn new(position: Vec3, velocity: Vec3, rs: f32) -> Self {
        Self {
            position,
            velocity,
            rs,
            disk_inner_mult: 3.0,
            disk_outer_mult: 15.0,
        }
    }
}

#[repr(C)]
#[derive(Debug, Copy, Clone, Default, Pod, Zeroable)]
pub struct GpuBody {
    pub position: [f32; 4],
    pub rs: f32,
    pub disk_inner: f32,
    pub disk_outer: f32,
    pub _padding: f32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Preset {
    Single,
    Binary,
    Triple,
}

impl Preset {
    pub const ALL: [Preset; 3] = [Preset::Single, Preset::Binary, Preset::Triple];

    pub fn name(self) -> &'static str {
        match self {
            Preset::Single => "Single",
            Preset::Binary => "Binary",
            Preset::Triple => "Triple",
        }
    }
}

pub struct Simulation {
    pub bodies: Vec<Body>,
    pub time: f64,
    pub paused: bool,
    pub speed: f32,
    pub preset: Preset,
}

impl Simulation {
    pub fn new(preset: Preset) -> Self {
        let mut sim = Self {
            bodies: Vec::new(),
            time: 0.0,
            paused: true,
            speed: 1.0,
            preset,
        };
        sim.load_preset(preset);
        sim
    }

    pub fn load_preset(&mut self, preset: Preset) {
        self.preset = preset;
        self.time = 0.0;

        match preset {
            Preset::Single => {
                self.bodies = vec![Body::new(Vec3::ZERO, Vec3::ZERO, 1.0)];
                self.paused = true;
            }
            Preset::Binary => {
                let separation = 6.0;
                let rs = 0.5;
                // Circular orbit velocity: v = sqrt(rs_other / (4 * d))
                // where d is the separation between the two bodies
                let v = (rs / (4.0_f32 * separation)).sqrt();
                self.bodies = vec![
                    Body::new(
                        Vec3::new(separation / 2.0, 0.0, 0.0),
                        Vec3::new(0.0, 0.0, v),
                        rs,
                    ),
                    Body::new(
                        Vec3::new(-separation / 2.0, 0.0, 0.0),
                        Vec3::new(0.0, 0.0, -v),
                        rs,
                    ),
                ];
                self.paused = false;
            }
            Preset::Triple => {
                let rs = 0.4;
                let radius = 5.0;
                // Equilateral triangle in the XZ plane
                let mut bodies = Vec::new();
                for i in 0..3 {
                    let angle = (i as f32) * std::f32::consts::TAU / 3.0;
                    let pos = Vec3::new(radius * angle.cos(), 0.0, radius * angle.sin());
                    // Circular orbit: velocity tangent to the circle
                    // For 3 equal-mass bodies in equilateral triangle:
                    // v = sqrt(rs_total_other / (4 * side_length)) where side_length = radius * sqrt(3)
                    let side = radius * 3.0_f32.sqrt();
                    let v_mag = (2.0 * rs / (4.0 * side)).sqrt();
                    let tangent = Vec3::new(-angle.sin(), 0.0, angle.cos());
                    let vel = v_mag * tangent;
                    bodies.push(Body::new(pos, vel, rs));
                }
                self.bodies = bodies;
                self.paused = false;
            }
        }
    }

    /// Leapfrog (kick-drift-kick) N-body integration
    pub fn step(&mut self, dt: f32) {
        if self.paused || self.bodies.len() <= 1 {
            return;
        }

        let dt = dt * self.speed;
        let n = self.bodies.len();

        // Half-kick: update velocities by dt/2
        let mut accels = vec![Vec3::ZERO; n];
        for i in 0..n {
            for j in 0..n {
                if i == j {
                    continue;
                }
                let delta = self.bodies[j].position - self.bodies[i].position;
                let r = delta.length();
                if r < 0.1 {
                    continue;
                }
                // a = rs_other / (2 * r^2) * r_hat
                // With G=c=1: M = rs/2, so a = M/r^2 = rs/(2*r^2)
                let a_mag = self.bodies[j].rs / (2.0 * r * r);
                accels[i] += a_mag * delta / r;
            }
        }

        for i in 0..n {
            self.bodies[i].velocity += accels[i] * dt * 0.5;
        }

        // Drift: update positions by dt
        for i in 0..n {
            let vel = self.bodies[i].velocity;
            self.bodies[i].position += vel * dt;
        }

        // Half-kick: recompute accelerations and update velocities by dt/2
        let mut accels = vec![Vec3::ZERO; n];
        for i in 0..n {
            for j in 0..n {
                if i == j {
                    continue;
                }
                let delta = self.bodies[j].position - self.bodies[i].position;
                let r = delta.length();
                if r < 0.1 {
                    continue;
                }
                let a_mag = self.bodies[j].rs / (2.0 * r * r);
                accels[i] += a_mag * delta / r;
            }
        }

        for i in 0..n {
            self.bodies[i].velocity += accels[i] * dt * 0.5;
        }

        self.time += dt as f64;
    }

    pub fn gpu_bodies(&self) -> [GpuBody; MAX_BODIES] {
        let mut result = [GpuBody::zeroed(); MAX_BODIES];
        for (i, body) in self.bodies.iter().enumerate() {
            if i >= MAX_BODIES {
                break;
            }
            result[i] = GpuBody {
                position: [body.position.x, body.position.y, body.position.z, 0.0],
                rs: body.rs,
                disk_inner: body.disk_inner_mult * body.rs,
                disk_outer: body.disk_outer_mult * body.rs,
                _padding: 0.0,
            };
        }
        result
    }
}
