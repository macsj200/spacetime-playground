mod app;
mod metrics;
mod renderer;
mod screenshot;
mod simulation;
mod ui;

use std::sync::Arc;
use std::time::{Duration, Instant};

use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::window::{WindowAttributes, WindowId};

/// Only request a redraw when this much time has passed (~60 FPS).
const FRAME_INTERVAL: Duration = Duration::from_millis(16);

struct SpacetimeApp {
    app: Option<app::App>,
    /// When we last requested a redraw (throttles to ~60 FPS, keeps input responsive).
    last_redraw_request: Instant,
}

impl ApplicationHandler for SpacetimeApp {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.app.is_none() {
            let attrs = WindowAttributes::default()
                .with_title("Spacetime Playground — Schwarzschild Black Hole")
                .with_inner_size(winit::dpi::LogicalSize::new(1280, 720));

            let window = Arc::new(event_loop.create_window(attrs).unwrap());
            self.app = Some(app::App::new(window));
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

    /// Request a redraw only when 1/60s has passed (throttle). We use Poll so the loop never
    /// blocks and input is processed every iteration; without throttling we'd render at max rate.
    fn about_to_wait(&mut self, _event_loop: &ActiveEventLoop) {
        if let Some(app) = &self.app {
            if Instant::now().duration_since(self.last_redraw_request) >= FRAME_INTERVAL {
                self.last_redraw_request = Instant::now();
                app.request_redraw();
            }
        }
    }
}

fn main() {
    env_logger::init();

    if let Some(config) = screenshot::parse_args() {
        screenshot::render_screenshot(&config);
        return;
    }

    let event_loop = EventLoop::new().unwrap();
    event_loop.set_control_flow(ControlFlow::Poll);

    let mut app = SpacetimeApp {
        app: None,
        last_redraw_request: Instant::now(),
    };
    event_loop.run_app(&mut app).unwrap();
}
