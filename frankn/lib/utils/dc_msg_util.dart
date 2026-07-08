import 'dart:convert';

/// Base class for all messages received from the Host.
/// Mirrors the `HostMessage` enum in Rust.
sealed class HostMessage {
  final String type;

  const HostMessage(this.type);

  factory HostMessage.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString();
    switch (type) {
      case 'challenge':
        return HostMsgChallenge.fromJson(json);
      case 'auth_success':
        return HostMsgAuthSuccess.fromJson(json);
      case 'auth_failed':
        return HostMsgAuthFailed.fromJson(json);
      case 'llm_token':
        return HostMsgLlmToken.fromJson(json);
      case 'media_update':
        return HostMsgMediaUpdate.fromJson(json);
      case 'response':
        return HostMsgResponse.fromJson(json);
      case 'tool_approval_request':
        return HostMsgToolApprovalRequest.fromJson(json);
      case 'notification':
        return HostMsgNotification.fromJson(json);
      case 'telemetry':
        return HostMsgTelemetry.fromJson(json);
      case 'transfer_ack':
        return HostMsgTransferAck.fromJson(json);
      case 'transfer_complete':
        return HostMsgTransferComplete.fromJson(json);
      case 'transfer_cancel':
        return HostMsgTransferCancel.fromJson(json);
      case 'download_start':
        return HostMsgDownloadStart.fromJson(json);
      case 'download_end':
        return HostMsgDownloadEnd.fromJson(json);
      case 'sync_snapshot':
        return HostMsgSyncSnapshot.fromJson(json);
      default:
        return HostMsgUnknown(json);
    }
  }

  factory HostMessage.parse(String data) {
    return HostMessage.fromJson(jsonDecode(data));
  }

  Map<String, dynamic> toJson() {
    return {'type': type};
  }
}

class HostMsgChallenge extends HostMessage {
  final String challenge;
  final String salt;
  final int timestamp;

  HostMsgChallenge({
    required this.challenge,
    required this.salt,
    required this.timestamp,
  }) : super('challenge');

  factory HostMsgChallenge.fromJson(Map<String, dynamic> json) {
    return HostMsgChallenge(
      challenge: (json['challenge'] ?? '').toString(),
      salt: (json['salt'] ?? '').toString(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({'challenge': challenge, 'salt': salt, 'timestamp': timestamp});
}

class HostMsgAuthSuccess extends HostMessage {
  final String token;
  final int timestamp;

  HostMsgAuthSuccess({required this.token, required this.timestamp})
    : super('auth_success');

  factory HostMsgAuthSuccess.fromJson(Map<String, dynamic> json) {
    return HostMsgAuthSuccess(
      token: (json['token'] ?? '').toString(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'token': token, 'timestamp': timestamp});
}

class HostMsgAuthFailed extends HostMessage {
  final String error;
  final int timestamp;

  HostMsgAuthFailed({required this.error, required this.timestamp})
    : super('auth_failed');

  factory HostMsgAuthFailed.fromJson(Map<String, dynamic> json) {
    return HostMsgAuthFailed(
      error: (json['error'] ?? 'Unknown error').toString(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'error': error, 'timestamp': timestamp});
}

class HostMsgLlmToken extends HostMessage {
  final String token;
  final bool isFinal;
  final int timestamp;

  HostMsgLlmToken({
    required this.token,
    required this.isFinal,
    required this.timestamp,
  }) : super('llm_token');

  factory HostMsgLlmToken.fromJson(Map<String, dynamic> json) {
    return HostMsgLlmToken(
      token: (json['token'] ?? '').toString(),
      isFinal: json['is_final'] == true,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()
        ..addAll({'token': token, 'is_final': isFinal, 'timestamp': timestamp});
}

class HostMsgToolApprovalRequest extends HostMessage {
  final String approvalId;
  final String tool;
  final String args;
  final int timestamp;

  HostMsgToolApprovalRequest({
    required this.approvalId,
    required this.tool,
    required this.args,
    required this.timestamp,
  }) : super('tool_approval_request');

  factory HostMsgToolApprovalRequest.fromJson(Map<String, dynamic> json) {
    return HostMsgToolApprovalRequest(
      approvalId: (json['approval_id'] ?? '').toString(),
      tool: (json['tool'] ?? '').toString(),
      args: (json['args'] ?? '').toString(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({
      'approval_id': approvalId,
      'tool': tool,
      'args': args,
      'timestamp': timestamp,
    });
}

class HostMsgMediaUpdate extends HostMessage {
  final String playerName;
  final bool playing;
  final String metadata;
  final String? artData;
  final double position;
  final double length;
  final double volume;
  final int timestamp;
  final String trackId;

  HostMsgMediaUpdate({
    required this.playerName,
    required this.playing,
    required this.metadata,
    this.artData,
    required this.position,
    required this.length,
    required this.volume,
    required this.timestamp,
    required this.trackId,
  }) : super('media_update');

  factory HostMsgMediaUpdate.fromJson(Map<String, dynamic> json) {
    return HostMsgMediaUpdate(
      playerName: (json['player_name'] ?? 'Unknown').toString().replaceAll(
        "org.mpris.MediaPlayer2.",
        "",
      ),
      playing: json['playing'] == true,
      metadata: (json['metadata'] ?? 'No Media').toString(),
      artData: json['art_data']?.toString(),
      position: (json['position'] as num?)?.toDouble() ?? 0.0,
      length: (json['length'] as num?)?.toDouble() ?? 0.0,
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      trackId: (json['track_id'] ?? '').toString(),
    );
  }

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({
      'player_name': playerName,
      'playing': playing,
      'metadata': metadata,
      'art_data': artData,
      'position': position,
      'length': length,
      'volume': volume,
      'timestamp': timestamp,
      'track_id': trackId,
    });

  HostMsgMediaUpdate copyWith({
    String? playerName,
    bool? playing,
    String? metadata,
    String? artData,
    double? position,
    double? length,
    double? volume,
    int? timestamp,
    String? trackId,
  }) {
    return HostMsgMediaUpdate(
      playerName: playerName ?? this.playerName,
      playing: playing ?? this.playing,
      metadata: metadata ?? this.metadata,
      artData: artData ?? this.artData,
      position: position ?? this.position,
      length: length ?? this.length,
      volume: volume ?? this.volume,
      timestamp: timestamp ?? this.timestamp,
      trackId: trackId ?? this.trackId,
    );
  }
}

class HostMsgResponse extends HostMessage {
  final String id;
  final String status;
  final dynamic data;
  final int timestamp;
  final String? error;

  HostMsgResponse({
    required this.id,
    required this.status,
    this.data,
    required this.timestamp,
    this.error,
  }) : super('response');

  factory HostMsgResponse.fromJson(Map<String, dynamic> json) {
    final statusObj = json['status'];
    String statusStr = 'Unknown';
    String? errorStr;

    if (statusObj == 'Success') {
      statusStr = 'Success';
    } else if (statusObj is Map && statusObj.containsKey('Error')) {
      statusStr = 'Error';
      errorStr = statusObj['Error']?.toString();
    } else {
      statusStr = statusObj?.toString() ?? 'Unknown';
    }

    return HostMsgResponse(
      id: (json['id'] ?? '0').toString(),
      status: statusStr,
      data: json['data'],
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      error: errorStr,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson()
      ..addAll({
        'id': id,
        'status': error != null ? {'Error': error} : status,
        'timestamp': timestamp,
      });
    if (data != null) map['data'] = data;
    return map;
  }
}

class HostMsgNotification extends HostMessage {
  final int id;
  final String appName;
  final String title;
  final String body;
  final int timestamp;

  HostMsgNotification({
    required this.id,
    required this.appName,
    required this.title,
    required this.body,
    required this.timestamp,
  }) : super('notification');

  factory HostMsgNotification.fromJson(Map<String, dynamic> json) {
    return HostMsgNotification(
      id: (json['id'] as num?)?.toInt() ?? 0,
      appName: (json['app_name'] ?? 'System').toString(),
      title: (json['title'] ?? 'Notification').toString(),
      body: (json['body'] ?? '').toString(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({
      'id': id,
      'app_name': appName,
      'title': title,
      'body': body,
      'timestamp': timestamp,
    });
}

class HostMsgTelemetry extends HostMessage {
  final double cpuLoad;
  final int usedMem;
  final int totalMem;
  final double cpuTemp;
  final int timestamp;

  HostMsgTelemetry({
    required this.cpuLoad,
    required this.usedMem,
    required this.totalMem,
    required this.cpuTemp,
    required this.timestamp,
  }) : super('telemetry');

  factory HostMsgTelemetry.fromJson(Map<String, dynamic> json) {
    return HostMsgTelemetry(
      cpuLoad: (json['cpu_load'] as num?)?.toDouble() ?? 0.0,
      usedMem: (json['used_mem'] as num?)?.toInt() ?? 0,
      totalMem: (json['total_mem'] as num?)?.toInt() ?? 0,
      cpuTemp: (json['cpu_temp'] as num?)?.toDouble() ?? 0.0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({
      'cpu_load': cpuLoad,
      'used_mem': usedMem,
      'total_mem': totalMem,
      'cpu_temp': cpuTemp,
      'timestamp': timestamp,
    });
}

class HostMsgTransferAck extends HostMessage {
  final String id;
  final int offset;
  final int seq;
  final int timestamp;

  HostMsgTransferAck({
    required this.id,
    required this.offset,
    required this.seq,
    required this.timestamp,
  }) : super('transfer_ack');

  factory HostMsgTransferAck.fromJson(Map<String, dynamic> json) {
    return HostMsgTransferAck(
      id: (json['id'] ?? '0').toString(),
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({'id': id, 'offset': offset, 'seq': seq, 'timestamp': timestamp});
}

class HostMsgTransferComplete extends HostMessage {
  final String id;
  final String hash;
  final int timestamp;

  HostMsgTransferComplete({
    required this.id,
    required this.hash,
    required this.timestamp,
  }) : super('transfer_complete');

  factory HostMsgTransferComplete.fromJson(Map<String, dynamic> json) {
    return HostMsgTransferComplete(
      id: (json['id'] ?? '0').toString(),
      hash: (json['hash'] ?? '').toString(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'id': id, 'hash': hash, 'timestamp': timestamp});
}

class HostMsgTransferCancel extends HostMessage {
  final String id;
  final int timestamp;

  HostMsgTransferCancel({required this.id, required this.timestamp})
    : super('transfer_cancel');

  factory HostMsgTransferCancel.fromJson(Map<String, dynamic> json) {
    return HostMsgTransferCancel(
      id: (json['id'] ?? '0').toString(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'id': id, 'timestamp': timestamp});
}

class HostMsgDownloadStart extends HostMessage {
  final String id;
  final String fileName;
  final int totalSize;
  final int offset;
  final String? hash;
  final int timestamp;

  HostMsgDownloadStart({
    required this.id,
    required this.fileName,
    required this.totalSize,
    required this.offset,
    this.hash,
    required this.timestamp,
  }) : super('download_start');

  factory HostMsgDownloadStart.fromJson(Map<String, dynamic> json) {
    return HostMsgDownloadStart(
      id: (json['id'] ?? '0').toString(),
      fileName: (json['file_name'] ?? 'file').toString(),
      totalSize: (json['total_size'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      hash: json['hash']?.toString(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson()
      ..addAll({
        'id': id,
        'file_name': fileName,
        'total_size': totalSize,
        'offset': offset,
        'timestamp': timestamp,
      });
    if (hash != null) map['hash'] = hash;
    return map;
  }
}

class HostMsgDownloadEnd extends HostMessage {
  final String id;
  final String hash;
  final int timestamp;

  HostMsgDownloadEnd({
    required this.id,
    required this.hash,
    required this.timestamp,
  }) : super('download_end');

  factory HostMsgDownloadEnd.fromJson(Map<String, dynamic> json) {
    return HostMsgDownloadEnd(
      id: (json['id'] ?? '0').toString(),
      hash: (json['hash'] ?? '').toString(),
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'id': id, 'hash': hash, 'timestamp': timestamp});
}

class HostMsgSyncSnapshot extends HostMessage {
  final String id;
  final String rootPath;
  final List<dynamic> files;
  final bool isFinal;
  final int timestamp;

  HostMsgSyncSnapshot({
    required this.id,
    required this.rootPath,
    required this.files,
    required this.isFinal,
    required this.timestamp,
  }) : super('sync_snapshot');

  factory HostMsgSyncSnapshot.fromJson(Map<String, dynamic> json) {
    return HostMsgSyncSnapshot(
      id: (json['id'] ?? '0').toString(),
      rootPath: (json['root_path'] ?? '').toString(),
      files: json['files'] as List<dynamic>? ?? [],
      isFinal: json['is_final'] == true,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({
      'id': id,
      'root_path': rootPath,
      'files': files,
      'is_final': isFinal,
      'timestamp': timestamp,
    });
}

/// Metadata for a file or directory entry on the remote host.
class RemoteEntry {
  final String name;
  final bool isDir;
  final int size;
  final String modified;
  final String? hash;

  RemoteEntry({
    required this.name,
    required this.isDir,
    required this.size,
    required this.modified,
    this.hash,
  });

  factory RemoteEntry.fromJson(Map<String, dynamic> json) {
    return RemoteEntry(
      name: (json['name'] ?? 'UNKNOWN').toString(),
      isDir: json['is_dir'] == true,
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified: (json['modified'] ?? '00:00:00').toString(),
      hash: json['hash']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'is_dir': isDir,
    'size': size,
    'modified': modified,
    'hash': hash,
  };
}

/// Represents the internal UI transfer progress events.
sealed class TransferProgressEvent {
  final String id;
  final String type;

  const TransferProgressEvent(this.id, this.type);

  factory TransferProgressEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString();
    final id = (json['id'] ?? 'unknown').toString();
    switch (type) {
      case 'start':
        return TransferProgressStart(id);
      case 'progress':
        return TransferProgressUpdate(
          id: id,
          progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
          bytesSent: (json['bytes_sent'] as num?)?.toInt() ?? 0,
          totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 1,
        );
      case 'complete':
        return TransferProgressComplete(
          id: id,
          finalPath: json['final_path']?.toString(),
          fileName: json['file_name']?.toString(),
        );
      case 'failed':
        return TransferProgressFailed(
          id: id,
          error: (json['error'] ?? 'Unknown error').toString(),
        );
      default:
        throw FormatException("Unknown transfer progress type: $type");
    }
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'type': type};
  }
}

class TransferProgressStart extends TransferProgressEvent {
  const TransferProgressStart(String id) : super(id, 'start');
}

class TransferProgressUpdate extends TransferProgressEvent {
  final double progress;
  final int bytesSent;
  final int totalBytes;

  const TransferProgressUpdate({
    required String id,
    required this.progress,
    required this.bytesSent,
    required this.totalBytes,
  }) : super(id, 'progress');

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({
      'progress': progress,
      'bytes_sent': bytesSent,
      'total_bytes': totalBytes,
    });
}

class TransferProgressComplete extends TransferProgressEvent {
  final String? finalPath;
  final String? fileName;

  const TransferProgressComplete({
    required String id,
    this.finalPath,
    this.fileName,
  }) : super(id, 'complete');

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'final_path': finalPath, 'file_name': fileName});
}

class TransferProgressFailed extends TransferProgressEvent {
  final String error;

  const TransferProgressFailed({required String id, required this.error})
    : super(id, 'failed');

  @override
  Map<String, dynamic> toJson() => super.toJson()..addAll({'error': error});
}

/// Represents a folder sync status update.
class SyncStatusEvent {
  final String localPath;
  final String remotePath;
  final int pendingChanges;
  final String status;

  SyncStatusEvent({
    required this.localPath,
    required this.remotePath,
    required this.pendingChanges,
    required this.status,
  });

  factory SyncStatusEvent.fromJson(Map<String, dynamic> json) {
    return SyncStatusEvent(
      localPath: (json['local_path'] ?? '').toString(),
      remotePath: (json['remote_path'] ?? '').toString(),
      pendingChanges: (json['pending_changes'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? 'UNKNOWN').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'local_path': localPath,
    'remote_path': remotePath,
    'pending_changes': pendingChanges,
    'status': status,
  };
}

/// Represents a folder sync batch progress update.
class SyncBatchProgressEvent {
  final int completed;
  final int total;
  final String currentFile;

  SyncBatchProgressEvent({
    required this.completed,
    required this.total,
    required this.currentFile,
  });

  factory SyncBatchProgressEvent.fromJson(Map<String, dynamic> json) {
    return SyncBatchProgressEvent(
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      currentFile: (json['current_file'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'completed': completed,
    'total': total,
    'current_file': currentFile,
  };
}

class HostMsgUnknown extends HostMessage {
  final Map<String, dynamic> raw;

  HostMsgUnknown(this.raw) : super(raw['type']?.toString() ?? 'unknown');

  @override
  Map<String, dynamic> toJson() => raw;
}

/// Base class for all commands sent to the Host.
/// Mirrors the `ClientMessage` enum in Rust.
sealed class ClientMessage {
  final String type;

  const ClientMessage(this.type);

  Map<String, dynamic> toJson() {
    return {'type': type};
  }
}

class ClientMsgAuthRequest extends ClientMessage {
  const ClientMsgAuthRequest() : super('auth_request');
}

class ClientMsgAuthResponse extends ClientMessage {
  final String response;

  const ClientMsgAuthResponse({required this.response})
    : super('auth_response');

  @override
  Map<String, dynamic> toJson() {
    return super.toJson()..addAll({'response': response});
  }
}

class ClientMsgXDcMsg extends ClientMessage {
  final String id;
  final DcMsg command;
  final Map<String, dynamic>? params;
  final String authToken;

  const ClientMsgXDcMsg({
    required this.id,
    required this.command,
    this.params,
    required this.authToken,
  }) : super('dc_msg');

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson()
      ..addAll({'id': id, 'auth_token': authToken})
      ..addAll(command.toJson());

    if (params != null) {
      json['params'] = params;
    }
    return json;
  }
}

class ClientMsgTransferInit extends ClientMessage {
  final String id;
  final String path;
  final int totalSize;
  final String? hash;
  final int resumeOffset;

  const ClientMsgTransferInit({
    required this.id,
    required this.path,
    required this.totalSize,
    this.hash,
    this.resumeOffset = 0,
  }) : super('transfer_init');

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson()
      ..addAll({
        'id': id,
        'path': path,
        'total_size': totalSize,
        'resume_offset': resumeOffset,
      });
    if (hash != null) {
      json['hash'] = hash;
    }
    return json;
  }
}

class ClientMsgTransferCancel extends ClientMessage {
  final String id;

  const ClientMsgTransferCancel({required this.id}) : super('transfer_cancel');

  @override
  Map<String, dynamic> toJson() {
    return super.toJson()..addAll({'id': id});
  }
}

class ClientMsgDownloadInit extends ClientMessage {
  final String id;
  final String path;
  final int resumeOffset;

  const ClientMsgDownloadInit({
    required this.id,
    required this.path,
    this.resumeOffset = 0,
  }) : super('download_init');

  @override
  Map<String, dynamic> toJson() {
    return super.toJson()
      ..addAll({'id': id, 'path': path, 'resume_offset': resumeOffset});
  }
}

/// Represents the `DcMsg` enum in Rust for system/file commands.
sealed class DcMsg {
  final String dcMsgType;

  const DcMsg(this.dcMsgType);

  factory DcMsg.fromJson(Map<String, dynamic> json) {
    final type = (json['dc_msg_type'] ?? '').toString();
    switch (type) {
      case 'tool_approval_response':
        return DcMsgToolApprovalResponse(
          approvalId: (json['approval_id'] ?? '').toString(),
          approved: json['approved'] == true,
        );
      case 'ping':
        return const DcMsgPing();
      case 'shutdown':
        return DcMsgShutdown(args: (json['args'] ?? '').toString());
      case 'disconnect':
        return const DcMsgDisconnect();
      case 'reboot':
        return const DcMsgReboot();
      case 'lock_screen':
        return const DcMsgLockScreen();
      case 'unlock_screen':
        return const DcMsgUnlockScreen();
      case 'update':
        return const DcMsgUpdate();
      case 'restart_host_server':
        return const DcMsgRestartHostServer();
      case 'system_log':
        return DcMsgSystemLog(
          unit: json['unit']?.toString(),
          lines: json['lines'] as int?,
          priority: json['priority']?.toString(),
          since: json['since']?.toString(),
          grep: json['grep']?.toString(),
        );
      case 'kill':
        return DcMsgKillProcess(proc: (json['proc'] ?? '').toString());
      case 'list_processes':
        return DcMsgListProcesses(
          sortBy: json['sort_by']?.toString(),
          filter: json['filter']?.toString(),
        );
      case 'ls':
        return DcMsgLs(
          path: (json['path'] ?? '').toString(),
          sortBy: json['sort_by']?.toString(),
          showHidden: json['show_hidden'] == true,
        );
      case 'mkdir':
        return DcMsgMkdir(path: (json['path'] ?? '').toString());
      case 'delete_file':
        return DcMsgDeleteFile(path: (json['path'] ?? '').toString());
      case 'list_models':
        return const DcMsgListModels();
      case 'llm_start':
        return DcMsgLlmStart(modelPath: (json['model_path'] ?? '').toString());
      case 'llm_chat':
        return DcMsgLlmChat(
          message: (json['message'] ?? '').toString(),
          systemPrompt: json['system_prompt']?.toString(),
          chatId: json['chat_id']?.toString(),
        );
      case 'llm_load_chat':
        return DcMsgLlmLoadChat(chatId: (json['chat_id'] ?? '').toString());
      case 'llm_delete_chat':
        return DcMsgLlmDeleteChat(chatId: (json['chat_id'] ?? '').toString());
      case 'llm_list_chats':
        return const DcMsgLlmListChats();
      case 'llm_stop':
        return const DcMsgLlmStop();
      case 'get_audio_devices':
        return const DcMsgGetAudioDevices();
      case 'set_device_volume':
        return DcMsgSetDeviceVolume(
          targetId: (json['target_id'] ?? '').toString(),
          volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
        );
      case 'set_default_audio_device':
        return DcMsgSetDefaultAudioDevice(
          targetId: (json['target_id'] ?? '').toString(),
        );
      case 'toggle_play_pause':
        return const DcMsgTogglePlayPause();
      case 'play_next_track':
        return const DcMsgPlayNextTrack();
      case 'play_previous_track':
        return const DcMsgPlayPreviousTrack();
      case 'set_volume':
        return DcMsgSetVolume(
          level: (json['level'] as num?)?.toDouble() ?? 0.0,
        );
      case 'get_media_status':
        return const DcMsgGetMediaStatus();
      case 'list_players':
        return const DcMsgListPlayers();
      case 'set_active_player':
        return DcMsgSetActivePlayer(
          playerName: (json['player_name'] ?? '').toString(),
        );
      case 'seek':
        return DcMsgSeek(position: (json['position'] as num?)?.toInt() ?? 0);
      case 'start_ssh':
        return const DcMsgStartSsh();
      case 'stop_ssh':
        return const DcMsgStopSsh();
      case 'get_network_status':
        return const DcMsgGetNetworkStatus();
      case 'toggle_radio':
        return DcMsgToggleRadio(
          radio: (json['radio'] ?? '').toString(),
          state: json['state'] == true,
        );
      case 'list_wifi_networks':
        return const DcMsgListWifiNetworks();
      case 'connect_wifi':
        return DcMsgConnectWifi(
          ssid: (json['ssid'] ?? '').toString(),
          password: json['password']?.toString(),
        );
      case 'list_bluetooth_devices':
        return const DcMsgListBluetoothDevices();
      case 'connect_bluetooth':
        return DcMsgConnectBluetooth(mac: (json['mac'] ?? '').toString());
      case 'sync_request':
        return DcMsgSyncRequest(path: (json['path'] ?? '').toString());
      default:
        throw FormatException("Unknown DcMsgCommand type: $type");
    }
  }

  Map<String, dynamic> toJson() {
    return {'dc_msg_type': dcMsgType};
  }
}

class DcMsgPing extends DcMsg {
  const DcMsgPing() : super('ping');
}

class DcMsgShutdown extends DcMsg {
  final String args;
  const DcMsgShutdown({required this.args}) : super('shutdown');
  @override
  Map<String, dynamic> toJson() => super.toJson()..addAll({'args': args});
}

class DcMsgDisconnect extends DcMsg {
  const DcMsgDisconnect() : super('disconnect');
}

class DcMsgReboot extends DcMsg {
  const DcMsgReboot() : super('reboot');
}

class DcMsgLockScreen extends DcMsg {
  const DcMsgLockScreen() : super('lock_screen');
}

class DcMsgUnlockScreen extends DcMsg {
  const DcMsgUnlockScreen() : super('unlock_screen');
}

class DcMsgUpdate extends DcMsg {
  const DcMsgUpdate() : super('update');
}

class DcMsgRestartHostServer extends DcMsg {
  const DcMsgRestartHostServer() : super('restart_host_server');
}

class DcMsgSystemLog extends DcMsg {
  final String? unit;
  final int? lines;
  final String? priority;
  final String? since;
  final String? grep;
  const DcMsgSystemLog({this.unit, this.lines, this.priority, this.since, this.grep})
      : super('system_log');
  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (unit != null) json['unit'] = unit;
    if (lines != null) json['lines'] = lines;
    if (priority != null) json['priority'] = priority;
    if (since != null) json['since'] = since;
    if (grep != null) json['grep'] = grep;
    return json;
  }
}

class DcMsgKillProcess extends DcMsg {
  final String proc;
  const DcMsgKillProcess({required this.proc}) : super('kill');
  @override
  Map<String, dynamic> toJson() => super.toJson()..addAll({'proc': proc});
}

class DcMsgListProcesses extends DcMsg {
  final String? sortBy;
  final String? filter;
  const DcMsgListProcesses({this.sortBy, this.filter})
    : super('list_processes');
  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (sortBy != null) json['sort_by'] = sortBy;
    if (filter != null) json['filter'] = filter;
    return json;
  }
}

class DcMsgLs extends DcMsg {
  final String path;
  final String? sortBy;
  final bool? showHidden;
  const DcMsgLs({required this.path, this.sortBy, this.showHidden})
    : super('ls');
  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson()..addAll({'path': path});
    if (sortBy != null) json['sort_by'] = sortBy;
    if (showHidden != null) json['show_hidden'] = showHidden;
    return json;
  }
}

class DcMsgMkdir extends DcMsg {
  final String path;
  const DcMsgMkdir({required this.path}) : super('mkdir');
  @override
  Map<String, dynamic> toJson() => super.toJson()..addAll({'path': path});
}

class DcMsgDeleteFile extends DcMsg {
  final String path;
  const DcMsgDeleteFile({required this.path}) : super('delete_file');
  @override
  Map<String, dynamic> toJson() => super.toJson()..addAll({'path': path});
}

class DcMsgListModels extends DcMsg {
  const DcMsgListModels() : super('list_models');
}

class DcMsgLlmStart extends DcMsg {
  final String modelPath;
  const DcMsgLlmStart({required this.modelPath}) : super('llm_start');
  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'model_path': modelPath});
}

class DcMsgLlmChat extends DcMsg {
  final String message;
  final String? systemPrompt;
  final String? chatId;
  const DcMsgLlmChat({required this.message, this.systemPrompt, this.chatId})
    : super('llm_chat');
  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson()..addAll({'message': message});
    if (systemPrompt != null) json['system_prompt'] = systemPrompt;
    if (chatId != null) json['chat_id'] = chatId;
    return json;
  }
}

class DcMsgLlmLoadChat extends DcMsg {
  final String chatId;
  const DcMsgLlmLoadChat({required this.chatId}) : super('llm_load_chat');
  @override
  Map<String, dynamic> toJson() => super.toJson()..addAll({'chat_id': chatId});
}

class DcMsgLlmDeleteChat extends DcMsg {
  final String chatId;
  const DcMsgLlmDeleteChat({required this.chatId}) : super('llm_delete_chat');
  @override
  Map<String, dynamic> toJson() => super.toJson()..addAll({'chat_id': chatId});
}

class DcMsgLlmListChats extends DcMsg {
  const DcMsgLlmListChats() : super('llm_list_chats');
}

class DcMsgLlmStop extends DcMsg {
  const DcMsgLlmStop() : super('llm_stop');
}

class DcMsgGetAudioDevices extends DcMsg {
  const DcMsgGetAudioDevices() : super('get_audio_devices');
}

class DcMsgSetDeviceVolume extends DcMsg {
  final String targetId;
  final double volume;
  const DcMsgSetDeviceVolume({required this.targetId, required this.volume})
    : super('set_device_volume');
  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'target_id': targetId, 'volume': volume});
}

class DcMsgSetDefaultAudioDevice extends DcMsg {
  final String targetId;
  const DcMsgSetDefaultAudioDevice({required this.targetId})
    : super('set_default_audio_device');
  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'target_id': targetId});
}

class DcMsgTogglePlayPause extends DcMsg {
  const DcMsgTogglePlayPause() : super('toggle_play_pause');
}

class DcMsgPlayNextTrack extends DcMsg {
  const DcMsgPlayNextTrack() : super('play_next_track');
}

class DcMsgPlayPreviousTrack extends DcMsg {
  const DcMsgPlayPreviousTrack() : super('play_previous_track');
}

class DcMsgSetVolume extends DcMsg {
  final double level;
  const DcMsgSetVolume({required this.level}) : super('set_volume');
  @override
  Map<String, dynamic> toJson() => super.toJson()..addAll({'level': level});
}

class DcMsgGetMediaStatus extends DcMsg {
  const DcMsgGetMediaStatus() : super('get_media_status');
}

class DcMsgListPlayers extends DcMsg {
  const DcMsgListPlayers() : super('list_players');
}

class DcMsgSetActivePlayer extends DcMsg {
  final String playerName;
  const DcMsgSetActivePlayer({required this.playerName})
    : super('set_active_player');
  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'player_name': playerName});
}

class DcMsgSeek extends DcMsg {
  final int position;
  const DcMsgSeek({required this.position}) : super('seek');
  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'position': position});
}

class DcMsgStartSsh extends DcMsg {
  const DcMsgStartSsh() : super('start_ssh');
}

class DcMsgStopSsh extends DcMsg {
  const DcMsgStopSsh() : super('stop_ssh');
}

class DcMsgGetNetworkStatus extends DcMsg {
  const DcMsgGetNetworkStatus() : super('get_network_status');
}

class DcMsgToggleRadio extends DcMsg {
  final String radio;
  final bool state;
  const DcMsgToggleRadio({required this.radio, required this.state})
    : super('toggle_radio');
  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll({'radio': radio, 'state': state});
}

class DcMsgListWifiNetworks extends DcMsg {
  const DcMsgListWifiNetworks() : super('list_wifi_networks');
}

class DcMsgConnectWifi extends DcMsg {
  final String ssid;
  final String? password;
  const DcMsgConnectWifi({required this.ssid, this.password})
    : super('connect_wifi');
  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson()..addAll({'ssid': ssid});
    if (password != null) json['password'] = password;
    return json;
  }
}

class DcMsgListBluetoothDevices extends DcMsg {
  const DcMsgListBluetoothDevices() : super('list_bluetooth_devices');
}

class DcMsgConnectBluetooth extends DcMsg {
  final String mac;
  const DcMsgConnectBluetooth({required this.mac}) : super('connect_bluetooth');
  @override
  Map<String, dynamic> toJson() => super.toJson()..addAll({'mac': mac});
}

class DcMsgSyncRequest extends DcMsg {
  final String path;
  const DcMsgSyncRequest({required this.path}) : super('sync_request');
  @override
  Map<String, dynamic> toJson() => super.toJson()..addAll({'path': path});
}

class DcMsgToolApprovalResponse extends DcMsg {
  final String approvalId;
  final bool approved;
  const DcMsgToolApprovalResponse({required this.approvalId, required this.approved})
    : super('tool_approval_response');
  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({
      'approval_id': approvalId,
      'approved': approved,
    });
}
