use std::sync::Arc;

use winit::event::{ElementState, WindowEvent};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::Window;

use crate::metrics::schwarzschild::SchwarzschildParams;
use crate::renderer::camera::OrbitalCamera;
use crate::renderer::pipeline::RayMarchPipeline;
use crate::renderer::uniforms::Uniforms;
use crate::ui::{self, UiState};

pub struct App {
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    pipeline: RayMarchPipeline,
    camera: OrbitalCamera,
    params: SchwarzschildParams,
    ui_state: UiState,
    max_steps: u32,
    step_size: f32,
    egui_ctx: egui::Context,
    egui_winit: egui_winit::State,
    egui_renderer: egui_wgpu::Renderer,
    window: Arc<Window>,
    last_frame_time: std::time::Instant,
    start_time: std::time::Instant,
}

impl App {
    pub fn new(window: Arc<Window>) -> Self {
        let size = window.inner_size();
        let width = size.width.max(1);
        let height = size.height.max(1);

        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        });

        let surface = instance.create_surface(window.clone()).unwrap();

        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: Some(&surface),
            force_fallback_adapter: false,
        }))
        .expect("Failed to find a suitable GPU adapter");

        log::info!("Using adapter: {:?}", adapter.get_info());

        let (device, queue) = pollster::block_on(adapter.request_device(
            &wgpu::DeviceDescriptor {
                label: Some("GPU Device"),
                required_features: wgpu::Features::empty(),
                required_limits: wgpu::Limits::default(),
                memory_hints: Default::default(),
            },
            None,
        ))
        .expect("Failed to create device");

        let surface_caps = surface.get_capabilities(&adapter);
        let surface_format = surface_caps
            .formats
            .iter()
            .find(|f| f.is_srgb())
            .copied()
            .unwrap_or(surface_caps.formats[0]);

        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format: surface_format,
            width,
            height,
            present_mode: wgpu::PresentMode::AutoVsync,
            alpha_mode: surface_caps.alpha_modes[0],
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&device, &config);

        let pipeline = RayMarchPipeline::new(&device, surface_format, width, height);
        let camera = OrbitalCamera::new(10.0, 0.5, std::f32::consts::FRAC_PI_2);

        let egui_ctx = egui::Context::default();
        let egui_winit = egui_winit::State::new(
            egui_ctx.clone(),
            egui::ViewportId::ROOT,
            &window,
            Some(window.scale_factor() as f32),
            None,
            None,
        );
        let egui_renderer = egui_wgpu::Renderer::new(&device, surface_format, None, 1, false);

        Self {
            surface,
            device,
            queue,
            config,
            pipeline,
            camera,
            params: SchwarzschildParams::default(),
            ui_state: UiState::default(),
            max_steps: 300,
            step_size: 0.01,
            egui_ctx,
            egui_winit,
            egui_renderer,
            window,
            last_frame_time: std::time::Instant::now(),
            start_time: std::time::Instant::now(),
        }
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        if width == 0 || height == 0 {
            return;
        }
        self.config.width = width;
        self.config.height = height;
        self.surface.configure(&self.device, &self.config);
        self.pipeline
            .resize(&self.device, self.config.format, width, height);
    }

    pub fn handle_window_event(&mut self, event: &WindowEvent) -> bool {
        // Let egui handle events first
        let egui_response = self.egui_winit.on_window_event(&self.window, event);
        if egui_response.consumed {
            return true;
        }

        match event {
            WindowEvent::Resized(size) => {
                self.resize(size.width, size.height);
                true
            }
            WindowEvent::MouseInput { button, state, .. } => {
                self.camera.handle_mouse_button(*button, *state);
                true
            }
            WindowEvent::CursorMoved { position, .. } => {
                self.camera.handle_mouse_move(position.x, position.y);
                true
            }
            WindowEvent::MouseWheel { delta, .. } => {
                self.camera.handle_scroll(*delta);
                true
            }
            WindowEvent::KeyboardInput { event, .. } => {
                if let PhysicalKey::Code(key) = event.physical_key {
                    // Toggle UI with Tab
                    if key == KeyCode::Tab && event.state == ElementState::Pressed {
                        self.ui_state.show_ui = !self.ui_state.show_ui;
                    }
                    self.camera.handle_key(key, event.state);
                }
                true
            }
            _ => false,
        }
    }

    pub fn render(&mut self) {
        let now = std::time::Instant::now();
        let dt = (now - self.last_frame_time).as_secs_f32();
        self.last_frame_time = now;

        self.camera.update(dt);

        // Update uniforms
        let uniforms = Uniforms {
            camera_pos: [
                self.camera.position().x,
                self.camera.position().y,
                self.camera.position().z,
                0.0,
            ],
            camera_forward: [
                self.camera.forward().x,
                self.camera.forward().y,
                self.camera.forward().z,
                0.0,
            ],
            camera_up: [
                self.camera.up().x,
                self.camera.up().y,
                self.camera.up().z,
                0.0,
            ],
            camera_right: [
                self.camera.right().x,
                self.camera.right().y,
                self.camera.right().z,
                0.0,
            ],
            resolution: [self.config.width as f32, self.config.height as f32],
            fov: self.camera.fov,
            rs: self.params.rs,
            max_steps: self.max_steps,
            step_size: self.step_size,
            disk_enabled: if self.ui_state.disk_enabled { 1 } else { 0 },
            disk_inner: self.ui_state.disk_inner,
            disk_outer: self.ui_state.disk_outer,
            background_mode: self.ui_state.background_mode,
            time: self.start_time.elapsed().as_secs_f32(),
            _padding: 0.0,
        };
        self.pipeline.update_uniforms(&self.queue, &uniforms);

        // Get surface texture
        let output = match self.surface.get_current_texture() {
            Ok(t) => t,
            Err(wgpu::SurfaceError::Lost | wgpu::SurfaceError::Outdated) => {
                self.resize(self.config.width, self.config.height);
                return;
            }
            Err(e) => {
                log::error!("Surface error: {:?}", e);
                return;
            }
        };
        let view = output
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());

        // Build egui UI
        let raw_input = self.egui_winit.take_egui_input(&self.window);
        let full_output = self.egui_ctx.run(raw_input, |ctx| {
            ui::draw_ui(
                ctx,
                &mut self.ui_state,
                &mut self.params,
                &mut self.camera,
                &mut self.max_steps,
                &mut self.step_size,
            );
        });

        self.egui_winit
            .handle_platform_output(&self.window, full_output.platform_output);

        let paint_jobs = self
            .egui_ctx
            .tessellate(full_output.shapes, full_output.pixels_per_point);

        let screen_descriptor = egui_wgpu::ScreenDescriptor {
            size_in_pixels: [self.config.width, self.config.height],
            pixels_per_point: self.window.scale_factor() as f32,
        };

        // Update egui textures
        for (id, delta) in &full_output.textures_delta.set {
            self.egui_renderer
                .update_texture(&self.device, &self.queue, *id, delta);
        }
        self.egui_renderer.update_buffers(
            &self.device,
            &self.queue,
            &mut self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("egui encoder"),
            }),
            &paint_jobs,
            &screen_descriptor,
        );

        // Encode compute + blit commands
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Main Encoder"),
            });

        // Dispatch compute shader
        self.pipeline.dispatch_compute(&mut encoder);

        // Render fullscreen blit
        self.pipeline.render_fullscreen(&mut encoder, &view);

        // Submit compute + blit
        self.queue.submit(std::iter::once(encoder.finish()));

        // Render egui on top
        let mut egui_encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("egui Encoder"),
            });
        let mut pass = egui_encoder
            .begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("egui Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Load,
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                ..Default::default()
            })
            .forget_lifetime();
        self.egui_renderer
            .render(&mut pass, &paint_jobs, &screen_descriptor);
        drop(pass);

        self.queue.submit(std::iter::once(egui_encoder.finish()));
        output.present();

        // Free egui textures
        for id in &full_output.textures_delta.free {
            self.egui_renderer.free_texture(id);
        }

        // Request redraw for continuous rendering
        self.window.request_redraw();
    }
}
