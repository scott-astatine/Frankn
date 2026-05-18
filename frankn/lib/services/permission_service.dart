import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Service for handling Android runtime permissions.
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// Requests all necessary permissions for Folder Sync and Notifications.
  Future<bool> requestStoragePermissions() async {
    if (!Platform.isAndroid) return true;

    // 1. Check for standard storage permissions (Required for older Android)
    final storage = await Permission.storage.request();
    
    // 2. Check for "All Files Access" (Required for Android 11+ to sync generic folders)
    // This permission is critical for Frankn to see files in /Downloads or other apps' folders.
    bool manageGranted = true;
    if (await Permission.manageExternalStorage.isDenied) {
      final res = await Permission.manageExternalStorage.request();
      manageGranted = res.isGranted;
    }

    // 3. Notification permissions (Android 13+)
    await Permission.notification.request();

    return storage.isGranted || manageGranted;
  }

  /// Checks if the app has full access to the file system.
  Future<bool> hasFullStorageAccess() async {
    if (!Platform.isAndroid) return true;
    
    final status = await Permission.manageExternalStorage.status;
    final storageStatus = await Permission.storage.status;
    
    return status.isGranted || storageStatus.isGranted;
  }
}
