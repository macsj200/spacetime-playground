use glam::Vec3;
use winit::event::{ElementState, MouseButton, MouseScrollDelta};
use winit::keyboard::KeyCode;
use std::collections::HashSet;

pub struct OrbitalCamera {
    /// Spherical coordinates: distance from origin
    pub distance: f32,
    /// Azimuthal angle (around Y axis)
    pub azimuth: f32,
    /// Polar angle (from Y axis)
    pub elevation: f32,
    /// Point the camera orbits around
    pub target: Vec3,
    /// Field of view in radians
    pub fov: f32,

    // Input state
    is_dragging: bool,
    last_mouse_pos: Option<(f64, f64)>,
    keys_pressed: HashSet<KeyCode>,
}

impl OrbitalCamera {
    pub fn new(distance: f32, azimuth: f32, elevation: f32) -> Self {
        Self {
            distance,
            azimuth,
            elevation,
            target: Vec3::ZERO,
            fov: 1.0,
            is_dragging: false,
            last_mouse_pos: None,
            keys_pressed: HashSet::new(),
        }
    }

    pub fn position(&self) -> Vec3 {
        let x = self.distance * self.elevation.sin() * self.azimuth.cos();
        let y = self.distance * self.elevation.cos();
        let z = self.distance * self.elevation.sin() * self.azimuth.sin();
        self.target + Vec3::new(x, y, z)
    }

    pub fn forward(&self) -> Vec3 {
        (self.target - self.position()).normalize()
    }

    pub fn up(&self) -> Vec3 {
        // Compute right vector first, then derive up
        let forward = self.forward();
        let world_up = Vec3::Y;
        let right = forward.cross(world_up).normalize();
        if right.length_squared() < 1e-6 {
            // Camera is looking straight up/down, pick arbitrary up
            return Vec3::Z;
        }
        right.cross(forward).normalize()
    }

    pub fn right(&self) -> Vec3 {
        let forward = self.forward();
        let world_up = Vec3::Y;
        let right = forward.cross(world_up).normalize();
        if right.length_squared() < 1e-6 {
            return Vec3::X;
        }
        right
    }

    pub fn handle_mouse_button(&mut self, button: MouseButton, state: ElementState) {
        if button == MouseButton::Left {
            self.is_dragging = state == ElementState::Pressed;
            if !self.is_dragging {
                self.last_mouse_pos = None;
            }
        }
    }

    pub fn handle_mouse_move(&mut self, x: f64, y: f64) {
        if !self.is_dragging {
            return;
        }

        if let Some((lx, ly)) = self.last_mouse_pos {
            let dx = (x - lx) as f32;
            let dy = (y - ly) as f32;

            let sensitivity = 0.005;
            self.azimuth -= dx * sensitivity;
            self.elevation = (self.elevation - dy * sensitivity).clamp(0.1, std::f32::consts::PI - 0.1);
        }

        self.last_mouse_pos = Some((x, y));
    }

    pub fn handle_scroll(&mut self, delta: MouseScrollDelta) {
        let scroll = match delta {
            MouseScrollDelta::LineDelta(_, y) => y,
            MouseScrollDelta::PixelDelta(pos) => pos.y as f32 * 0.01,
        };
        self.distance = (self.distance - scroll * 0.5).clamp(1.5, 100.0);
    }

    pub fn handle_key(&mut self, key: KeyCode, state: ElementState) {
        match state {
            ElementState::Pressed => { self.keys_pressed.insert(key); }
            ElementState::Released => { self.keys_pressed.remove(&key); }
        }
    }

    pub fn update(&mut self, dt: f32) {
        let speed = 5.0 * dt;
        let forward = self.forward();
        let right = self.right();

        if self.keys_pressed.contains(&KeyCode::KeyW) {
            self.target += forward * speed;
        }
        if self.keys_pressed.contains(&KeyCode::KeyS) {
            self.target -= forward * speed;
        }
        if self.keys_pressed.contains(&KeyCode::KeyA) {
            self.target -= right * speed;
        }
        if self.keys_pressed.contains(&KeyCode::KeyD) {
            self.target += right * speed;
        }
    }
}
