use crate::metrics::schwarzschild::SchwarzschildParams;
use crate::renderer::camera::OrbitalCamera;

pub struct UiState {
    pub show_ui: bool,
    pub use_checkerboard: bool,
}

impl Default for UiState {
    fn default() -> Self {
        Self {
            show_ui: true,
            use_checkerboard: true,
        }
    }
}

pub fn draw_ui(
    ctx: &egui::Context,
    ui_state: &mut UiState,
    params: &mut SchwarzschildParams,
    camera: &mut OrbitalCamera,
    max_steps: &mut u32,
    step_size: &mut f32,
) {
    if !ui_state.show_ui {
        return;
    }

    egui::Window::new("Black Hole Parameters")
        .default_pos([10.0, 10.0])
        .show(ctx, |ui| {
            ui.heading("Metric");
            ui.add(
                egui::Slider::new(&mut params.rs, 0.1..=5.0)
                    .text("Schwarzschild radius (rs)"),
            );
            ui.label(format!(
                "Photon sphere: r = {:.2}",
                params.photon_sphere_radius()
            ));
            ui.label(format!(
                "Critical impact param: b = {:.2}",
                params.critical_impact_parameter()
            ));

            ui.separator();
            ui.heading("Camera");
            ui.add(
                egui::Slider::new(&mut camera.distance, 1.5..=50.0)
                    .text("Distance")
                    .logarithmic(true),
            );
            ui.add(
                egui::Slider::new(&mut camera.fov, 0.2..=2.5)
                    .text("FOV (radians)"),
            );

            ui.separator();
            ui.heading("Integration");
            ui.add(
                egui::Slider::new(max_steps, 50..=1000)
                    .text("Max RK4 steps"),
            );
            ui.add(
                egui::Slider::new(step_size, 0.001..=0.1)
                    .text("Step size (dφ)")
                    .logarithmic(true),
            );

            ui.separator();
            ui.heading("Rendering");
            ui.checkbox(&mut ui_state.use_checkerboard, "Checkerboard background");
        });
}
