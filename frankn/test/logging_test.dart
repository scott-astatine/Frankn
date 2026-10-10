import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frankn/services/logging/diagnostic_capture_engine.dart';
import 'package:frankn/services/logging/frankn_log_frame.dart';
import 'package:frankn/services/logging/frankn_logger.dart';
import 'package:frankn/services/logging/frankn_state_snapshot.dart';
import 'package:frankn/services/logging/ipc_transport_engine.dart';
import 'package:frankn/services/logging/redaction_engine.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/rtc_thin_client.dart';

void main() {
  group('Phase 1 Logging Subsystem Contracts Test Suite', () {
    test('FranknLogFrame JSON Serialization and Correlation Hierarchy', () {
      const serializationSecret = 'direct-frame-token-secret';
      final frame = FranknLogFrame(
        timestampMs: 1788164000000,
        level: LogLevel.info,
        category: LogCategory.webrtc,
        subsystem: 'token=$serializationSecret',
        message: 'PeerConnection created successfully',
        generationId: 'G7',
        hostSessionId: 'S_8b9a',
        capabilitySessionId: 'CS_99',
        nodeId: 'node_cam_1',
        metadata: {
          'candidate_type': 'srflx',
          'port': 54321,
          'nested': {'password': serializationSecret},
        },
      );

      final json = frame.toJson();
      expect(json['ts'], 1788164000000);
      expect(json['lvl'], LogLevel.info.index);
      expect(json['cat'], LogCategory.webrtc.index);
      expect(json['sub'], 'token=[REDACTED]');
      expect(frame.toEncodedJson(), isNot(contains(serializationSecret)));
      expect(json['gen'], 'G7');
      expect(json['hsid'], 'S_8b9a');
      expect(json['csid'], 'CS_99');
      expect(json['nid'], 'node_cam_1');

      final reconstructed = FranknLogFrame.fromJson(json);
      expect(reconstructed.generationId, 'G7');
      expect(reconstructed.hostSessionId, 'S_8b9a');
      expect(reconstructed.capabilitySessionId, 'CS_99');
      expect(reconstructed.nodeId, 'node_cam_1');
    });

    test('RedactionEngine Secret Sanitization Comprehensive Coverage', () {
      final redaction = RedactionEngine();

      // Free text secret masking (Argon2 hash, tokens, passwords, PEM key)
      final rawMsg =
          'Auth attempt with argon2=\$argon2id\$v=19\$m=65536,t=3,p=4\$c29tZXNhbHQ\$hash and password="SuperSecretPassword123!" provided auth_token="abc123xyz7890000" and -----BEGIN RSA PRIVATE KEY-----\nMIIEogIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----';
      final safeMsg = redaction.sanitizeMessage(rawMsg);

      expect(safeMsg.contains('SuperSecretPassword123!'), isFalse);
      expect(safeMsg.contains('abc123xyz7890000'), isFalse);
      expect(safeMsg.contains('c29tZXNhbHQ'), isFalse);
      expect(safeMsg.contains('MIIEogIBAAKCAQEA'), isFalse);
      expect(safeMsg.contains('[REDACTED]'), isTrue);

      // Metadata map secret key masking for all mandatory sensitive keys
      final Map<String, dynamic> metadata = {
        'host_id': 'wnFjWA4u64MKKxRkfZpnhbWrghpjywc1x_5Aj__IyWo',
        'password': 'RawPasswordString',
        'auth_token': 'TokenValue12345',
        'token': 'GeneralTokenValue',
        'private_key': 'PEM_PRIVATE_KEY_DATA',
        'argon2_hash': 'HashDataString',
        'challenge_response': 'Argon2ResponseString',
        'salt': 'RandomSalt123',
        'signature': 'Ed25519SignatureData',
        'nested': {'password': 'NestedPassword', 'public_info': 'OK'},
      };

      final safeMeta = redaction.sanitizeMetadata(metadata)!;
      expect(
        safeMeta['host_id'],
        'wnFjWA4u64MKKxRkfZpnhbWrghpjywc1x_5Aj__IyWo',
      );
      expect(safeMeta['password'], '[REDACTED]');
      expect(safeMeta['auth_token'], '[REDACTED]');
      expect(safeMeta['token'], '[REDACTED]');
      expect(safeMeta['private_key'], '[REDACTED]');
      expect(safeMeta['argon2_hash'], '[REDACTED]');
      expect(safeMeta['challenge_response'], '[REDACTED]');
      expect(safeMeta['salt'], '[REDACTED]');
      expect(safeMeta['signature'], '[REDACTED]');
      expect(safeMeta['nested']['password'], '[REDACTED]');
      expect(safeMeta['nested']['public_info'], 'OK');
    });

    test('Authentication secrets are absent from every telemetry sink', () async {
      const token = 'bearer-secret-token-4e5f';
      const authToken = 'auth-secret-token-a91b';
      const response = 'opaque-proof-secret-b37d';
      const password = 'correct-horse-secret-1248';
      const privateKeyBody = 'private-key-secret-body-8891';
      const privatePem =
          '-----BEGIN PRIVATE KEY-----\n$privateKeyBody\n-----END PRIVATE KEY-----';
      const phc = r'$argon2id$v=19$m=65536,t=3,p=4$c2FsdC1zZWNyZXQ$hash-secret';
      const jsonMessage =
          '{"type":"auth_response","response":"$response","auth_token":"$authToken","nested":{"password":"$password","private_key":"$privateKeyBody","verifier":"$phc"}}';

      final logger = FranknLogger.instance;
      final originalPolicy = logger.ipcEngine.policy;
      final originalSink = logger.ipcSink;
      final ipcPayloads = <Map<String, dynamic>>[];
      final stdoutLines = <String>[];
      logger.ipcEngine.policy = IpcPolicy.trace;
      logger.ipcSink = ipcPayloads.add;
      final snapshot = FranknStateSnapshot(
        timestampMs: 1,
        label: 'CAPTURE_START',
        hostConnectionState: 'authenticated',
        signalingState: 'connected',
        hasActiveInternet: true,
        onlineHostIds: const [],
        activeCapabilitySessions: 0,
        activeSyncPairs: 0,
        systemMemoryInfo: const {
          'token': token,
          'nested': {'response': response},
        },
      );
      final capture = logger.startDiagnosticCapture(
        captureId: 'token=$token',
        startSnapshot: snapshot,
      );

      await runZoned(
        () async {
          logger.log(
            level: LogLevel.info,
            category: LogCategory.security,
            subsystem: 'private_key=$privateKeyBody',
            message: 'RAW_RX: $jsonMessage; password=$password; $phc; $privatePem',
            generationId: 'password=$password',
            metadata: {
              'token': token,
              'auth_token': authToken,
              'response': response,
              'nested': [
                {'password': password, 'private_key': privateKeyBody},
              ],
            },
          );
        },
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => stdoutLines.add(line),
        ),
      );

      logger.stopDiagnosticCapture(snapshot);
      final thinClient = RtcThinClient();
      thinClient.handleMsg(
        IsolateMsg(
          type: IsolateType.event,
          action: IsolateAction.logEvent,
          payload: {'msg': jsonMessage},
        ),
      );
      final ringJson = logger.getRingBufferSnapshot().last.toEncodedJson();
      final ipcJson = ipcPayloads.last.toString();
      final captureJson = capture.toJson().toString();
      final export = capture.generateMarkdownReport(
        clientVersion: 'token=$token',
        osInfo: 'response=$response',
      );
      final allSinks = [
        stdoutLines.join('\n'),
        ringJson,
        ipcJson,
        captureJson,
        export,
        thinClient.logHistory.last,
      ].join('\n');

      for (final secret in [
        token,
        authToken,
        response,
        password,
        privateKeyBody,
        privatePem,
        phc,
        'salt-secret',
        'hash-secret',
      ]) {
        expect(allSinks, isNot(contains(secret)), reason: 'Leaked $secret');
      }

      logger.ipcSink = originalSink;
      logger.ipcEngine.policy = originalPolicy;
      logger.unsubscribeUiLogs();
    });

    test('IpcTransportEngine Dual Bucket Token & Suppression Counter', () {
      final ipc = IpcTransportEngine(
        policy: IpcPolicy.live,
        subscriptionConfig: const IpcSubscriptionConfig(
          isUiSubscribed: true,
          subscribedCategories: {LogCategory.webrtc, LogCategory.signaling},
          minSubscribedLevel: LogLevel.debug,
        ),
        maxHighPriorityTokensPerSec: 10,
        maxLowPriorityTokensPerSec: 2,
      );

      final debugFrame = FranknLogFrame(
        timestampMs: 1000,
        level: LogLevel.debug,
        category: LogCategory.webrtc,
        subsystem: 'ICE',
        message: 'Debug candidate payload',
      );

      // Consume low priority tokens
      expect(ipc.preparePayload(debugFrame), isNotNull);
      expect(ipc.preparePayload(debugFrame), isNotNull);

      // Low priority token bucket exhausted -> should suppress
      expect(ipc.preparePayload(debugFrame), isNull);
      expect(ipc.suppressedFrameCount, 1);

      // High priority frame should still be dispatched
      final errorFrame = FranknLogFrame(
        timestampMs: 1001,
        level: LogLevel.error,
        category: LogCategory.webrtc,
        subsystem: 'ICE',
        message: 'High priority failure',
      );

      final payload = ipc.preparePayload(errorFrame);
      expect(payload, isNotNull);
      expect(
        payload!['suppressed_count'],
        1,
      ); // Suppression count attached and reset
      expect(ipc.suppressedFrameCount, 0);
    });

    test(
      'DiagnosticCaptureSession Start/End Snapshot and Frames Bounded Session',
      () {
        final startSnap = FranknStateSnapshot(
          timestampMs: 1000,
          label: 'CAPTURE_START',
          hostConnectionState: 'authenticated',
          signalingState: 'connected',
          hasActiveInternet: true,
          onlineHostIds: ['host_1'],
          activeCapabilitySessions: 1,
          activeSyncPairs: 1,
          systemMemoryInfo: {'free_mb': 512},
        );

        final endSnap = FranknStateSnapshot(
          timestampMs: 2000,
          label: 'CAPTURE_END',
          hostConnectionState: 'authenticated',
          signalingState: 'connected',
          hasActiveInternet: true,
          onlineHostIds: ['host_1'],
          activeCapabilitySessions: 1,
          activeSyncPairs: 1,
          systemMemoryInfo: {'free_mb': 500},
        );

        final session = DiagnosticCaptureSession(
          captureId: 'CAP_100',
          maxFrameLimit: 2,
        );
        session.start(startSnap);
        expect(session.isActive, isTrue);

        session.captureFrame(
          FranknLogFrame(
            timestampMs: 1100,
            level: LogLevel.info,
            category: LogCategory.signaling,
            subsystem: 'WS',
            message: 'Msg 1',
          ),
        );
        session.captureFrame(
          FranknLogFrame(
            timestampMs: 1200,
            level: LogLevel.info,
            category: LogCategory.signaling,
            subsystem: 'WS',
            message: 'Msg 2',
          ),
        );
        // Overflow frame beyond maxFrameLimit = 2
        session.captureFrame(
          FranknLogFrame(
            timestampMs: 1300,
            level: LogLevel.info,
            category: LogCategory.signaling,
            subsystem: 'WS',
            message: 'Msg 3 Overflow',
          ),
        );

        session.stop(endSnap);
        expect(session.isActive, isFalse);
        expect(session.capturedFrames.length, 2);

        final report = session.generateMarkdownReport(
          clientVersion: '1.2.0',
          osInfo: 'Linux x86_64',
        );
        expect(report.contains('CAP_100'), isTrue);
        expect(report.contains('CAPTURE_START'), isTrue);
        expect(report.contains('CAPTURE_END'), isTrue);
      },
    );

    test('FranknLogger Subscription Lifecycle Invariant', () {
      final logger = FranknLogger.instance;

      // Logger ring buffer captures events
      logger.log(
        level: LogLevel.info,
        category: LogCategory.system,
        subsystem: 'BOOT',
        message: 'System booting',
      );

      expect(logger.getRingBufferSnapshot().isNotEmpty, isTrue);

      // UI Subscribes IPC
      logger.subscribeUiLogs(
        categories: {LogCategory.system},
        minLevel: LogLevel.info,
      );
      expect(logger.ipcEngine.subscriptionConfig.isUiSubscribed, isTrue);

      // UI Unsubscribes IPC when screen closes
      logger.unsubscribeUiLogs();
      expect(logger.ipcEngine.subscriptionConfig.isUiSubscribed, isFalse);
      // Ring buffer retains history regardless of UI unsubscription!
      expect(logger.getRingBufferSnapshot().isNotEmpty, isTrue);
    });
  });
}
