import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/services/logging/frankn_log_frame.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/cyber_alert_dialog.dart';

class LogTerminalScreen extends StatefulWidget {
  final RtcThinClient client;
  const LogTerminalScreen({super.key, required this.client});

  @override
  State<LogTerminalScreen> createState() => _LogTerminalScreenState();
}

class _LogTerminalScreenState extends State<LogTerminalScreen> {
  final List<FranknLogFrame> _frames = [];
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<FranknLogFrame>? _frameSub;
  StreamSubscription<List<FranknLogFrame>>? _batchSub;
  StreamSubscription<Map<String, dynamic>>? _reportSub;

  LogCategory? _selectedCategory;
  LogLevel _minLevel = LogLevel.debug;
  String? _generationFilter;
  bool _isPaused = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();

    // 1. Subscribe UI Isolate to background logger
    widget.client.subscribeLogs(
      categories: _selectedCategory != null ? {_selectedCategory!} : null,
      minLevel: _minLevel,
      generationFilter: _generationFilter,
    );

    // 2. Listen for history snapshot batch
    _batchSub = widget.client.logBatchStream.listen((batch) {
      if (mounted && !_isPaused) {
        setState(() {
          _frames.clear();
          _frames.addAll(batch.reversed);
        });
      }
    });

    // 3. Listen for live incoming log frames
    _frameSub = widget.client.logFrameStream.listen((frame) {
      if (mounted && !_isPaused) {
        setState(() {
          _frames.insert(0, frame);
          if (_frames.length > 3000) _frames.removeLast();
        });
      }
    });

    // 4. Listen for diagnostic report export
    _reportSub = widget.client.diagnosticReportStream.listen((data) {
      if (mounted) {
        final report = data['report'] as String?;
        if (report != null) {
          setState(() {
            _isCapturing = false;
          });
          _showDiagnosticReportModal(report);
        }
      }
    });
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _batchSub?.cancel();
    _reportSub?.cancel();
    _searchController.dispose();

    // Unsubscribe UI IPC listener when log screen closes
    // Background logger storage policy & stdout remain 100% UNTOUCHED
    widget.client.unsubscribeLogs();
    super.dispose();
  }

  void _reSubscribe() {
    widget.client.subscribeLogs(
      categories: _selectedCategory != null ? {_selectedCategory!} : null,
      minLevel: _minLevel,
      generationFilter: _generationFilter,
    );
  }

  List<FranknLogFrame> get _filteredFrames {
    final query = _searchController.text.trim().toLowerCase();
    return _frames.where((f) {
      if (f.level.value < _minLevel.value) return false;
      if (_selectedCategory != null && f.category != _selectedCategory) {
        return false;
      }
      if (_generationFilter != null &&
          _generationFilter!.isNotEmpty &&
          f.generationId != _generationFilter) {
        return false;
      }
      if (query.isNotEmpty) {
        final msgMatch = f.message.toLowerCase().contains(query);
        final subMatch = f.subsystem.toLowerCase().contains(query);
        final genMatch = f.generationId?.toLowerCase().contains(query) ?? false;
        if (!msgMatch && !subMatch && !genMatch) return false;
      }
      return true;
    }).toList();
  }

  void _showPayloadModal(FranknLogFrame frame) {
    if (frame.metadata == null || frame.metadata!.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final jsonStr = const JsonEncoder.withIndent('  ').convert(frame.metadata);
        return Container(
          padding: const EdgeInsets.all(20),
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "FRAME PAYLOAD METADATA // [${frame.subsystem}]",
                    style: const TextStyle(
                      color: AppColors.accentSecondary,
                      fontFamily: 'JetBrainsMonoNerdFont',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    jsonStr,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMonoNerdFont',
                      color: AppColors.accentSuccess,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceSecondary,
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text("COPY JSON PAYLOAD"),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: jsonStr));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Payload copied to clipboard")),
                    );
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDiagnosticReportModal(String report) {
    showDialog(
      context: context,
      builder: (context) => CyberAlertDialog(
        title: "DIAGNOSTIC CAPTURE BUNDLE",
        content: SizedBox(
          width: double.maxFinite,
          height: 350,
          child: SingleChildScrollView(
            child: SelectableText(
              report,
              style: const TextStyle(
                fontFamily: 'JetBrainsMonoNerdFont',
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 14),
            label: const Text("COPY BUNDLE"),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Diagnostic bundle copied to clipboard")),
              );
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final activeGen = widget.client.currentHostState == HostConnectionState.authenticated
        ? "G1"
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        title: Text(
          l10n.liveLog,
          style: const TextStyle(
            fontFamily: 'JetBrainsMonoNerdFont',
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: _isPaused ? Colors.amberAccent : Colors.white70,
            ),
            tooltip: _isPaused ? "Resume Stream" : "Pause Stream",
            onPressed: () => setState(() => _isPaused = !_isPaused),
          ),
          IconButton(
            icon: Icon(
              _isCapturing ? Icons.stop_circle : Icons.fiber_manual_record,
              color: _isCapturing ? Colors.redAccent : Colors.white54,
            ),
            tooltip: _isCapturing ? "Stop Diagnostic Capture" : "Start Capture",
            onPressed: () {
              if (_isCapturing) {
                widget.client.stopDiagnosticCapture();
              } else {
                setState(() => _isCapturing = true);
                widget.client.startDiagnosticCapture();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Diagnostic Capture Started")),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white54),
            tooltip: "Clear View",
            onPressed: () => setState(() => _frames.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Control Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF141414),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: "Search logs or subsystem tag...",
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1F1F1F),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 16),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<LogLevel>(
                      value: _minLevel,
                      dropdownColor: const Color(0xFF1F1F1F),
                      style: const TextStyle(color: AppColors.accentSecondary, fontSize: 11),
                      underline: const SizedBox(),
                      items: LogLevel.values.map((lvl) {
                        return DropdownMenuItem(
                          value: lvl,
                          child: Text(lvl.name.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _minLevel = val);
                          _reSubscribe();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Category Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text("ALL"),
                        selected: _selectedCategory == null,
                        selectedColor: AppColors.accentSecondary.withValues(alpha: 0.3),
                        onSelected: (_) {
                          setState(() => _selectedCategory = null);
                          _reSubscribe();
                        },
                      ),
                      const SizedBox(width: 6),
                      ...LogCategory.values.map((cat) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(cat.code),
                            selected: _selectedCategory == cat,
                            selectedColor: AppColors.accentSecondary.withValues(alpha: 0.3),
                            onSelected: (selected) {
                              setState(() {
                                _selectedCategory = selected ? cat : null;
                              });
                              _reSubscribe();
                            },
                          ),
                        );
                      }),
                      if (activeGen != null) ...[
                        const SizedBox(width: 6),
                        ActionChip(
                          avatar: const Icon(Icons.link, size: 12, color: Colors.cyanAccent),
                          label: Text("Follow ($activeGen)"),
                          onPressed: () {
                            setState(() => _generationFilter = activeGen);
                            _reSubscribe();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isCapturing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              color: Colors.red.withValues(alpha: 0.2),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: Colors.redAccent, size: 10),
                  SizedBox(width: 8),
                  Text(
                    "DIAGNOSTIC CAPTURE ACTIVE (Recording snapshots & telemetry)",
                    style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _filteredFrames.length,
              itemBuilder: (context, index) {
                final frame = _filteredFrames[index];
                final timeStr = DateTime.fromMillisecondsSinceEpoch(frame.timestampMs)
                    .toIso8601String()
                    .substring(11, 19);

                Color lvlColor = AppColors.accentSuccess;
                if (frame.level == LogLevel.warn) lvlColor = Colors.amberAccent;
                if (frame.level == LogLevel.error || frame.level == LogLevel.fatal) {
                  lvlColor = Colors.redAccent;
                }

                final hasMeta = frame.metadata != null && frame.metadata!.isNotEmpty;

                return InkWell(
                  onTap: hasMeta ? () => _showPayloadModal(frame) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "[$timeStr]",
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMonoNerdFont',
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "[${frame.category.code}]",
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMonoNerdFont',
                            color: AppColors.accentSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "[${frame.subsystem}]",
                          style: TextStyle(
                            fontFamily: 'JetBrainsMonoNerdFont',
                            color: lvlColor,
                            fontSize: 11,
                          ),
                        ),
                        if (frame.generationId != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            "[${frame.generationId}]",
                            style: const TextStyle(
                              fontFamily: 'JetBrainsMonoNerdFont',
                              color: Colors.cyan,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            frame.message,
                            style: TextStyle(
                              fontFamily: 'JetBrainsMonoNerdFont',
                              color: lvlColor,
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (hasMeta)
                          const Icon(Icons.data_object, size: 14, color: AppColors.accentSecondary),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
