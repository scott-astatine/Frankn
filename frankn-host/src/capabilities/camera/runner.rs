use std::collections::HashMap;
use std::process::Stdio;
use std::sync::{Arc, LazyLock};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::net::UdpSocket;
use tokio::process::Command;
use tokio::sync::Mutex;
use webrtc::track::track_local::TrackLocalWriter;
use webrtc::track::track_local::track_local_static_rtp::TrackLocalStaticRTP;

use super::probe::get_best_camera_device;

static BROADCASTER: LazyLock<Arc<CameraBroadcaster>> = LazyLock::new(|| {
    Arc::new(CameraBroadcaster {
        sessions: Arc::new(Mutex::new(HashMap::new())),
    })
});

/// Manages shared camera broadcasting sessions across multiple simultaneous clients.
pub struct CameraBroadcaster {
    sessions: Arc<Mutex<HashMap<String, Arc<BroadcasterSession>>>>,
}

struct BroadcasterSession {
    subscribers: Arc<Mutex<HashMap<String, Arc<TrackLocalStaticRTP>>>>,
    stop_tx: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
}

impl CameraBroadcaster {
    pub fn global() -> Arc<Self> {
        BROADCASTER.clone()
    }

    /// Subscribes a WebRTC video track (associated with `session_id`) to the camera stream for `device_path`.
    pub async fn subscribe(
        &self,
        device_path: Option<String>,
        session_id: String,
        track: Arc<TrackLocalStaticRTP>,
    ) {
        let device = match device_path {
            Some(ref p) if !p.is_empty() => p.clone(),
            _ => get_best_camera_device()
                .await
                .unwrap_or_else(|| "/dev/video0".to_string()),
        };

        let mut sessions_map = self.sessions.lock().await;

        if let Some(broadcaster_sess) = sessions_map.get(&device) {
            crate::log!(
                "[CAMERA_BROADCASTER] Adding subscriber session '{}' to active stream for '{}'",
                &session_id,
                &device
            );
            broadcaster_sess
                .subscribers
                .lock()
                .await
                .insert(session_id, track);
        } else {
            crate::log!(
                "[CAMERA_BROADCASTER] Initializing new hardware stream for '{}' (first subscriber: '{}')",
                &device,
                &session_id
            );

            let subscribers: Arc<Mutex<HashMap<String, Arc<TrackLocalStaticRTP>>>> =
                Arc::new(Mutex::new(HashMap::new()));
            subscribers.lock().await.insert(session_id, track);

            let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
            let subscribers_clone = Arc::clone(&subscribers);
            let device_clone = device.clone();
            let sessions_map_ref = Arc::clone(&self.sessions);

            tokio::spawn(async move {
                Self::run_broadcaster_loop(device_clone.clone(), subscribers_clone, stop_rx).await;

                // Cleanup session from sessions map when loop terminates
                let mut map = sessions_map_ref.lock().await;
                map.remove(&device_clone);
                crate::log!(
                    "[CAMERA_BROADCASTER] Hardware stream for '{}' terminated and cleaned up.",
                    &device_clone
                );
            });

            sessions_map.insert(
                device,
                Arc::new(BroadcasterSession {
                    subscribers,
                    stop_tx: Mutex::new(Some(stop_tx)),
                }),
            );
        }
    }

    /// Unsubscribes a session from the camera stream. If no subscribers remain, stops the camera stream.
    pub async fn unsubscribe(&self, device_path: Option<String>, session_id: &str) {
        let device = match device_path {
            Some(ref p) if !p.is_empty() => p.clone(),
            _ => get_best_camera_device()
                .await
                .unwrap_or_else(|| "/dev/video0".to_string()),
        };

        let mut sessions_map = self.sessions.lock().await;
        let should_remove = if let Some(broadcaster_sess) = sessions_map.get(&device) {
            let mut subs = broadcaster_sess.subscribers.lock().await;
            subs.remove(session_id);
            crate::log!(
                "[CAMERA_BROADCASTER] Removed subscriber session '{}' from '{}' (remaining subscribers: {})",
                session_id,
                &device,
                subs.len()
            );
            subs.is_empty()
        } else {
            false
        };

        if should_remove {
            crate::log!(
                "[CAMERA_BROADCASTER] No remaining subscribers for '{}'. Stopping hardware stream...",
                &device
            );
            if let Some(sess) = sessions_map.remove(&device) {
                if let Some(tx) = sess.stop_tx.lock().await.take() {
                    let _ = tx.send(());
                }
            }
        }
    }

    async fn run_broadcaster_loop(
        device: String,
        subscribers: Arc<Mutex<HashMap<String, Arc<TrackLocalStaticRTP>>>>,
        mut stop_rx: tokio::sync::oneshot::Receiver<()>,
    ) {
        let dev_exists = std::path::Path::new(&device).exists();
        let gst_available = which::which("gst-launch-1.0").is_ok();

        crate::log!(
            "[CAMERA_BROADCASTER] Target device='{}', exists={}, gst_available={}",
            &device,
            dev_exists,
            gst_available
        );

        if dev_exists && gst_available {
            let sock = match UdpSocket::bind("127.0.0.1:0").await {
                Ok(s) => s,
                Err(e) => {
                    crate::elog!(
                        "[CAMERA_BROADCASTER] Failed to bind UDP socket: {e}. Falling back to synthetic stream."
                    );
                    Self::run_synthetic_broadcaster_loop(subscribers, stop_rx).await;
                    return;
                }
            };

            let port = match sock.local_addr() {
                Ok(addr) => addr.port(),
                Err(e) => {
                    crate::elog!(
                        "[CAMERA_BROADCASTER] Failed to get local address: {e}. Falling back to synthetic stream."
                    );
                    Self::run_synthetic_broadcaster_loop(subscribers, stop_rx).await;
                    return;
                }
            };

            crate::log!(
                "[CAMERA_BROADCASTER] Local UDP bridge listening on 127.0.0.1:{port}. Spawning single GStreamer pipeline for '{device}'..."
            );

            let device_arg = format!("device={}", device);

            let mut child = match Command::new("gst-launch-1.0")
                .args(&[
                    "v4l2src",
                    &device_arg,
                    "!",
                    "decodebin",
                    "!",
                    "videoconvert",
                    "!",
                    "vp8enc",
                    "target-bitrate=800000",
                    "deadline=1",
                    "cpu-used=4",
                    "!",
                    "rtpvp8pay",
                    "pt=96",
                    "ssrc=12345",
                    "!",
                    "udpsink",
                    "host=127.0.0.1",
                    &format!("port={}", port),
                ])
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
            {
                Ok(c) => c,
                Err(e) => {
                    crate::elog!(
                        "[CAMERA_BROADCASTER] Failed to spawn GStreamer process: {e}. Falling back to synthetic stream."
                    );
                    Self::run_synthetic_broadcaster_loop(subscribers, stop_rx).await;
                    return;
                }
            };

            if let Some(stderr) = child.stderr.take() {
                tokio::spawn(async move {
                    let mut reader = BufReader::new(stderr).lines();
                    while let Ok(Some(line)) = reader.next_line().await {
                        crate::elog!("GSTREAMER_STDERR: {line}");
                    }
                });
            }

            if let Some(stdout) = child.stdout.take() {
                tokio::spawn(async move {
                    let mut reader = BufReader::new(stdout).lines();
                    while let Ok(Some(line)) = reader.next_line().await {
                        crate::log!("GSTREAMER_STDOUT: {line}");
                    }
                });
            }

            let mut buf = vec![0u8; 65536];
            let mut packet_count: u64 = 0;
            let mut total_bytes: u64 = 0;

            loop {
                tokio::select! {
                    _ = &mut stop_rx => {
                        crate::log!("[CAMERA_BROADCASTER] Stop signal received for '{device}'. Exiting loop.");
                        break;
                    }
                    res = sock.recv_from(&mut buf) => {
                        match res {
                            Ok((len, _)) => {
                                packet_count += 1;
                                total_bytes += len as u64;

                                if packet_count == 1 {
                                    crate::log!("[CAMERA_BROADCASTER] First video RTP packet received from GStreamer ({} bytes). Broadcasting to WebRTC subscribers...", len);
                                } else if packet_count % 100 == 0 {
                                    let sub_count = subscribers.lock().await.len();
                                    crate::log!("[CAMERA_BROADCASTER] Stream Active. Sent {} RTP packets ({} KB total) to {} subscribers", packet_count, total_bytes / 1024, sub_count);
                                }

                                // Fan out RTP packet to all active subscriber WebRTC tracks!
                                let tracks: Vec<Arc<TrackLocalStaticRTP>> = {
                                    let subs = subscribers.lock().await;
                                    subs.values().cloned().collect()
                                };

                                for track in tracks {
                                    let _ = track.write(&buf[..len]).await;
                                }
                            }
                            Err(e) => {
                                crate::elog!("[CAMERA_BROADCASTER] UDP receive error: {e}");
                                break;
                            }
                        }
                    }
                    status = child.wait() => {
                        match status {
                            Ok(s) => crate::elog!("[CAMERA_BROADCASTER] GStreamer child process exited with status: {s}"),
                            Err(e) => crate::elog!("[CAMERA_BROADCASTER] Error waiting for GStreamer child: {e}"),
                        }
                        break;
                    }
                }
            }

            let _ = child.kill().await;
            crate::log!(
                "[CAMERA_BROADCASTER] Killed GStreamer process and released camera device '{device}'."
            );
        } else {
            crate::log!(
                "[CAMERA_BROADCASTER] Device '{}' or GStreamer unavailable. Streaming synthetic VP8 source...",
                &device
            );
            Self::run_synthetic_broadcaster_loop(subscribers, stop_rx).await;
        }
    }

    async fn run_synthetic_broadcaster_loop(
        subscribers: Arc<Mutex<HashMap<String, Arc<TrackLocalStaticRTP>>>>,
        mut stop_rx: tokio::sync::oneshot::Receiver<()>,
    ) {
        use webrtc::rtp::header::Header;
        use webrtc::rtp::packet::Packet;

        let mut sequence_number: u16 = 0;
        let mut timestamp: u32 = 0;
        let ssrc: u32 = 12345;
        let mut count: u64 = 0;

        crate::log!("[CAMERA_BROADCASTER] Starting synthetic VP8 RTP broadcasting loop...");

        loop {
            tokio::select! {
                _ = &mut stop_rx => {
                    crate::log!("[CAMERA_BROADCASTER] Stop signal received during synthetic loop. Exiting.");
                    break;
                }
                _ = tokio::time::sleep(tokio::time::Duration::from_millis(100)) => {
                    let mock_payload = vec![0x10, 0x20, 0x30, 0x40];

                    let packet = Packet {
                        header: Header {
                            version: 2,
                            padding: false,
                            extension: false,
                            marker: true,
                            payload_type: 96,
                            sequence_number,
                            timestamp,
                            ssrc,
                            ..Default::default()
                        },
                        payload: mock_payload.into(),
                    };

                    let tracks: Vec<Arc<TrackLocalStaticRTP>> = {
                        let subs = subscribers.lock().await;
                        subs.values().cloned().collect()
                    };

                    for track in tracks {
                        let _ = track.write_rtp(&packet).await;
                    }

                    count += 1;
                    if count % 100 == 0 {
                        crate::log!("[CAMERA_BROADCASTER] Sent {} synthetic RTP packets to {} subscribers", count, subscribers.lock().await.len());
                    }

                    sequence_number = sequence_number.wrapping_add(1);
                    timestamp = timestamp.wrapping_add(9000);
                }
            }
        }
    }
}

/// Backwards-compatible `CameraRunner` API wrapping `CameraBroadcaster`.
pub struct CameraRunner {
    track: Arc<TrackLocalStaticRTP>,
    device_path: Option<String>,
    session_id: String,
    stop_rx: tokio::sync::oneshot::Receiver<()>,
}

impl CameraRunner {
    pub fn new(
        track: Arc<TrackLocalStaticRTP>,
        device_path: Option<String>,
        session_id: String,
        stop_rx: tokio::sync::oneshot::Receiver<()>,
    ) -> Self {
        Self {
            track,
            device_path,
            session_id,
            stop_rx,
        }
    }

    pub async fn start(self) {
        let broadcaster = CameraBroadcaster::global();
        let device_path = self.device_path.clone();
        let session_id = self.session_id.clone();
        let track = self.track;
        let stop_rx = self.stop_rx;

        broadcaster
            .subscribe(device_path.clone(), session_id.clone(), track)
            .await;

        tokio::spawn(async move {
            let _ = stop_rx.await;
            broadcaster.unsubscribe(device_path, &session_id).await;
        });
    }
}
