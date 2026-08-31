import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Helper service for validating network interface state and actual internet connectivity.
class NetworkHealthService {
  /// Checks whether an active network interface is present AND DNS/socket lookup succeeds.
  static Future<bool> hasActiveInternet() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      if (connectivityResults.contains(ConnectivityResult.none) ||
          connectivityResults.isEmpty) {
        return false;
      }
    } catch (_) {
      // If connectivity check fails, proceed to DNS socket check
    }

    try {
      final lookup = await InternetAddress.lookup('1.1.1.1')
          .timeout(const Duration(seconds: 2));
      if (lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    try {
      final fallback = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 2));
      return fallback.isNotEmpty && fallback[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
