use crate::{utils::Status, HostMessage, sys::rtc::RTCConn};
use std::collections::HashMap;
use sysinfo::{ProcessRefreshKind, RefreshKind, System, MemoryRefreshKind};
use tokio::process::Command;
use std::sync::Arc;
use tokio::sync::Mutex;

pub async fn list_processes(
    id: &str, 
    sort_by: &Option<String>, 
    filter: &Option<String>,
    _rtc: Arc<Mutex<RTCConn>>
) -> HostMessage {
    let mut sys = System::new_with_specifics(
        RefreshKind::nothing()
            .with_processes(ProcessRefreshKind::everything())
            .with_cpu(sysinfo::CpuRefreshKind::everything())
            .with_memory(MemoryRefreshKind::everything()),
    );
    
    sys.refresh_cpu_all();
    sys.refresh_processes(sysinfo::ProcessesToUpdate::All, true);

    let total_mem = sys.total_memory();
    let used_mem = sys.used_memory();
    let global_cpu = sys.global_cpu_usage();

    let mut grouped: HashMap<String, (u32, u64, f32, String, String, String)> = HashMap::new();

    let filter_lower = filter.as_ref().map(|f| f.to_lowercase());

    for p in sys.processes().values() {
        let name = p.name().to_string_lossy().to_string();
        
        // Host-side filtering
        if let Some(ref f) = filter_lower {
            if !name.to_lowercase().contains(f) {
                continue;
            }
        }

        let cmd = p.cmd().iter().map(|s| s.to_string_lossy().to_string()).collect::<Vec<_>>().join(" ");
        let status = format!("{:?}", p.status());
        let user = p.user_id().map(|u| u.to_string()).unwrap_or_else(|| "root".to_string());

        let entry = grouped.entry(name.clone()).or_insert((
            p.pid().as_u32(), 
            0, 
            0.0, 
            status, 
            cmd,
            user
        ));

        if p.pid().as_u32() < entry.0 {
            entry.0 = p.pid().as_u32();
        }
        entry.1 += p.memory();
        entry.2 += p.cpu_usage();
    }

    let mut list: Vec<_> = grouped
        .into_iter()
        .map(|(name, (pid, mem, cpu, status, cmd, user))| {
            serde_json::json!({
                "pid": pid,
                "name": name,
                "memory": mem,
                "cpu": cpu,
                "status": status,
                "cmd": cmd,
                "user": user
            })
        })
        .collect();

    // Host-side sorting
    match sort_by.as_deref() {
        Some("memory") => {
            list.sort_by(|a, b| {
                b["memory"].as_u64().unwrap_or(0).cmp(&a["memory"].as_u64().unwrap_or(0))
            });
        },
        Some("name") => {
            list.sort_by(|a, b| {
                a["name"].as_str().unwrap_or("").cmp(b["name"].as_str().unwrap_or(""))
            });
        },
        _ => { // Default: CPU
            list.sort_by(|a, b| {
                b["cpu"]
                    .as_f64()
                    .unwrap_or(0.0)
                    .partial_cmp(&a["cpu"].as_f64().unwrap_or(0.0))
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
        }
    }

    HostMessage::Response {
        id: id.to_string(),
        status: Status::Success,
        data: Some(serde_json::json!({ 
            "processes": list.into_iter().take(100).collect::<Vec<_>>(),
            "stats": {
                "total_mem": total_mem,
                "used_mem": used_mem,
                "cpu_load": global_cpu
            }
        })),
        timestamp: crate::utils::get_timestamp(),
    }
}

pub async fn kill_process(id: &str, proc: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    let output = if let Ok(_pid) = proc.parse::<i32>() {
        #[cfg(target_os = "linux")]
        Command::new("kill").arg("-9").arg(proc).output().await
    } else {
        #[cfg(target_os = "linux")]
        Command::new("pkill").arg("-9").arg(proc).output().await
    };

    match output {
        Ok(_) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Success,
            data: Some(serde_json::json!({ "message": format!("Terminated {}", proc) })),
            timestamp: crate::utils::get_timestamp(),
        },
        Err(e) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(format!("Failed to kill {}: {}", proc, e)),
            data: None,
            timestamp: crate::utils::get_timestamp(),
        }
    }
}