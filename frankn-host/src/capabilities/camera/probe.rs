use serde::{Deserialize, Serialize};
use std::path::Path;
use tokio::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CameraDeviceInfo {
    pub device_path: String,
    pub name: String,
    pub formats: Vec<String>,
    pub resolutions: Vec<String>,
    pub is_functional: bool,
    pub is_dummy: bool,
}

/// Probes all `/dev/video*` devices present on the system.
pub async fn probe_cameras() -> Vec<CameraDeviceInfo> {
    let mut devices = Vec::new();
    let mut entries = Vec::new();

    // Collect /dev/video* paths
    if let Ok(read_dir) = std::fs::read_dir("/dev") {
        for entry in read_dir.flatten() {
            let filename = entry.file_name();
            let name_str = filename.to_string_lossy();
            if name_str.starts_with("video") {
                entries.push(entry.path().to_string_lossy().to_string());
            }
        }
    }

    // Sort entries naturally (video0, video1, video2...)
    entries.sort_by_key(|path| {
        path.strip_prefix("/dev/video")
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(999)
    });

    for path in entries {
        if let Some(info) = probe_single_device(&path).await {
            devices.push(info);
        }
    }

    devices
}

/// Probe a single V4L2 device by path.
pub async fn probe_single_device(device_path: &str) -> Option<CameraDeviceInfo> {
    if !Path::new(device_path).exists() {
        return None;
    }

    let has_v4l2_ctl = which::which("v4l2-ctl").is_ok();

    if has_v4l2_ctl {
        probe_with_v4l2_ctl(device_path).await
    } else {
        probe_fallback(device_path)
    }
}

async fn probe_with_v4l2_ctl(device_path: &str) -> Option<CameraDeviceInfo> {
    // Run v4l2-ctl --device=<path> --all
    let output_all = Command::new("v4l2-ctl")
        .args(&["--device", device_path, "--all"])
        .output()
        .await
        .ok()?;

    let all_stdout = String::from_utf8_lossy(&output_all.stdout);

    // If ioctl failed or not a video device
    if !output_all.status.success() || all_stdout.contains("Invalid argument") {
        return None;
    }

    let mut card_name = String::new();
    let mut is_capture = false;

    for line in all_stdout.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("Card type") {
            if let Some((_, val)) = trimmed.split_once(':') {
                card_name = val.trim().to_string();
            }
        } else if trimmed.contains("Video Capture") {
            is_capture = true;
        }
    }

    if card_name.is_empty() {
        // Try fallback card name extraction
        if let Some(first_line) = all_stdout.lines().next() {
            if first_line.contains(':') {
                card_name = first_line
                    .split(':')
                    .next()
                    .unwrap_or(device_path)
                    .trim()
                    .to_string();
            }
        }
    }

    if card_name.is_empty() {
        card_name = format!("V4L2 Camera ({})", device_path);
    }

    // Run v4l2-ctl --device=<path> --list-formats-ext
    let output_fmts = Command::new("v4l2-ctl")
        .args(&["--device", device_path, "--list-formats-ext"])
        .output()
        .await
        .ok();

    let mut formats = Vec::new();
    let mut resolutions = Vec::new();

    if let Some(fmts_out) = output_fmts {
        let stdout = String::from_utf8_lossy(&fmts_out.stdout);
        for line in stdout.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with('[') && trimmed.contains(':') {
                // e.g. [0]: 'MJPG' (Motion-JPEG, compressed)
                if let Some(fmt) = trimmed.split('\'').nth(1) {
                    if !formats.contains(&fmt.to_string()) {
                        formats.push(fmt.to_string());
                    }
                }
            } else if trimmed.starts_with("Size:") {
                // e.g. Size: Discrete 1280x720
                if let Some(res) = trimmed.split_whitespace().last() {
                    if res.contains('x') && !resolutions.contains(&res.to_string()) {
                        resolutions.push(res.to_string());
                    }
                }
            }
        }
    }

    let is_dummy = card_name.to_lowercase().contains("dummy")
        || card_name.to_lowercase().contains("v4l2loopback");

    let is_functional = is_capture && (!formats.is_empty() || !resolutions.is_empty() || is_dummy);

    Some(CameraDeviceInfo {
        device_path: device_path.to_string(),
        name: card_name,
        formats,
        resolutions,
        is_functional,
        is_dummy,
    })
}

fn probe_fallback(device_path: &str) -> Option<CameraDeviceInfo> {
    let is_dummy = device_path == "/dev/video0";
    Some(CameraDeviceInfo {
        device_path: device_path.to_string(),
        name: format!("Video Device ({})", device_path),
        formats: vec![],
        resolutions: vec![],
        is_functional: true,
        is_dummy,
    })
}

/// Helper to return functional physical cameras, preferring real webcams over loopback dummies.
pub async fn get_best_camera_device() -> Option<String> {
    let cameras = probe_cameras().await;

    // First try functional non-dummy webcams
    if let Some(real_cam) = cameras.iter().find(|c| c.is_functional && !c.is_dummy) {
        return Some(real_cam.device_path.clone());
    }

    // Fallback to any functional camera
    if let Some(any_cam) = cameras.iter().find(|c| c.is_functional) {
        return Some(any_cam.device_path.clone());
    }

    None
}
