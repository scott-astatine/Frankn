import 'package:flutter/material.dart';
import 'package:frankn/screens/log_terminal_screen.dart';
import 'package:frankn/screens/settings_screen.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/desktop_layout.dart';
import 'package:frankn/widgets/log_terminal.dart';
import 'package:frankn/widgets/mobile_layout.dart';
import 'package:frankn/widgets/status_badge.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _client = RtcClient();
  final List<String> _logs = [];

  // Terminal States
  double _terminalHeight = 200.0;
  bool _isTerminalMinimized = false;
  final double _minHeight = 36.0;
  final double _maxHeight = 600.0;

  @override
  void initState() {
    super.initState();
    _client.connectToSignaling();
    _client.logStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs.insert(0, "> $log");
          if (_logs.length > 100) _logs.removeLast();
        });
      }
    });
  }

  void _toggleTerminal() {
    setState(() {
      if (_isTerminalMinimized) {
        _isTerminalMinimized = false;
        _terminalHeight = 200.0;
      } else if (_terminalHeight < 400) {
        _terminalHeight = 500.0;
      } else {
        _terminalHeight = 200.0;
      }
    });
  }

  void _minimizeTerminal() {
    setState(() {
      _isTerminalMinimized = !_isTerminalMinimized;
      if (_isTerminalMinimized) {
        _terminalHeight = _minHeight;
      } else {
        _terminalHeight = 200.0;
      }
    });
  }

  void _navigateToFullscreenTerminal() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LogTerminalScreen(client: _client, initialLogs: _logs),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile =
        MediaQuery.of(context).size.width < AppConstants.mobileBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: Stack(
        children: [
          // Fixed Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(
                    "https://www.transparenttextures.com/patterns/dark-matter.png",
                  ),
                  repeat: ImageRepeat.repeat,
                  opacity: 0.7,
                ),
              ),
            ),
          ),

          // Layout
          Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      floating: true,
                      snap: true,
                      backgroundColor: AppColors.voidBlack,
                      surfaceTintColor: Colors.transparent,
                      scrolledUnderElevation: 0,
                      title: Text("FRANKN:${_client.currentHostName ?? ''}"),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.settings, color: AppColors.neonCyan),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SettingsScreen(),
                              ),
                            );
                          },
                        ),
                        StreamBuilder<HostConnectionState>(
                          stream: _client.hostStateStream,
                          initialData: _client.currentHostState,
                          builder: (context, snapshot) {
                            if (snapshot.data ==
                                HostConnectionState.authenticated) {
                              return TextButton(
                                onPressed: () => _client.disconnectFromHost(),
                                child: const Text(
                                  "DISCONNECT",
                                  style: TextStyle(
                                    color: AppColors.errorRed,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        StreamBuilder<SignalConnectionState>(
                          stream: _client.connectionStateStream,
                          initialData: _client.sigState,
                          builder: (context, snapshot) => GestureDetector(
                            onTap: () {
                              _client.requestHostList();
                              _client.log("Manually refreshing host list...");
                            },
                            child: StatusBadge(state: snapshot.data!),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                    ),
                    SliverFillRemaining(
                      hasScrollBody: true,
                      child: isMobile
                          ? MobileLayout(client: _client)
                          : DesktopLayout(client: _client)
                    ),
                  ],
                ),
              ),
              _buildResizableTerminal(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResizableTerminal() {
    return Column(
      children: [
        // Drag Handle
        GestureDetector(
          onVerticalDragUpdate: (details) {
            setState(() {
              _terminalHeight -= details.delta.dy;
              if (_terminalHeight < _minHeight) {
                _terminalHeight = _minHeight;
                _isTerminalMinimized = true;
              } else {
                _isTerminalMinimized = false;
              }
              if (_terminalHeight > _maxHeight) _terminalHeight = _maxHeight;
            });
          },
          child: Container(
            height: 6,
            width: double.infinity,
            color: AppColors.voidBlack,
            child: Center(
              child: Container(
                width: 40,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.neonCyan.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: _terminalHeight,
          child: LogTerminal(
            logs: _logs,
            isMinimized: _isTerminalMinimized,
            onToggleExpand: _toggleTerminal,
            onMinimize: _minimizeTerminal,
            onFullscreen: _navigateToFullscreenTerminal,
          ),
        ),
      ],
    );
  }
}
