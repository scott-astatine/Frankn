import 'dart:convert';

class IsolateMsg {
  final String type; // e.g., 'intent', 'event', 'state'
  final String action; // e.g., 'connect', 'upload', 'host_state_change'
  final Map<String, dynamic> payload;

  IsolateMsg({
    required this.type,
    required this.action,
    this.payload = const {},
  });

  String toJson() =>
      jsonEncode({'type': type, 'action': action, 'payload': payload});

  factory IsolateMsg.fromJson(String source) {
    final map = jsonDecode(source);
    return IsolateMsg(
      type: map['type']?.toString() ?? '',
      action: map['action']?.toString() ?? '',
      payload: map['payload'] is Map<String, dynamic>
          ? map['payload'] as Map<String, dynamic>
          : {},
    );
  }
}

class IsolateType {
  static const intent = "intent";
  static const state = "state";
  static const event = "event";
}

class IsolateAction {
  // Intent Actions (UI -> Background)
  static const connectSignaling = "connect_signaling";
  static const connectHost = "connect_host";
  static const disconnectHost = "disconnect_host";
  static const sendDcMsg = "send_dc_msg";
  static const sendInput = "send_input";
  static const downloadInit = "download_init";
  static const authenticate = "authenticate";
  static const sshInput = "ssh_input";
  static const startSsh = "start_ssh";
  static const stopSsh = "stop_ssh";
  static const requestHostList = "request_host_list";
  static const syncState = "sync_state";
  static const uploadInit = "upload_init";
  static const logIntent = "log_intent";
  static const folderSyncInit = "folder_sync_init";

  // State & Event Actions (Background -> UI)
  static const hostState = "host_state";
  static const sigState = "sig_state";
  static const isolateReady = "isolate_ready";
  static const commandResponse = "command_response";
  static const peerStatus = "peer_status";
  static const hostList = "host_list";
  static const logEvent = "log_event";
  static const notification = "notification";
  static const transferProgress = "transfer_progress";
  static const transferComplete = "transfer_complete";
  static const transferFailed = "transfer_failed";
  static const downloadStart = "download_start";
  static const downloadEnd = "download_end";
  static const folderSyncSnapshot = "folder_sync_snapshot";
  static const folderSyncProgress = "folder_sync_progress";
  static const folderSyncComplete = "folder_sync_complete";
  static const sshOutput = "ssh_output";
  static const authFailed = "auth_failed";
  static const authSuccess = "auth_success";
}
