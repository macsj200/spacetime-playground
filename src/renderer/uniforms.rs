use bytemuck::{Pod, Zeroable};

#[repr(C)]
#[derive(Debug, Copy, Clone, Pod, Zeroable)]
pub struct Uniforms {
    pub camera_pos: [f32; 4],
    pub camera_forward: [f32; 4],
    pub camera_up: [f32; 4],
    pub camera_right: [f32; 4],
    pub resolution: [f32; 2],
    pub fov: f32,
    pub num_bodies: u32,
    pub max_steps: u32,
    pub step_size: f32,
    pub disk_enabled: u32,
    pub background_mode: u32,
    pub time: f32,
    pub grid_enabled: u32,
    pub _padding: [f32; 2],
}

impl Default for Uniforms {
    fn default() -> Self {
        Self {
            camera_pos: [0.0, 0.0, 10.0, 0.0],
            camera_forward: [0.0, 0.0, -1.0, 0.0],
            camera_up: [0.0, 1.0, 0.0, 0.0],
            camera_right: [1.0, 0.0, 0.0, 0.0],
            resolution: [800.0, 600.0],
            fov: 1.0,
            num_bodies: 1,
            max_steps: 600,
            step_size: 0.1,
            disk_enabled: 1,
            background_mode: 0,
            time: 0.0,
            grid_enabled: 0,
            _padding: [0.0; 2],
        }
    }
}
