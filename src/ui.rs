use crate::renderer::camera::OrbitalCamera;
use crate::simulation::{Preset, Simulation};

pub struct UiState {
    pub show_ui: bool,
    pub background_mode: u32,
    pub disk_enabled: bool,
    pub selected_body: usize,
}

impl Default for UiState {
    fn default() -> Self {
        Self {
            show_ui: true,
            background_mode: 1,
            disk_enabled: true,
            selected_body: 0,
        }
    }
}

pub fn draw_ui(
    ctx: &egui::Context,
    ui_state: &mut UiState,
    simulation: &mut Simulation,
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
            // Preset selector
            ui.heading("Preset");
            ui.horizontal(|ui| {
                for preset in Preset::ALL {
                    if ui
                        .selectable_label(simulation.preset == preset, preset.name())
                        .clicked()
                    {
                        simulation.load_preset(preset);
                        ui_state.selected_body = 0;
                    }
                }
            });

            ui.separator();

            // Time controls
            ui.heading("Simulation");
            ui.horizontal(|ui| {
                ui.checkbox(&mut simulation.paused, "Paused");
                ui.add(
                    egui::Slider::new(&mut simulation.speed, 0.1..=5.0)
                        .text("Speed")
                        .logarithmic(true),
                );
            });
            ui.label(format!("Time: {:.1}s", simulation.time));

            ui.separator();

            // Bodies list
            ui.heading("Bodies");
            let num_bodies = simulation.bodies.len();
            for i in 0..num_bodies {
                let label = format!(
                    "Body {} (rs={:.2})",
                    i, simulation.bodies[i].rs
                );
                if ui
                    .selectable_label(ui_state.selected_body == i, label)
                    .clicked()
                {
                    ui_state.selected_body = i;
                }
            }

            // Clamp selected body to valid range
            if ui_state.selected_body >= num_bodies {
                ui_state.selected_body = 0;
            }

            ui.separator();

            // Selected body details
            if num_bodies > 0 {
                let idx = ui_state.selected_body;
                ui.heading(format!("Body {}", idx));

                ui.add(
                    egui::Slider::new(&mut simulation.bodies[idx].rs, 0.1..=5.0)
                        .text("Schwarzschild radius (rs)"),
                );

                let rs = simulation.bodies[idx].rs;
                ui.label(format!("Photon sphere: r = {:.2}", 1.5 * rs));
                ui.label(format!(
                    "Critical impact param: b = {:.2}",
                    3.0 * 3.0_f32.sqrt() / 2.0 * rs
                ));
                ui.label(format!("ISCO: r = {:.2}", 3.0 * rs));

                ui.label(format!(
                    "Position: ({:.2}, {:.2}, {:.2})",
                    simulation.bodies[idx].position.x,
                    simulation.bodies[idx].position.y,
                    simulation.bodies[idx].position.z,
                ));

                ui.separator();
                ui.heading("Accretion Disk");
                ui.checkbox(&mut ui_state.disk_enabled, "Enable accretion disk");
                if ui_state.disk_enabled {
                    ui.add(
                        egui::Slider::new(
                            &mut simulation.bodies[idx].disk_inner_mult,
                            1.5..=10.0,
                        )
                        .text("Inner radius (×rs)"),
                    );
                    ui.add(
                        egui::Slider::new(
                            &mut simulation.bodies[idx].disk_outer_mult,
                            5.0..=30.0,
                        )
                        .text("Outer radius (×rs)"),
                    );
                }
            }

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
                egui::Slider::new(max_steps, 50..=2000)
                    .text("Max RK4 steps"),
            );
            ui.add(
                egui::Slider::new(step_size, 0.01..=1.0)
                    .text("Step size (dt)")
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
