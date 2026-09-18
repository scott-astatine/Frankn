import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:frankn/services/capabilities/capability.dart';
import 'package:frankn/services/client_rtc/rtc.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';

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
  late final MicrophoneCapabilityController _micController;
  String? _selectedProviderId;
  String? _selectedDevicePath;
  bool _showUI = true;
  bool _showGrid = false;
  int _frameCount = 0;
  Timer? _frameTimer;

  // Colors based on Surveillance Pro v2
  final Color _bgDark = const Color(0xFF0A0A0F);
  final Color _accentMagenta = const Color(0xFFFF2D78);
  final Color _accentCyan = const Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _controller = CameraCapabilityController(capabilityId: widget.capabilityId);
    _micController = MicrophoneCapabilityController(capabilityId: 'microphone');
    
    _controller.addListener(_onControllerUpdated);
    _micController.addListener(_onControllerUpdated);
    RtcClient().capabilityInventory.addListener(_onInventoryUpdated);
    
    _selectedProviderId = widget.nodeId;
    
    _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (mounted) {
        setState(() {
          _frameCount = (_frameCount + 1) % 10000;
        });
      }
    });

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
        !cameraEntries.any((e) => e.provider.providerId == _selectedProviderId)) {
      _initCameraSession();
    } else {
      setState(() {});
    }
  }

  Future<void> _initCameraSession() async {
    final inventory = RtcClient().capabilityInventory;
    final cameraEntries = inventory.byCapability(widget.capabilityId).toList();

    if (_selectedProviderId == null ||
        !cameraEntries.any((e) => e.provider.providerId == _selectedProviderId)) {
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
      await _controller.startSession(_selectedProviderId!, devicePath: _selectedDevicePath);
      // Try to start mic as well on the same node
      try {
        await _micController.startSession(_selectedProviderId!);
      } catch (e) {
        debugPrint('Could not start microphone session (stub only): $e');
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  List<Map<String, dynamic>> _getAvailableDevices() {
    final inventory = RtcClient().capabilityInventory;
    final entry = inventory.find(widget.capabilityId, _selectedProviderId ?? '');
    if (entry != null && entry.descriptor.properties.containsKey('devices')) {
      final devicesList = entry.descriptor.properties['devices'] as List?;
      if (devicesList != null) {
        return devicesList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    return [];
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    RtcClient().capabilityInventory.removeListener(_onInventoryUpdated);
    _controller.removeListener(_onControllerUpdated);
    _micController.removeListener(_onControllerUpdated);
    _controller.dispose();
    _micController.dispose();
    super.dispose();
  }

  String _getFriendlyNodeName(String providerId, String fallback) {
    final client = RtcThinClient();
    
    // 1. Check if it's the currently connected host
    if (client.currentHostId == providerId && client.currentHostName != null) {
      return client.currentHostName!;
    }
    
    // 2. Check saved hosts
    final savedHosts = SettingsService().savedHosts;
    for (var host in savedHosts) {
      if (host['id'] == providerId) {
        return host['name'] ?? fallback;
      }
    }
    
    // 3. Check discovered hosts
    final currentHosts = client.currentHosts;
    for (var host in currentHosts) {
      if (host['host_id'] == providerId) {
        return host['display_name'] ?? fallback;
      }
    }
    
    return fallback;
  }

  void _showProviderAndDevicePicker(BuildContext context, List<CapabilityInventoryEntry> cameraEntries) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bgDark.withValues(alpha: 0.9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final devices = _getAvailableDevices();
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "SELECT NODE",
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      color: _accentMagenta,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                ...cameraEntries.map((entry) {
                  final isSelected = entry.provider.providerId == _selectedProviderId;
                  final friendlyName = _getFriendlyNodeName(entry.provider.providerId, entry.provider.displayName);
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.check_circle : Icons.dns,
                      color: isSelected ? _accentMagenta : Colors.grey,
                    ),
                    title: Text(
                      friendlyName,
                      style: TextStyle(
                        color: isSelected ? _accentMagenta : Colors.white,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    onTap: () {
                      if (!isSelected) {
                        setState(() {
                          _selectedProviderId = entry.provider.providerId;
                          _selectedDevicePath = null;
                        });
                        _initCameraSession();
                      }
                      Navigator.pop(context);
                    },
                  );
                }),
                if (devices.isNotEmpty) ...[
                  const Divider(color: Colors.white24),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "SELECT CAMERA DEVICE",
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        color: _accentCyan,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  ...devices.map((dev) {
                    final path = dev['device_path'] as String;
                    final name = dev['name'] as String;
                    final isSelected = path == _selectedDevicePath || (_selectedDevicePath == null && devices.first['device_path'] == path);
                    return ListTile(
                      leading: Icon(
                        Icons.videocam,
                        color: isSelected ? _accentCyan : Colors.grey,
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          color: isSelected ? _accentCyan : Colors.white,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                      subtitle: Text(
                        path,
                        style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'JetBrains Mono'),
                      ),
                      onTap: () {
                        if (_selectedDevicePath != path) {
                          setState(() {
                            _selectedDevicePath = path;
                          });
                          _initCameraSession();
                        }
                        Navigator.pop(context);
                      },
                    );
                  }),
                ]
              ],
            ),
          ),
        );
      },
    );
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
              descriptor: const CapabilityDescriptor(id: 'camera', name: 'Camera'),
              provider: CapabilityProvider(
                kind: ProviderKind.node,
                providerId: _selectedProviderId ?? 'unknown',
                displayName: widget.nodeName ?? 'UNKNOWN',
              ),
            ),
    );

    final devices = _getAvailableDevices();
    final currentDevice = devices.firstWhere(
      (d) => d['device_path'] == _selectedDevicePath,
      orElse: () => devices.isNotEmpty ? devices.first : {},
    );

    final resolutions = currentDevice['resolutions'] as List?;
    final resStats = currentDevice.isNotEmpty
        ? ((resolutions != null && resolutions.isNotEmpty) ? resolutions.first.toString() : '1280x720')
        : "1280x720";

    return Scaffold(
      backgroundColor: _bgDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Container with Grid
          InteractiveViewer(
            panEnabled: true,
            minScale: 1.0,
            maxScale: 5.0,
            child: GestureDetector(
              onTap: () => setState(() => _showUI = !_showUI),
              child: Container(
                color: _bgDark,
                child: _controller.isRendererInitialized && _controller.renderer.srcObject != null
                    ? RTCVideoView(
                      _controller.renderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                    )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: _accentCyan),
                        const SizedBox(height: 16),
                        Text(
                          _selectedProviderId != null
                              ? "ESTABLISHING P2P LINK... (${state.name.toUpperCase()})"
                              : "SEARCHING FOR NODE...",
                          style: TextStyle(
                            color: _accentCyan.withValues(alpha: 0.7),
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ),
            ),
          ),

          // 2. Crosshair Grid
          if (_showGrid && _showUI)
            IgnorePointer(
              child: Opacity(
                opacity: 0.15,
                child: Stack(
                  children: [
                    Positioned(
                      top: MediaQuery.of(context).size.height / 2,
                      left: 0,
                      right: 0,
                      child: Container(height: 1, color: _accentCyan),
                    ),
                    Positioned(
                      left: MediaQuery.of(context).size.width / 2,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 1, color: _accentCyan),
                    ),
                    Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(color: _accentCyan, width: 1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_showUI)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 4. Top Bar
                    Positioned(
              top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _bgDark.withValues(alpha: 0.9),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showProviderAndDevicePicker(context, cameraEntries),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _getFriendlyNodeName(currentEntry.provider.providerId, currentEntry.provider.displayName),
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_drop_down, color: _accentMagenta, size: 20),
                              ],
                            ),
                            Container(
                              height: 2,
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 4, right: 16),
                              decoration: BoxDecoration(
                                color: _accentMagenta,
                                boxShadow: [
                                  BoxShadow(
                                    color: _accentMagenta.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  )
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (currentDevice.isNotEmpty)
                          Text(
                            currentDevice['device_path'],
                            style: TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 10,
                              color: _accentCyan.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 5. Corner HUDs
          // Top Left Clock
            Positioned(
              top: 100,
            left: 16,
            child: SafeArea(
              child: _buildHudBox(
                child: Text(
                  "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}",
                  style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, color: Colors.white),
                ),
                borderColor: _accentCyan,
                borderSide: BorderSide(color: _accentCyan, width: 2),
                isLeft: true,
              ),
            ),
          ),

          // Top Right REC
          Positioned(
              top: 100,
            right: 16,
            child: SafeArea(
              child: _buildHudBox(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.8), blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "REC [ ${_frameCount.toString().padLeft(4, '0')} ]",
                      style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
                borderColor: _accentMagenta,
                borderSide: BorderSide(color: _accentMagenta, width: 2),
                isLeft: false,
              ),
            ),
          ),

          // Bottom Left Res
          Positioned(
              bottom: 90,
            left: 16,
            child: _buildHudBox(
              child: Text(
                resStats,
                style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, color: _accentCyan),
              ),
            ),
          ),

          // Bottom Right Status
          Positioned(
              bottom: 90,
            right: 16,
            child: _buildHudBox(
              child: Text(
                state == NodeSessionState.connected ? "LINK: STABLE" : "LINK: ${state.name.toUpperCase()}",
                style: TextStyle(
                  fontFamily: 'JetBrains Mono', 
                  fontSize: 12, 
                  color: state == NodeSessionState.connected ? _accentCyan : Colors.orangeAccent
                ),
              ),
            ),
          ),

          // Error Overlay
          if (error != null)
            Positioned(
              top: 130,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Text(
                  "SYS_ERR: $error",
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'JetBrains Mono'),
                ),
              ),
            ),

          // 6. Bottom Action Bar
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 70,
                padding: const EdgeInsets.only(bottom: 10, left: 20, right: 20),
                decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [_bgDark, _bgDark.withValues(alpha: 0.5), Colors.transparent],
                  stops: const [0.0, 0.6, 1.0],
                ),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildActionBtn(
                    icon: _micController.isMuted ? Icons.mic_off : Icons.mic,
                    label: _micController.isMuted ? "MUTED" : "MIC",
                    isActive: _micController.isMuted,
                    activeColor: _accentMagenta,
                    onTap: () => _micController.toggleMute(),
                  ),
                  _buildActionBtn(
                    icon: Icons.grid_4x4,
                    label: "GRID",
                    isActive: _showGrid,
                    activeColor: _accentCyan,
                    onTap: () => setState(() => _showGrid = !_showGrid),
                  ),
                  _buildActionBtn(
                    icon: Icons.radio_button_checked,
                    label: "CAPTURE",
                    isActive: false,
                    isMain: true,
                    onTap: () {
                      // TODO: Capture implementation
                    },
                  ),
                  _buildActionBtn(
                    icon: Icons.settings,
                    label: "CONFIG",
                    isActive: false,
                    onTap: () {
                      // TODO: Settings implementation
                    },
                  ),
                ],
              ),
            ),
          ),
                  ], // End of UI Overlay Stack children
                ), // End of UI Overlay Stack
              ), // End of UI Overlay ConstrainedBox
            ), // End of UI Overlay Center
        ], // Main Stack children
      ), // Main Stack
    ); // Scaffold
  }

  Widget _buildHudBox({required Widget child, Color? borderColor, BorderSide? borderSide, bool isLeft = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _bgDark.withValues(alpha: 0.6),
        border: Border(
          left: isLeft ? (borderSide ?? BorderSide(color: Colors.white.withValues(alpha: 0.3))) : BorderSide.none,
          right: !isLeft ? (borderSide ?? BorderSide(color: Colors.white.withValues(alpha: 0.3))) : BorderSide.none,
          top: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
      child: child,
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required bool isActive,
    bool isMain = false,
    Color? activeColor,
    required VoidCallback onTap,
  }) {
    final color = isActive 
        ? (activeColor ?? _accentCyan) 
        : (isMain ? Colors.white : Colors.white.withValues(alpha: 0.7));
        
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: isMain ? 32 : 24,
            shadows: isActive || isMain ? [Shadow(color: color.withValues(alpha: 0.5), blurRadius: 8)] : null,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 10,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
