use std::io::Error;

pub fn get_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

pub fn get_cpu_temp() -> Result<f32, Error> {
    // Read the temp file (milli-celsius)
    let temp_str = std::fs::read_to_string("/sys/class/thermal/thermal_zone0/temp")?;
    let temp_milli: f32 = temp_str.trim().parse().unwrap_or(0.0);
    Ok(temp_milli / 1000.0) // Convert to Celsius
}

#[macro_export]
macro_rules! log {
    ($($arg:tt)*) => {
        println!("[{}] {}", chrono::Local::now().format("%H:%M:%S"), format!($($arg)*))
    };
}

#[macro_export]
macro_rules! elog {
    ($($arg:tt)*) => {
        eprintln!("[{}] {}", chrono::Local::now().format("%H:%M:%S"), format!($($arg)*))
    };
}

// Backward-compatible re-exports for other submodules
pub use crate::transport::protocol::messages::{HostMessage, Status};
