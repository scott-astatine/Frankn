import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:frankn/services/capabilities/capability.dart';
import 'package:frankn/services/client_rtc/rtc.dart';

class CameraScreen extends StatefulWidget {
  final String? nodeName;
  final String? nodeId;
  final String capabilityId;

  const CameraScreen({
    super.key,
    this.nodeName,
    this.nodeId,
    this.capabilityId = 'camera',
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final CameraCapabilityController _controller;
  String? _selectedProviderId;

  @override
  void initState() {
    super.initState();
    _controller = CameraCapabilityController(capabilityId: widget.capabilityId);
    _controller.addListener(_onControllerUpdated);
    RtcClient().capabilityInventory.addListener(_onInventoryUpdated);
    _selectedProviderId = widget.nodeId;
    _initCameraSession();
  }

  void _onControllerUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onInventoryUpdated() {
    if (!mounted) return;
    final inventory = RtcClient().capabilityInventory;
    final cameraEntries = inventory.byCapability(widget.capabilityId).toList();

    if (_selectedProviderId == null ||
        !cameraEntries.any(
          (e) => e.provider.providerId == _selectedProviderId,
        )) {
      _initCameraSession();
    } else {
      setState(() {});
    }
  }

  Future<void> _initCameraSession() async {
    final inventory = RtcClient().capabilityInventory;
    final cameraEntries = inventory.byCapability(widget.capabilityId).toList();

    if (_selectedProviderId == null ||
        !cameraEntries.any(
          (e) => e.provider.providerId == _selectedProviderId,
        )) {
      final available = cameraEntries.where(
        (e) => e.availability == CapabilityAvailability.available,
      );
      if (available.isNotEmpty) {
        _selectedProviderId = available.first.provider.providerId;
      } else if (cameraEntries.isNotEmpty) {
        _selectedProviderId = cameraEntries.first.provider.providerId;
      }
    }

    if (_selectedProviderId != null) {
      await _controller.startSession(_selectedProviderId!);
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    RtcClient().capabilityInventory.removeListener(_onInventoryUpdated);
    _controller.removeListener(_onControllerUpdated);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = RtcClient().capabilityInventory;
    final cameraEntries = inventory.byCapability(widget.capabilityId).toList();
    final state = _controller.state;
    final error = _controller.error;

    final currentEntry = cameraEntries.firstWhere(
      (e) => e.provider.providerId == _selectedProviderId,
      orElse: () => cameraEntries.isNotEmpty
          ? cameraEntries.first
          : CapabilityInventoryEntry(
              descriptor: CapabilityDescriptor(id: 'camera', name: 'Camera'),
              provider: CapabilityProvider(
                kind: ProviderKind.node,
                providerId: _selectedProviderId ?? 'unknown',
                displayName: widget.nodeName ?? 'Camera Provider',
              ),
            ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "📹 ${currentEntry.provider.displayName} // CAMERA",
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            if (cameraEntries.length > 1)
              Text(
                "${cameraEntries.length} camera providers available",
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
          ],
        ),
        actions: [
          if (cameraEntries.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.flip_camera_ios_outlined,
                color: Colors.cyanAccent,
              ),
              tooltip: "Select Camera Provider",
              onSelected: (newProviderId) {
                if (_selectedProviderId != newProviderId) {
                  setState(() {
                    _selectedProviderId = newProviderId;
                  });
                  _initCameraSession();
                }
              },
              itemBuilder: (context) => cameraEntries.map((entry) {
                final isSelected =
                    entry.provider.providerId == _selectedProviderId;
                return PopupMenuItem<String>(
                  value: entry.provider.providerId,
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle : Icons.videocam,
                        color: isSelected ? Colors.cyanAccent : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${entry.provider.displayName} (${entry.availability.name})",
                        style: TextStyle(
                          color: isSelected ? Colors.cyanAccent : Colors.white,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: _initCameraSession,
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child:
                _controller.isRendererInitialized &&
                    _controller.renderer.srcObject != null
                ? RTCVideoView(
                    _controller.renderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.cyanAccent),
                      const SizedBox(height: 16),
                      Text(
                        _selectedProviderId != null
                            ? "Connecting P2P stream... (${state.name})"
                            : (cameraEntries.isEmpty
                                  ? "Searching for camera providers in inventory..."
                                  : "No camera provider selected."),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.cyanAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state == NodeSessionState.connected
                          ? Colors.greenAccent
                          : (state == NodeSessionState.failed
                                ? Colors.redAccent
                                : Colors.orangeAccent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Text(
                  "ERROR: $error",
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
