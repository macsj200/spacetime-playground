use crate::metrics::schwarzschild::SchwarzschildParams;
use crate::renderer::camera::OrbitalCamera;

pub struct UiState {
    pub show_ui: bool,
    pub background_mode: u32, // 0 = checkerboard, 1 = star field
    pub disk_enabled: bool,
    pub disk_inner: f32,
    pub disk_outer: f32,
}

impl Default for UiState {
    fn default() -> Self {
        Self {
            show_ui: true,
            background_mode: 1,
            disk_enabled: true,
            disk_inner: 3.0,
            disk_outer: 15.0,
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
            ui.label(format!(
                "ISCO: r = {:.2}",
                params.isco_radius()
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
            ui.heading("Accretion Disk");
            ui.checkbox(&mut ui_state.disk_enabled, "Enable accretion disk");
            if ui_state.disk_enabled {
                // Snap inner radius to ISCO by default
                ui.add(
                    egui::Slider::new(&mut ui_state.disk_inner, 1.5..=10.0)
                        .text("Inner radius"),
                );
                ui.add(
                    egui::Slider::new(&mut ui_state.disk_outer, 5.0..=30.0)
                        .text("Outer radius"),
                );
            }

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
            ui.horizontal(|ui| {
                ui.label("Background:");
                ui.selectable_value(&mut ui_state.background_mode, 0, "Checkerboard");
                ui.selectable_value(&mut ui_state.background_mode, 1, "Star field");
            });
        });
}
