import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/screens/syslog_screen.dart';
import 'package:frankn/screens/file_browser_screen.dart';
import 'package:frankn/screens/process_manager_screen.dart';
import 'package:frankn/widgets/volume_mixer_dialog.dart';
import 'package:frankn/screens/ssh_screen.dart';

class QuickFunction extends StatefulWidget {
  final RtcClient client;
  const QuickFunction({super.key, required this.client});

  @override
  State<QuickFunction> createState() => _QuickFunctionState();
}

class _QuickFunctionState extends State<QuickFunction> {
  String _mediaStatus = "Paused";
  String _mediaMetadata = "No Media";
  String _currentPlayer = "";
  List<String> _availablePlayers = [];
  double _mediaPosition = 0.0;
  double _mediaLength = 1.0;
  String? _artData;
  Timer? _progressTimer;

  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    _initMediaSync();
  }

  void _triggerInitialSync() {
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.GetMediaStatus});
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.ListPlayers});
  }

  void _initMediaSync() {
    // If already authenticated, fetch initial state
    if (widget.client.currentHostState == HostConnectionState.authenticated) {
      _triggerInitialSync();
    }

    // Also listen for state changes to trigger sync when auth arrives
    widget.client.hostStateStream.listen((state) {
      if (mounted && state == HostConnectionState.authenticated) {
        _triggerInitialSync();
      }
    });

    widget.client.mediaStatusStream.listen((status) {
      if (mounted) setState(() => _mediaStatus = status);
    });

    widget.client.commandResponseStream.listen((resp) {
      if (!mounted) return;
      
      Map<String, dynamic> data = {};
      try {
        if (resp['type'] == 'response') {
          if (resp.containsKey('data') && resp['data'] is Map<String, dynamic>) {
            data = resp['data'] as Map<String, dynamic>;
          }
        } else {
          data = Map<String, dynamic>.from(resp);
        }
      } catch (e) {
        debugPrint("UI ERROR: Failed to parse media response: $e");
        return;
      }

      setState(() {
        if (data.containsKey('players')) {
          _availablePlayers = List<String>.from(data['players']);
          if (data.containsKey('active_player')) {
            _currentPlayer = data['active_player'] ?? "";
          }
        }
        if (data.containsKey('player_name')) {
          final newPlayer = data['player_name'].toString();
          if (newPlayer != _currentPlayer) {
            _currentPlayer = newPlayer;
            _mediaPosition = 0;
          }
        }
        if (data.containsKey('metadata')) {
          _mediaMetadata = data['metadata']?.toString().trim() ?? "No Media";
          if (_mediaMetadata.isEmpty) _mediaMetadata = "No Media";
        }
        if (data.containsKey('art_data')) {
          _artData = data['art_data'];
        }
        if (data['position'] != null) {
          _mediaPosition = (data['position'] as num).toDouble();
          if (!_isDragging) _dragValue = _mediaPosition;
        }
        if (data['length'] != null) {
          _mediaLength = (data['length'] as num).toDouble();
          if (_mediaLength <= 0) _mediaLength = 1.0;
        }
      });
    });

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted &&
          _mediaStatus.toLowerCase().contains("playing") &&
          !_isDragging) {
        setState(() {
          _mediaPosition += 1000000;
          if (_mediaPosition > _mediaLength) _mediaPosition = _mediaLength;
          _dragValue = _mediaPosition;
        });
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(double microseconds) {
    if (microseconds <= 0) return "00:00";
    final d = Duration(microseconds: microseconds.toInt());
    return "${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isWide = constraints.maxWidth > 800;
      final int crossAxisCount =
          isWide ? 4 : (constraints.maxWidth > 500 ? 3 : 2);

      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader("NEURAL DECK"),
            const SizedBox(height: 12),
            _buildMediaCard(isWide),
            const SizedBox(height: 32),
            _buildSectionHeader("SYSTEM OPERATIONS"),
            const SizedBox(height: 12),
            _buildOpsGrid(crossAxisCount, isWide),
            const SizedBox(height: 32),
            _buildSectionHeader("POWER MANAGEMENT"),
            const SizedBox(height: 12),
            _buildPowerGrid(crossAxisCount, isWide),
          ],
        ),
      );
    });
  }

  Widget _buildOpsGrid(int count, bool isWide) {
    return GridView.count(
      crossAxisCount: count,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: isWide ? 3.0 : 2.5,
      children: [
        _buildGridBtn("FILE BROWSER", Icons.folder_open, AppColors.cyberYellow,
            () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => FileBrowserScreen(client: widget.client)));
        }),
        _buildGridBtn("TERMINAL", Icons.code, AppColors.neonCyan, () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => SShScreen(client: widget.client)));
        }),
        _buildGridBtn("SYS_LOG", Icons.terminal, AppColors.matrixGreen, () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => SyslogScreen(client: widget.client)));
        }),
        _buildGridBtn("PROCESSES", Icons.memory, AppColors.errorRed, () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      ProcessManagerScreen(client: widget.client)));
        }),
        _buildGridBtn(
            "UPDATE",
            Icons.system_update,
            AppColors.cyberYellow,
            () => widget.client
                .sendDcMsg({DcMsg.Key: DcMsg.Update})),
        _buildGridBtn(
            "RESTART_SVC",
            Icons.refresh,
            AppColors.cyberYellow,
            () => widget.client
                .sendDcMsg({DcMsg.Key: DcMsg.RestartHostServer})),
      ],
    );
  }

  Widget _buildPowerGrid(int count, bool isWide) {
    return GridView.count(
      crossAxisCount: count,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: isWide ? 3.0 : 2.5,
      children: [
        _buildGridBtn(
            "LOCK",
            Icons.lock,
            AppColors.neonCyan,
            () => widget.client
                .sendDcMsg({DcMsg.Key: DcMsg.LockScreen})),
        _buildGridBtn(
            "UNLOCK",
            Icons.lock_open,
            AppColors.neonCyan,
            () => widget.client
                .sendDcMsg({DcMsg.Key: DcMsg.UnlockScreen})),
        _buildGridBtn(
            "REBOOT",
            Icons.restart_alt,
            AppColors.cyberYellow,
            () => _confirmAction(
                "REBOOT HOST?", "Restart remote system?", DcMsg.Reboot)),
        _buildGridBtn(
            "SHUTDOWN",
            Icons.power_settings_new,
            AppColors.errorRed,
            () => _confirmAction("SHUTDOWN HOST?", "Power off remote system?",
                DcMsg.Shutdown)),
      ],
    );
  }

  Widget _buildMediaCard(bool isWide) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.borderRadius),
      child: CyberCard(
        child: Stack(
          children: [
            Positioned.fill(child: _buildMediaBackground()),
            Positioned.fill(child: _buildGlassOverlay()),
            Padding(
              padding: EdgeInsets.all(isWide ? 24 : 16),
              child: Column(
                children: [
                  _buildMediaHeader(isWide),
                  const SizedBox(height: 20),
                  _buildProgressSection(),
                  const SizedBox(height: 12),
                  _buildMediaControls(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaHeader(bool isWide) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildAlbumArt(size: isWide ? 120 : 80),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _mediaMetadata,
                      style: TextStyle(
                          color: AppColors.neonCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: isWide ? 18 : 14,
                          letterSpacing: 1,
                          overflow: TextOverflow.ellipsis,
                          shadows: [
                            Shadow(
                                color: AppColors.neonCyan.withAlpha(128),
                                blurRadius: 10)
                          ]),
                      maxLines: 2,
                    ),
                  ),
                  _buildPlayerPicker(),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _currentPlayer
                    .replaceAll("org.mpris.MediaPlayer2.", "")
                    .toUpperCase(),
                style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerPicker() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.devices, color: AppColors.neonCyan, size: 20),
      color: AppColors.panelGrey,
      tooltip: "Players",
      onSelected: (player) {
        widget.client.sendDcMsg(
            {DcMsg.Key: DcMsg.SetActivePlayer, "player_name": player});
        widget.client.sendDcMsg({DcMsg.Key: DcMsg.ListPlayers});
      },
      itemBuilder: (context) => _availablePlayers
          .map((p) => PopupMenuItem(
                value: p,
                child: Text(
                  p.replaceAll("org.mpris.MediaPlayer2.", "").toUpperCase(),
                  style: TextStyle(
                      color: p == _currentPlayer
                          ? AppColors.neonCyan
                          : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildGlassOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withAlpha(204),
            Colors.black.withAlpha(102),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaBackground() {
    if (_artData == null) return Container(color: Colors.black);
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: Opacity(
        opacity: 0.5,
        child: _buildArtImage(fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildAlbumArt({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.voidBlack,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: AppColors.neonPink.withAlpha(102), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: AppColors.neonPink.withAlpha(51),
              blurRadius: 12,
              spreadRadius: 1)
        ],
      ),
      child: _artData != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(2), child: _buildArtImage())
          : const Icon(Icons.music_note, color: AppColors.neonPink, size: 32),
    );
  }

  Widget _buildArtImage({BoxFit fit = BoxFit.cover}) {
    if (_artData == null || _artData!.isEmpty) {
      return const Icon(Icons.music_note);
    }

    if (_artData!.startsWith('http')) {
      return Image.network(_artData!, fit: fit);
    }

    if (_artData!.startsWith('file://')) {
      return const Icon(Icons.music_note, color: AppColors.neonPink);
    }

    try {
      return Image.memory(base64Decode(_artData!), fit: fit);
    } catch (e) {
      return const Icon(Icons.music_note, color: AppColors.errorRed);
    }
  }

  Widget _buildProgressSection() {
    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.neonPink,
            inactiveTrackColor: AppColors.neonPink.withAlpha(25),
            thumbColor: Colors.white,
            trackHeight: 1.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            overlayColor: AppColors.neonPink.withAlpha(51),
          ),
          child: Slider(
            value: _dragValue.clamp(0.0, _mediaLength),
            max: _mediaLength,
            onChangeStart: (v) => setState(() => _isDragging = true),
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              setState(() {
                _isDragging = false;
                _mediaPosition = v;
              });
              widget.client.sendDcMsg(
                  {DcMsg.Key: DcMsg.Seek, "position": v.toInt()});
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_dragValue),
                  style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
              Text(_formatDuration(_mediaLength),
                  style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMediaControls() {
    final send = widget.client.sendDcMsg;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
            icon:
                const Icon(Icons.replay_10, color: AppColors.neonCyan, size: 22),
            onPressed: () {
              double newPos = _mediaPosition - 10000000;
              if (newPos < 0) newPos = 0;
              send({DcMsg.Key: DcMsg.Seek, "position": newPos.toInt()});
            }),
        IconButton(
            icon: const Icon(Icons.skip_previous,
                color: AppColors.neonPink, size: 28),
            onPressed: () => send({DcMsg.Key: DcMsg.PlayPreviousTrack})),
        _buildPlayPauseBtn(),
        IconButton(
            icon:
                const Icon(Icons.skip_next, color: AppColors.neonPink, size: 28),
            onPressed: () => send({DcMsg.Key: DcMsg.PlayNextTrack})),
        IconButton(
            icon: const Icon(Icons.forward_10,
                color: AppColors.neonCyan, size: 22),
            onPressed: () {
              double newPos = _mediaPosition + 10000000;
              if (newPos > _mediaLength) newPos = _mediaLength;
              send({DcMsg.Key: DcMsg.Seek, "position": newPos.toInt()});
            }),
        IconButton(
            icon: const Icon(Icons.tune, color: AppColors.neonCyan, size: 22),
            onPressed: () => _showVolumeMixer(context)),
      ],
    );
  }

  Widget _buildPlayPauseBtn() {
    bool isPlaying = _mediaStatus.toLowerCase().contains("playing");
    return Container(
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.neonPink, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: AppColors.neonPink.withAlpha(76),
                blurRadius: 10)
          ]),
      child: IconButton(
        iconSize: 36,
        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
            color: AppColors.neonPink),
        onPressed: () =>
            widget.client.sendDcMsg({DcMsg.Key: DcMsg.TogglePlayPause}),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: AppColors.neonCyan.withAlpha(128),
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
        fontSize: 9,
      ),
    );
  }

  Widget _buildGridBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        splashColor: color.withAlpha(51),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: color.withAlpha(102)),
            borderRadius: BorderRadius.circular(4),
            color: color.withAlpha(5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmAction(String title, String body, String dcType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelGrey,
        shape: const BeveledRectangleBorder(
            side: BorderSide(color: AppColors.errorRed, width: 1)),
        title: Text(title,
            style: const TextStyle(
                color: AppColors.errorRed,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2)),
        content:
            Text(body, style: const TextStyle(color: Colors.white, fontSize: 12)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL",
                  style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorRed, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              widget.client.sendDcMsg({DcMsg.Key: dcType, "args": ""});
            },
            child: const Text("CONFIRM"),
          ),
        ],
      ),
    );
  }

  void _showVolumeMixer(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => VolumeMixerDialog(client: widget.client),
    );
  }
}
