import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
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
  Future<void> initialize() async {
    await AwesomeNotifications().initialize(
      'resource://mipmap/ic_launcher',
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
      debug: true,
    );

    await AwesomeNotifications().setListeners(
      onActionReceivedMethod: onActionReceivedMethod,
    );

    await AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
      if (!isAllowed) {
        AwesomeNotifications().requestPermissionToSendNotifications();
      }
    });
  }

  /// Displays a notification mirrored from the host PC.
  ///
  /// The payload includes the original app name and notification body.
  /// Used for things like "Build Complete", "New Email", etc.
  Future<void> showNotificationFromHost(Map<String, dynamic> data) async {
    final int id = data['id'] is int
        ? data['id']
        : (DateTime.now().millisecondsSinceEpoch % 100000);

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'frankn_host_alerts',
        title: "${data['app_name']}: ${data['title']}",
        body: data['body'],
        notificationLayout: NotificationLayout.Default,
        category: NotificationCategory.Message,
        payload: {'host_id': data['id'].toString()},
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
    double progress,
  ) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'frankn_host_alerts',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.ProgressBar,
        progress: progress,
        category: NotificationCategory.Progress,
        payload: {'host_id': '0'},
        color: AppColors.neonCyan,
        backgroundColor: AppColors.panelGrey,
        locked: true,
      ),
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
        title: "DOWNLOAD COMPLETE",
        body: fileName,
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
}

/// Static handler for notification actions (taps/buttons).
///
/// Must be a top-level function or static method.
/// Handles the 'OPEN_FILE' action by launching the file at `file_path`
/// using the [OpenFilex] plugin.
@pragma("vm:entry-point")

Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {
  if (receivedAction.buttonKeyPressed == 'OPEN_FILE' ||
      (receivedAction.channelKey == 'frankn_host_alerts' &&
          receivedAction.payload?.containsKey('file_path') == true)) {
    final filePath = receivedAction.payload?['file_path'];
    if (filePath != null) {
      await OpenFilex.open(filePath);
    }
  }
}
