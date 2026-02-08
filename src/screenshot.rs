use std::path::PathBuf;

use crate::renderer::camera::OrbitalCamera;
use crate::renderer::pipeline::RayMarchPipeline;
use crate::renderer::uniforms::Uniforms;
use crate::simulation::{Preset, Simulation};

pub struct ScreenshotConfig {
    pub preset: Preset,
    pub width: u32,
    pub height: u32,
    pub camera_distance: f32,
    pub camera_azimuth: f32,
    pub camera_elevation: f32,
    pub camera_fov: f32,
    pub max_steps: u32,
    pub step_size: f32,
    pub background_mode: u32,
    pub output: PathBuf,
    pub sim_time: f32,
}

impl Default for ScreenshotConfig {
    fn default() -> Self {
        Self {
            preset: Preset::Single,
            width: 1920,
            height: 1080,
            camera_distance: 10.0,
            camera_azimuth: 0.5,
            camera_elevation: 1.2,
            camera_fov: 1.0,
            max_steps: 600,
            step_size: 0.1,
            background_mode: 1,
            output: PathBuf::from("screenshot.png"),
            sim_time: 0.0,
        }
    }
}

pub fn parse_args() -> Option<ScreenshotConfig> {
    let args: Vec<String> = std::env::args().collect();
    if !args.iter().any(|a| a == "--screenshot") {
        return None;
    }

    let mut config = ScreenshotConfig::default();

    let get_val = |flag: &str| -> Option<String> {
        args.iter()
            .position(|a| a == flag)
            .and_then(|i| args.get(i + 1).cloned())
    };

    if let Some(p) = get_val("--preset") {
        config.preset = match p.as_str() {
            "single" => Preset::Single,
            "binary" => Preset::Binary,
            "triple" => Preset::Triple,
            _ => {
                eprintln!("Unknown preset '{}'. Options: single, binary, triple", p);
                std::process::exit(1);
            }
        };
    }

    if let Some(v) = get_val("--width") {
        config.width = v.parse().expect("Invalid --width");
    }
    if let Some(v) = get_val("--height") {
        config.height = v.parse().expect("Invalid --height");
    }
    if let Some(v) = get_val("--camera-distance") {
        config.camera_distance = v.parse().expect("Invalid --camera-distance");
    }
    if let Some(v) = get_val("--camera-azimuth") {
        config.camera_azimuth = v.parse().expect("Invalid --camera-azimuth");
    }
    if let Some(v) = get_val("--camera-elevation") {
        config.camera_elevation = v.parse().expect("Invalid --camera-elevation");
    }
    if let Some(v) = get_val("--camera-fov") {
        config.camera_fov = v.parse().expect("Invalid --camera-fov");
    }
    if let Some(v) = get_val("--max-steps") {
        config.max_steps = v.parse().expect("Invalid --max-steps");
    }
    if let Some(v) = get_val("--step-size") {
        config.step_size = v.parse().expect("Invalid --step-size");
    }
    if let Some(v) = get_val("--background") {
        config.background_mode = match v.as_str() {
            "checker" => 0,
            "stars" => 1,
            _ => v.parse().expect("Invalid --background"),
        };
    }
    if let Some(v) = get_val("--output") {
        config.output = PathBuf::from(v);
    }
    if let Some(v) = get_val("--sim-time") {
        config.sim_time = v.parse().expect("Invalid --sim-time");
    }

    Some(config)
}

pub fn render_screenshot(config: &ScreenshotConfig) {
    let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
        backends: wgpu::Backends::all(),
        ..Default::default()
    });

    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: None,
        force_fallback_adapter: false,
    }))
    .expect("Failed to find a suitable GPU adapter");

    log::info!("Using adapter: {:?}", adapter.get_info());

    let (device, queue) = pollster::block_on(adapter.request_device(
        &wgpu::DeviceDescriptor {
            label: Some("Screenshot Device"),
            required_features: wgpu::Features::empty(),
            required_limits: wgpu::Limits::default(),
            memory_hints: Default::default(),
        },
        None,
    ))
    .expect("Failed to create device");

    // Use a non-sRGB format for headless since there's no surface
    let surface_format = wgpu::TextureFormat::Bgra8Unorm;

    let pipeline = RayMarchPipeline::new(&device, surface_format, config.width, config.height);

    // Set up camera
    let camera = OrbitalCamera::new(config.camera_distance, config.camera_azimuth, config.camera_elevation);

    // Set up simulation and advance to desired time
    let mut simulation = Simulation::new(config.preset);
    if config.sim_time > 0.0 {
        simulation.paused = false;
        let steps = (config.sim_time / 0.016).ceil() as u32;
        let dt = config.sim_time / steps as f32;
        for _ in 0..steps {
            simulation.step(dt);
        }
    }

    let gpu_bodies = simulation.gpu_bodies();
    pipeline.update_bodies(&queue, &gpu_bodies);

    let uniforms = Uniforms {
        camera_pos: [
            camera.position().x,
            camera.position().y,
            camera.position().z,
            0.0,
        ],
        camera_forward: [
            camera.forward().x,
            camera.forward().y,
            camera.forward().z,
            0.0,
        ],
        camera_up: [
            camera.up().x,
            camera.up().y,
            camera.up().z,
            0.0,
        ],
        camera_right: [
            camera.right().x,
            camera.right().y,
            camera.right().z,
            0.0,
        ],
        resolution: [config.width as f32, config.height as f32],
        fov: config.camera_fov,
        num_bodies: simulation.bodies.len() as u32,
        max_steps: config.max_steps,
        step_size: config.step_size,
        disk_enabled: 1,
        background_mode: config.background_mode,
        time: config.sim_time,
        _padding: [0.0; 3],
    };
    pipeline.update_uniforms(&queue, &uniforms);

    // Dispatch compute
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("Screenshot Compute Encoder"),
    });
    pipeline.dispatch_compute(&mut encoder);
    queue.submit(std::iter::once(encoder.finish()));

    // Capture and save
    match pipeline.capture_screenshot_to(&device, &queue, &config.output) {
        Some(path) => {
            println!("Screenshot saved to {}", path.display());
        }
        None => {
            eprintln!("Failed to capture screenshot");
            std::process::exit(1);
        }
    }
}
