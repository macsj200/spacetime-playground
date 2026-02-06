/// Parameters for the Schwarzschild metric.
///
/// ds² = -(1 - rs/r)dt² + (1 - rs/r)⁻¹dr² + r²(dθ² + sin²θ dφ²)
pub struct SchwarzschildParams {
    /// Schwarzschild radius rs = 2GM/c² (natural units: rs = 1)
    pub rs: f32,
}

impl Default for SchwarzschildParams {
    fn default() -> Self {
        Self { rs: 1.0 }
    }
}

impl SchwarzschildParams {
    /// Critical impact parameter for the photon sphere: b_crit = 3√3/2 * rs
    pub fn critical_impact_parameter(&self) -> f32 {
        3.0 * 3.0_f32.sqrt() / 2.0 * self.rs
    }

    /// Photon sphere radius: r = 3/2 * rs
    pub fn photon_sphere_radius(&self) -> f32 {
        1.5 * self.rs
    }
}
