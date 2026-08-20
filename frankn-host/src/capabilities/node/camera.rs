use std::sync::Arc;
use tokio::net::UdpSocket;
use tokio::process::Command;
use webrtc::track::track_local::track_local_static_rtp::TrackLocalStaticRTP;
use webrtc::track::track_local::TrackLocalWriter;

pub struct CameraRunner {
    track: Arc<TrackLocalStaticRTP>,
}

impl CameraRunner {
    pub fn new(track: Arc<TrackLocalStaticRTP>) -> Self {
        Self { track }
    }

    pub async fn start(self) {
        tokio::spawn(async move {
            crate::log!("CAMERA: Starting camera streaming thread...");
            
            let dev_exists = std::path::Path::new("/dev/video0").exists();
            let gst_available = which::which("gst-launch-1.0").is_ok();

            if dev_exists && gst_available {
                crate::log!("CAMERA: V4L2 camera and GStreamer detected. Initializing UDP bridge...");
                
                let sock = match UdpSocket::bind("127.0.0.1:0").await {
                    Ok(s) => s,
                    Err(e) => {
                        crate::elog!("CAMERA: Failed to bind UDP socket: {e}. Falling back to synthetic stream.");
                        self.run_synthetic_loop().await;
                        return;
                    }
                };

                let port = match sock.local_addr() {
                    Ok(addr) => addr.port(),
                    Err(e) => {
                        crate::elog!("CAMERA: Failed to get local address: {e}. Falling back to synthetic stream.");
                        self.run_synthetic_loop().await;
                        return;
                    }
                };

                crate::log!("CAMERA: UDP bridge listening on port {port}. Spawning GStreamer pipeline...");

                // Spawn GStreamer process
                let mut child = match Command::new("gst-launch-1.0")
                    .args(&[
                        "v4l2src", "device=/dev/video0",
                        "!", "video/x-raw,width=640,height=480,framerate=30/1",
                        "!", "videoconvert",
                        "!", "vp8enc", "target-bitrate=800000", "deadline=1", "cpu-used=4",
                        "!", "rtpvp8pay", "pt=96", "ssrc=12345",
                        "!", "udpsink", "host=127.0.0.1", &format!("port={}", port)
                    ])
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null())
                    .spawn()
                {
                    Ok(c) => c,
                    Err(e) => {
                        crate::elog!("CAMERA: Failed to spawn GStreamer child: {e}. Falling back to synthetic stream.");
                        self.run_synthetic_loop().await;
                        return;
                    }
                };

                let mut buf = vec![0u8; 65536];

                loop {
                    tokio::select! {
                        res = sock.recv_from(&mut buf) => {
                            match res {
                                Ok((len, _)) => {
                                    let write_res: Result<usize, webrtc::Error> = self.track.write(&buf[..len]).await;
                                    if write_res.is_err() {
                                        crate::elog!("CAMERA: Write to track failed, stopping stream.");
                                        break;
                                    }
                                }
                                Err(e) => {
                                    crate::elog!("CAMERA: UDP receive error: {e}");
                                    break;
                                }
                            }
                        }
                        _ = child.wait() => {
                            crate::elog!("CAMERA: GStreamer child process exited.");
                            break;
                        }
                    }
                }

                let _ = child.kill().await;
            } else {
                crate::log!("CAMERA: No physical V4L2 camera or GStreamer available. Streaming synthetic VP8 source...");
                self.run_synthetic_loop().await;
            }
        });
    }

    async fn run_synthetic_loop(&self) {
        use webrtc::rtp::header::Header;
        use webrtc::rtp::packet::Packet;

        let mut sequence_number: u16 = 0;
        let mut timestamp: u32 = 0;
        let ssrc: u32 = 12345;

        loop {
            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

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

            let res: Result<usize, webrtc::Error> = self.track.write_rtp(&packet).await;
            if res.is_err() {
                break;
            }

            sequence_number = sequence_number.wrapping_add(1);
            timestamp = timestamp.wrapping_add(9000); // 10fps
        }
    }
}
