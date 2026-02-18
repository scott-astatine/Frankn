import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';

class VolumeMixerDialog extends StatefulWidget {
  final RtcClient client;
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

    widget.client.commandResponseStream.listen((resp) {
      if (!mounted) return;
      final Map<String, dynamic> data;
      if (resp['type'] == 'response' && resp.containsKey('data')) {
        data = resp['data'] as Map<String, dynamic>;
      } else {
        data = resp;
      }

      if (data.containsKey('devices')) {
        setState(() {
          _devices = data['devices'];
          _isLoading = false;
        });
      }
    });
  }

  void _refresh() {
    setState(() => _isLoading = true);
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.GetAudioDevices});
  }

  void _updateVolume(String deviceId, double volume) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      widget.client.sendDcMsg({
        DcMsg.Key: DcMsg.SetDeviceVolume,
        "target_id": deviceId,
        "volume": volume,
      });
    });
  }

  void _setActiveDevice(String deviceId) {
    widget.client.sendDcMsg({
      DcMsg.Key: DcMsg.SetDefaultAudioDevice,
      "target_id": deviceId,
    });
    // Optimistic update
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
    return AlertDialog(
      backgroundColor: AppColors.voidBlack,
      shape: const BeveledRectangleBorder(
        side: BorderSide(color: AppColors.neonCyan),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "AUDIO_MATRIX",
            style: TextStyle(
              color: AppColors.neonCyan,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh,
              color: AppColors.neonCyan,
              size: 18,
            ),
            onPressed: _refresh,
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const SizedBox(
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.neonCyan),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final dev = _devices[index];
                  final bool isActive = dev['is_active'] ?? false;
                  final double currentVol = (dev['volume'] as num).toDouble();
                  final bool isOverdrive = currentVol > 1.0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => _setActiveDevice(dev['id']),
                              child: Container(
                                width: 18,
                                height: 18,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isActive
                                        ? AppColors.neonCyan
                                        : AppColors.textGrey,
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isActive
                                          ? AppColors.neonCyan
                                          : Colors.transparent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                dev['name'].toString().toUpperCase(),
                                style: TextStyle(
                                  color: isActive
                                      ? AppColors.neonCyan
                                      : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              "VOL: ${(currentVol * 100).round()}%",
                              style: TextStyle(
                                color: isOverdrive
                                    ? AppColors.neonPink
                                    : AppColors.neonCyan.withAlpha(178),
                                fontSize: 10,
                                fontFamily: 'Courier',
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: isOverdrive
                                ? AppColors.neonPink
                                : (isActive
                                      ? AppColors.neonCyan
                                      : AppColors.textGrey),
                            thumbColor: isOverdrive
                                ? AppColors.neonPink
                                : (isActive
                                      ? AppColors.neonCyan
                                      : AppColors.textGrey),
                            trackHeight: 1,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 4,
                            ),
                          ),
                          child: Slider(
                            value: currentVol.clamp(0.0, 1.5),
                            max: 1.5, // Allow up to 150%
                            onChanged: (v) {
                              setState(() => dev['volume'] = v);
                              _updateVolume(dev['id'], v);
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            "CLOSE",
            style: TextStyle(color: AppColors.neonCyan),
          ),
        ),
      ],
    );
  }
}