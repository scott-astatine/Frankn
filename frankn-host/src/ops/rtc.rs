use std::{collections::HashMap, sync::Arc};

use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use webrtc::{
    api::{
        APIBuilder, interceptor_registry::register_default_interceptors, media_engine::MediaEngine,
    },
    data_channel::RTCDataChannel,
    ice_transport::ice_candidate::{RTCIceCandidate, RTCIceCandidateInit},
    interceptor::registry::Registry,
    peer_connection::{
        RTCPeerConnection, peer_connection_state::RTCPeerConnectionState,
        sdp::session_description::RTCSessionDescription,
    },
};

use crate::log;

pub type PeerMap = Arc<Mutex<HashMap<String, Arc<Mutex<RTCConn>>>>>;

pub struct RTCConn {
    pub peer_connection: Arc<RTCPeerConnection>,
    pub data_channels: Arc<Mutex<HashMap<String, Arc<RTCDataChannel>>>>,
    pub authenticated: Arc<Mutex<bool>>,
    pub current_challenge: Arc<Mutex<Option<String>>>,
    pub ssh_bridge_stop: Arc<Mutex<Option<tokio::sync::oneshot::Sender<()>>>>,
}

impl std::fmt::Display for RTCConn {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "(RTCPeerConnection {})", self.peer_connection)
    }
}

impl RTCConn {
    pub async fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let mut m = MediaEngine::default();

        let mut registry = Registry::new();

        registry = register_default_interceptors(registry, &mut m)?;

        let api = APIBuilder::new()
            .with_media_engine(m)
            .with_interceptor_registry(registry)
            .build();

        let config = webrtc::peer_connection::configuration::RTCConfiguration {
            ice_servers: vec![
                // Google STUN servers (primary - most reliable)
                webrtc::ice_transport::ice_server::RTCIceServer {
                    urls: vec!["stun:stun.l.google.com:19302".to_string()],
                    ..Default::default()
                },
                webrtc::ice_transport::ice_server::RTCIceServer {
                    urls: vec!["stun:stun1.l.google.com:19302".to_string()],
                    ..Default::default()
                },
                webrtc::ice_transport::ice_server::RTCIceServer {
                    urls: vec!["stun:stun2.l.google.com:19302".to_string()],
                    ..Default::default()
                },
                webrtc::ice_transport::ice_server::RTCIceServer {
                    urls: vec!["stun:stun3.l.google.com:19302".to_string()],
                    ..Default::default()
                },
                webrtc::ice_transport::ice_server::RTCIceServer {
                    urls: vec!["stun:stun4.l.google.com:19302".to_string()],
                    ..Default::default()
                },
                // Mozilla STUN (independent provider for redundancy)
                webrtc::ice_transport::ice_server::RTCIceServer {
                    urls: vec!["stun:stun.services.mozilla.com".to_string()],
                    ..Default::default()
                },
                // Twilio STUN (enterprise-grade reliability)
                webrtc::ice_transport::ice_server::RTCIceServer {
                    urls: vec!["stun:global.stun.twilio.com:3478".to_string()],
                    ..Default::default()
                },
            ],
            // ICE configuration optimizations
            ice_candidate_pool_size: 10, // Pre-gather candidates for faster connection
            ..Default::default()
        };

        let peer_connection = Arc::new(api.new_peer_connection(config).await?);

        Ok(Self {
            peer_connection,
            data_channels: Arc::new(Mutex::new(HashMap::new())),
            authenticated: Arc::new(Mutex::new(false)),
            current_challenge: Arc::new(Mutex::new(None)),
            ssh_bridge_stop: Arc::new(Mutex::new(None)),
        })
    }

    pub async fn set_remote_data_channel_handler(
        &self,
        on_channel: impl Fn(Arc<RTCDataChannel>) + Send + Sync + 'static + Clone,
    ) {
        let data_channels = Arc::clone(&self.data_channels);
        self.peer_connection
            .on_data_channel(Box::new(move |d: Arc<RTCDataChannel>| {
                println!("New DataChannel: {} {}", d.label(), d.id());
                let d_label = d.label().to_owned();
                let d_clone = Arc::clone(&d);

                let on_channel = on_channel.clone();
                let data_channels = Arc::clone(&data_channels);

                Box::pin(async move {
                    {
                        let mut map = data_channels.lock().await;
                        map.insert(d_label.clone(), Arc::clone(&d_clone));
                    }
                    on_channel(d_clone);
                })
            }));
    }

    pub async fn send_message(
        &self,
        label: &str,
        data: &Bytes,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let map = self.data_channels.lock().await;
        if let Some(dc) = map.get(label) {
            dc.send(data).await?;
            Ok(())
        } else {
            Err(format!("Data channel '{}' not found", label).into())
        }
    }

    pub async fn get_buffered_amount(&self, label: &str) -> usize {
        let map = self.data_channels.lock().await;
        if let Some(dc) = map.get(label) {
            dc.buffered_amount().await
        } else {
            0
        }
    }

    pub async fn add_remote_candidate(
        &self,
        candidate: String,
        sdp_mid: Option<String>,
        sdp_mline_index: Option<u16>,
    ) -> Result<(), webrtc::Error> {
        let candidate_init = RTCIceCandidateInit {
            candidate,
            sdp_mid,
            sdp_mline_index,
            ..Default::default()
        };
        self.peer_connection.add_ice_candidate(candidate_init).await
    }

    // pub async fn create_offer(&self) -> Result<RTCSessionDescription, Box<dyn std::error::Error>> {
    //     let offer = self.peer_connection.create_offer(None).await?;
    //     self.peer_connection
    //         .set_local_description(offer.clone())
    //         .await?;
    //     Ok(offer)
    // }

    pub async fn create_answer(&self) -> Result<RTCSessionDescription, Box<dyn std::error::Error>> {
        let answer = self.peer_connection.create_answer(None).await?;
        self.peer_connection
            .set_local_description(answer.clone())
            .await?;
        Ok(answer)
    }

    pub async fn set_remote_description(
        &self,
        sdp: RTCSessionDescription,
    ) -> Result<(), Box<dyn std::error::Error>> {
        self.peer_connection.set_remote_description(sdp).await?;
        Ok(())
    }

    pub fn on_ice_candidate<F>(&self, f: F)
    where
        F: Fn(Option<RTCIceCandidate>) + Send + Sync + 'static,
    {
        self.peer_connection.on_ice_candidate(Box::new(
            move |candidate: Option<RTCIceCandidate>| {
                f(candidate);
                Box::pin(async {})
            },
        ));
    }

    pub fn on_peer_connection_state_change<F>(&self, f: F)
    where
        F: Fn(RTCPeerConnectionState) + Send + Sync + 'static,
    {
        self.peer_connection
            .on_peer_connection_state_change(Box::new(move |state: RTCPeerConnectionState| {
                f(state);
                Box::pin(async {})
            }))
    }

    pub async fn close(&self) -> Result<(), Box<dyn std::error::Error>> {
        log!("Closing RTCConnection and all data channels");

        // Stop SSH bridge if active
        let bridge_stop = {
            let mut stop_lock = self.ssh_bridge_stop.lock().await;
            stop_lock.take()
        };
        if let Some(tx) = bridge_stop {
            let _ = tx.send(());
        }

        // Close all data channels
        let mut channels = self.data_channels.lock().await;
        for (label, dc) in channels.drain() {
            log!("Closing data channel: {}", label);
            let _ = dc.close().await;
        }

        self.peer_connection.close().await?;
        Ok(())
    }
}
