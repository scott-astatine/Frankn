import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/utils/utils.dart';
import 'package:open_filex/open_filex.dart';

/// Manages system notifications for Frankn.
///
/// Handles initialization, display, and user interaction for:
/// - Mirrored notifications from the host PC
/// - File transfer progress indicators
/// - Download completion alerts with "Open" actions
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  /// Initializes the Awesome Notifications plugin.
  ///
  /// Sets up the notification channels, groups, and action listeners.
  /// Requests permission if not already granted.
  Future<void> initialize({bool requestPermissions = true}) async {
    await AwesomeNotifications().initialize(
      'resource://drawable/ic_notification',
      [
        NotificationChannel(
          channelGroupKey: 'frankn_channel_group',
          channelKey: 'frankn_host_alerts',
          channelName: 'Host Alerts',
          channelDescription: 'Notifications mirrored from the Frankn Host',
          defaultColor: AppColors.neonCyan,
          ledColor: Colors.white,
          importance: NotificationImportance.High,
          channelShowBadge: true,
        ),
      ],
      channelGroups: [
        NotificationChannelGroup(
          channelGroupKey: 'frankn_channel_group',
          channelGroupName: 'Frankn Group',
        ),
      ],
      debug: false,
    );

    await AwesomeNotifications().setListeners(
      onActionReceivedMethod: onActionReceivedMethod,
    );

    if (requestPermissions) {
      await AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
        if (!isAllowed) {
          AwesomeNotifications().requestPermissionToSendNotifications();
        }
      });
    }
  }

  /// Displays a notification mirrored from the host PC.
  ///
  /// The payload includes the original app name and notification body.
  /// Used for things like "Build Complete", "New Email", etc.
  Future<void> showNotificationFromHost(HostMsgNotification msg) async {
    final int id = msg.id != 0
        ? msg.id
        : (DateTime.now().millisecondsSinceEpoch % 100000);

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'frankn_host_alerts',
        title: "${msg.appName}: ${msg.title}",
        body: msg.body,
        notificationLayout: NotificationLayout.Default,
        category: NotificationCategory.Message,
        payload: {'host_id': msg.id.toString()},
        color: AppColors.neonCyan,
        backgroundColor: AppColors.panelGrey,
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'DISMISS',
          label: 'Dismiss',
          actionType: ActionType.DismissAction,
        ),
      ],
    );
  }
/// Shows or updates a progress bar notification for file transfers.
///
/// This notification is locked (non-dismissible) while progress < 100%.
Future<void> showProgressNotification(
  int id,
  String title,
  String body,
  double progress, {
  String? transferId,
}) async {
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: id,
      channelKey: 'frankn_host_alerts',
      title: title,
      body: body,
      notificationLayout: progress >= 100
          ? NotificationLayout.Default
          : NotificationLayout.ProgressBar,
      progress: progress,
      category: NotificationCategory.Progress,
      color: AppColors.neonCyan,
      backgroundColor: AppColors.panelGrey,
      locked: progress < 100,
      payload: transferId != null ? {'transfer_id': transferId} : null,
    ),
    actionButtons: progress < 100
        ? [
            NotificationActionButton(
              key: 'CANCEL_TRANSFER',
              label: 'CANCEL',
              actionType: ActionType.KeepOnTop,
              color: AppColors.errorRed,
            ),
          ]
        : [
            NotificationActionButton(
              key: 'DISMISS',
              label: 'DISMISS',
              actionType: ActionType.DismissAction,
            ),
          ],
  );
}

  /// Shows a notification when a file download completes.
  ///
  /// Includes an "OPEN" action button that triggers [onActionReceivedMethod]
  /// to open the file using the system's default handler.
  Future<void> showDownloadComplete(
    int id,
    String fileName,
    String filePath,
  ) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'frankn_host_alerts',
        title: "Download Complete",
        body: "'$fileName' downloaded successfully.",
        notificationLayout: NotificationLayout.Default,
        category: NotificationCategory.Status,
        payload: {'file_path': filePath},
        color: AppColors.matrixGreen,
        backgroundColor: AppColors.panelGrey,
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'OPEN_FILE',
          label: 'OPEN',
          actionType: ActionType.Default,
        ),
        NotificationActionButton(
          key: 'DISMISS',
          label: 'DISMISS',
          actionType: ActionType.DismissAction,
        ),
      ],
    );
  }

  /// Shows or updates a progress bar notification for a folder sync session.
  Future<void> showSyncNotification({
    required int id,
    required String folderName,
    required String folderPath,
    required int completedItems,
    required int totalItems,
    required String totalSize,
    required String currentFile,
    required double progress,
    bool isComplete = false,
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'frankn_host_alerts',
        title: isComplete ? "✅ SYNC_COMPLETE: $folderName" : "🔄 SYNCING: $folderName",
        body: isComplete
            ? "$totalItems items synced ($totalSize)"
            : "${(progress * 100).toStringAsFixed(1)}% ($completedItems/$totalItems) - $currentFile",
        notificationLayout: isComplete
            ? NotificationLayout.Default
            : NotificationLayout.ProgressBar,
        progress: progress * 100,
        summary: folderPath,
        category:
            isComplete ? NotificationCategory.Status : NotificationCategory.Progress,
        color: isComplete ? AppColors.matrixGreen : AppColors.neonCyan,
        backgroundColor: AppColors.panelGrey,
        locked: !isComplete,
      ),
      actionButtons: isComplete
          ? [
              NotificationActionButton(
                key: 'DISMISS',
                label: 'DISMISS',
                actionType: ActionType.DismissAction,
              ),
            ]
          : [
              NotificationActionButton(
                key: 'CANCEL_SYNC',
                label: 'CANCEL',
                actionType: ActionType.KeepOnTop,
                color: AppColors.errorRed,
              ),
            ],
    );
  }
}

/// Static handler for notification actions (taps/buttons).
///
/// Must be a top-level function or static method.
/// Handles the 'OPEN_FILE' action by launching the file at `file_path`
/// using the [OpenFilex] plugin.
@pragma("vm:entry-point")
Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {
  if (receivedAction.buttonKeyPressed == 'CANCEL_SYNC') {
    RtcThinClient().sendIntent(IsolateAction.stopSync);
  }

  if (receivedAction.buttonKeyPressed == 'CANCEL_TRANSFER') {
    final tid = receivedAction.payload?['transfer_id'];
    if (tid != null) {
      RtcThinClient().sendIntent(IsolateAction.cancelTransfer, {'id': tid});
    }
  }

  if (receivedAction.buttonKeyPressed == 'OPEN_FILE' ||
      (receivedAction.channelKey == 'frankn_host_alerts' &&
          receivedAction.payload?.containsKey('file_path') == true)) {
    final filePath = receivedAction.payload?['file_path'];
    if (filePath != null) {
      await OpenFilex.open(filePath);
    }
  }
}
