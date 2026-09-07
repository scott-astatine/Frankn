import 'package:frankn/services/logging/frankn_log_frame.dart';

/// Configurable IPC policies controlling output from background to UI isolate.
enum IpcPolicy {
  off, // Zero IPC output to UI isolate
  errorsOnly, // Only LogLevel.error and LogLevel.fatal
  errorsWarnings, // LogLevel.warn, error, and fatal
  live, // Stream matching UI subscription filters
  trace, // Unfiltered raw IPC stream
}

/// Abstract contract for IPC transport bridge.
abstract class IpcTransportContract {
  bool shouldDispatch(FranknLogFrame frame);
  Map<String, dynamic>? preparePayload(FranknLogFrame frame);
  void resetSuppressionCounter();
  int get suppressedFrameCount;
}

/// Subscription state data holder for UI isolate subscription requests.
class IpcSubscriptionConfig {
  final bool isUiSubscribed;
  final Set<LogCategory> subscribedCategories;
  final LogLevel minSubscribedLevel;
  final String? generationFilter;

  const IpcSubscriptionConfig({
    this.isUiSubscribed = false,
    this.subscribedCategories = const {},
    this.minSubscribedLevel = LogLevel.debug,
    this.generationFilter,
  });
}

/// Priority-aware, rate-limited IPC transport engine.
/// Protects UI event loop by enforcing priority-tiered token bucket rate limits.
/// Prefers preserving WARN/ERROR/FATAL frames while coalescing DEBUG/TRACE frames under load.
class IpcTransportEngine implements IpcTransportContract {
  IpcPolicy policy;
  IpcSubscriptionConfig subscriptionConfig;

  // Configurable Rate Limit Parameters
  final int maxHighPriorityTokensPerSec;
  final int maxLowPriorityTokensPerSec;

  // Rate Limiting Bucket States
  int _highPriorityTokens;
  int _lowPriorityTokens;
  DateTime _lastRefill;

  // Suppression Counter
  int _suppressedFrameCount = 0;

  IpcTransportEngine({
    this.policy = IpcPolicy.off,
    this.subscriptionConfig = const IpcSubscriptionConfig(),
    this.maxHighPriorityTokensPerSec = 100,
    this.maxLowPriorityTokensPerSec = 20,
  })  : _highPriorityTokens = maxHighPriorityTokensPerSec,
        _lowPriorityTokens = maxLowPriorityTokensPerSec,
        _lastRefill = DateTime.now();

  @override
  int get suppressedFrameCount => _suppressedFrameCount;

  @override
  void resetSuppressionCounter() {
    _suppressedFrameCount = 0;
  }

  @override
  bool shouldDispatch(FranknLogFrame frame) {
    switch (policy) {
      case IpcPolicy.off:
        return false;
      case IpcPolicy.errorsOnly:
        return frame.level.value >= LogLevel.error.value;
      case IpcPolicy.errorsWarnings:
        return frame.level.value >= LogLevel.warn.value;
      case IpcPolicy.live:
        if (!subscriptionConfig.isUiSubscribed) return false;
        if (!subscriptionConfig.subscribedCategories.contains(frame.category)) {
          return false;
        }
        if (frame.level.value < subscriptionConfig.minSubscribedLevel.value) {
          return false;
        }
        if (subscriptionConfig.generationFilter != null &&
            subscriptionConfig.generationFilter!.isNotEmpty &&
            frame.generationId != subscriptionConfig.generationFilter) {
          return false;
        }
        return true;
      case IpcPolicy.trace:
        return true;
    }
  }

  @override
  Map<String, dynamic>? preparePayload(FranknLogFrame frame) {
    _refillTokensIfNeeded();

    final isHighPriority = frame.level.value >= LogLevel.warn.value;

    if (isHighPriority) {
      if (_highPriorityTokens > 0) {
        _highPriorityTokens--;
        return _buildPayload(frame);
      }
    } else {
      if (_lowPriorityTokens > 0) {
        _lowPriorityTokens--;
        return _buildPayload(frame);
      } else {
        // Low priority token bucket exhausted: Suppress & Increment counter
        _suppressedFrameCount++;
        return null;
      }
    }

    // High priority tokens exhausted (extreme error cascade): Suppress & Increment
    _suppressedFrameCount++;
    return null;
  }

  Map<String, dynamic> _buildPayload(FranknLogFrame frame) {
    final payload = frame.toJson();
    if (_suppressedFrameCount > 0) {
      payload['suppressed_count'] = _suppressedFrameCount;
      _suppressedFrameCount = 0; // Reset after attaching to payload
    }
    return payload;
  }

  void _refillTokensIfNeeded() {
    final now = DateTime.now();
    if (now.difference(_lastRefill).inMilliseconds >= 1000) {
      _highPriorityTokens = maxHighPriorityTokensPerSec;
      _lowPriorityTokens = maxLowPriorityTokensPerSec;
      _lastRefill = now;
    }
  }
}
