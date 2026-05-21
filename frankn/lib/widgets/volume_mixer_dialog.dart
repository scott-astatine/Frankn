import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/utils/cyber_card.dart';

class VolumeMixerDialog extends StatefulWidget {
  final RtcThinClient client;
  const VolumeMixerDialog({super.key, required this.client});

  @override
  State<VolumeMixerDialog> createState() => _VolumeMixerDialogState();
}

class _VolumeMixerDialogState extends State<VolumeMixerDialog> {
  List<dynamic> _devices = [];
  bool _isLoading = true;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _refresh();

    widget.client.genDcMsgStream.listen((msg) {
      if (!mounted) return;
      
      Map<String, dynamic>? data;
      if (msg is HostMsgResponse && msg.data is Map) {
          data = msg.data as Map<String, dynamic>;
      } else if (msg is HostMsgUnknown) {
          data = msg.raw;
      }

      if (data != null && data.containsKey('devices')) {
        setState(() {
          _devices = data!['devices'];
          _isLoading = false;
        });
      }
    });
  }

  void _refresh() {
    setState(() => _isLoading = true);
    widget.client.sendDcMsg(const DcMsgGetAudioDevices());
  }

  void _updateVolume(String deviceId, double volume) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      widget.client.sendDcMsg(DcMsgSetDeviceVolume(
        targetId: deviceId,
        volume: volume,
      ));
    });
  }

  void _setActiveDevice(String deviceId) {
    widget.client.sendDcMsg(DcMsgSetDefaultAudioDevice(
      targetId: deviceId,
    ));
    setState(() {
      for (var dev in _devices) {
        dev['is_active'] = (dev['id'] == deviceId);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.neonPink.withValues(alpha: 0.2),
            width: 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadiusGeometry.circular(12),

          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 8),
                  child: SizedBox(height: 1),
                ),
              ),

              // Positioned.fill(
              //   child: Container(
              //     decoration: const BoxDecoration(
              //       gradient: LinearGradient(
              //         colors: [Colors.black87, AppColors.deepSpace],
              //         begin: Alignment.bottomCenter,
              //         end: Alignment.topCenter,
              //       ),
              //     ),
              //   ),
              // ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(9.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.tune,
                                color: AppColors.neonPink,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                l10n.audioMatrix.toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.neonPink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.white38,
                              size: 20,
                            ),
                            onPressed: _refresh,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Flexible(
                      child: _isLoading
                          ? const SizedBox(
                              height: 200,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.neonPink,
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _devices.length,
                              itemBuilder: (context, index) {
                                final dev = _devices[index];
                                final bool isActive = dev['is_active'] ?? false;
                                final double currentVol = (dev['volume'] as num)
                                    .toDouble();
                                final bool isOverdrive = currentVol > 1.0;
                                final Color accentColor = isOverdrive
                                    ? AppColors.errorRed
                                    : AppColors.neonPink;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: CyberCard(
                                    bgColor: !isActive
                                        ? Colors.transparent
                                        : AppColors.deepSpace.withValues(
                                            alpha: 0.5,
                                          ),
                                    borderColor: isActive
                                        ? accentColor.withValues(alpha: 0.3)
                                        : Colors.white.withValues(alpha: 0.05),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              GestureDetector(
                                                onTap: () =>
                                                    _setActiveDevice(dev['id']),
                                                child: Container(
                                                  width: 20,
                                                  height: 20,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: isActive
                                                          ? accentColor
                                                          : Colors.white24,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: isActive
                                                      ? Center(
                                                          child: Container(
                                                            width: 10,
                                                            height: 10,
                                                            decoration:
                                                                BoxDecoration(
                                                                  color:
                                                                      accentColor,
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  dev['name']
                                                      .toString()
                                                      .toUpperCase(),
                                                  style: TextStyle(
                                                    color: isActive
                                                        ? Colors.white
                                                        : Colors.white38,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w900,
                                                    letterSpacing: 0.5,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Text(
                                                "${(currentVol * 100).round()}%",
                                                style: TextStyle(
                                                  color: accentColor,
                                                  fontSize: 11,
                                                  fontFamily:
                                                      'JetBrainsMonoNerdFont',
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          SliderTheme(
                                            data: SliderThemeData(
                                              activeTrackColor: accentColor,
                                              inactiveTrackColor: Colors.white
                                                  .withValues(alpha: 0.05),
                                              thumbColor: Colors.white,
                                              overlayColor: accentColor
                                                  .withValues(alpha: 0.1),
                                              trackHeight: 2,
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                    enabledThumbRadius: 6,
                                                  ),
                                            ),
                                            child: Slider(
                                              value: currentVol.clamp(0.0, 1.5),
                                              max: 1.5,
                                              onChanged: (v) {
                                                setState(
                                                  () => dev['volume'] = v,
                                                );
                                                _updateVolume(dev['id'], v);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          l10n.close.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
