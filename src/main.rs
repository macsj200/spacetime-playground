mod app;
mod metrics;
mod renderer;
mod screenshot;
mod simulation;
mod ui;

use std::sync::Arc;

use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{WindowAttributes, WindowId};

struct SpacetimeApp {
    app: Option<app::App>,
}

impl ApplicationHandler for SpacetimeApp {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.app.is_none() {
            let attrs = WindowAttributes::default()
                .with_title("Spacetime Playground — Schwarzschild Black Hole")
                .with_inner_size(winit::dpi::LogicalSize::new(1280, 720));

            let window = Arc::new(event_loop.create_window(attrs).unwrap());
            self.app = Some(app::App::new(window.clone()));
            window.request_redraw();
        }
    }

    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        _window_id: WindowId,
        event: WindowEvent,
    ) {
        // Handle CloseRequested before borrowing self.app, so we can drop it
        // while the window is still alive (avoids Vulkan surface semaphore panic).
        if matches!(&event, WindowEvent::CloseRequested) {
            self.app = None;
            event_loop.exit();
            return;
        }

        let Some(app) = &mut self.app else { return };

        match &event {
            WindowEvent::RedrawRequested => {
                app.render();
                return;
            }
            _ => {}
        }

        app.handle_window_event(&event);
    }
}

fn main() {
    env_logger::init();

    if let Some(config) = screenshot::parse_args() {
        screenshot::render_screenshot(&config);
        return;
    }

    let event_loop = EventLoop::new().unwrap();
    event_loop.set_control_flow(winit::event_loop::ControlFlow::Poll);

    let mut app = SpacetimeApp { app: None };
    event_loop.run_app(&mut app).unwrap();
}
