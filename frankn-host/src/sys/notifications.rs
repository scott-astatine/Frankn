use crate::{HostMessage, elog, log, sys::rtc::PeerMap};
use futures_util::stream::StreamExt;
use std::sync::Arc;
use tokio_tungstenite::tungstenite::Bytes;

#[cfg(target_os = "linux")]
use zbus::{MatchRule, message::Type};

pub async fn start_notification_listener(peer_map: PeerMap) {
    #[cfg(target_os = "linux")]
    {
        tokio::spawn(async move {
            if let Ok(conn) = zbus::Connection::session().await {
                log!("DBus Monitor active. Listening for notifications...");
                let pm = Arc::clone(&peer_map);

                // Create a match rule to filter for Notify method calls
                let rule = match MatchRule::builder()
                    .msg_type(Type::MethodCall)
                    .interface("org.freedesktop.Notifications")
                    .and_then(|r| r.member("Notify"))
                {
                    Ok(r) => r.build(),
                    Err(e) => {
                        elog!("Failed to build match rule: {}", e);
                        return;
                    }
                };

                // Set up a message stream with our filter
                if let Ok(mut stream) =
                    zbus::MessageStream::for_match_rule(rule, &conn, Some(1)).await
                {
                    // Loop forever, pulling messages
                    while let Some(msg_result) = stream.next().await {
                        if let Ok(msg) = msg_result {
                            // Extract notification details from the message body
                            // The Notify method signature is:
                            // app_name: STRING, replaces_id: UINT32, app_icon: STRING,
                            // title: STRING, body: STRING, actions: ARRAY, hints: DICT,
                            // expire_timeout: INT32
                            if let Ok((
                                app_name,
                                _replaces_id,
                                _app_icon,
                                title,
                                body_text,
                                _actions,
                                _hints,
                                _timeout,
                            )) = msg.body().deserialize::<(
                                &str,
                                u32,
                                &str,
                                &str,
                                &str,
                                Vec<(&str, &str)>,
                                std::collections::HashMap<&str, zvariant::Value>,
                                i32,
                            )>() {
                                    // Forward to all clients
                                    _send_notification_to_client(
                                        pm.clone(),
                                        app_name,
                                        title,
                                        body_text,
                                    )
                                    .await;
                            }
                        }
                    }
                }
            }
        });
    }
}

pub async fn _send_notification_to_client(
    peer_map: PeerMap,
    app_name: &str,
    title: &str,
    body: &str,
) {
    let msg = HostMessage::Notification {
        id: rand::random::<u32>(),
        app_name: app_name.to_string(),
        title: title.to_string(),
        body: body.to_string(),
        timestamp: crate::utils::get_timestamp(),
    };

    if let Ok(json) = serde_json::to_string(&msg) {
        let connections = peer_map.lock().await;
        for (client_id, conn) in connections.iter() {
            log!("Sending notification to client {}", client_id);
            let _ = conn.lock().await.send_message("frankn_cmd", &Bytes::from(json.clone())).await;
        }
    }
}
