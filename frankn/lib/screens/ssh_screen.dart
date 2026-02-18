import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/ssh/ssh_controller.dart';
import 'package:frankn/widgets/ssh/ssh_theme.dart';
import 'package:frankn/widgets/ssh/key_bar.dart';
import 'package:frankn/widgets/ssh/status_bar.dart';
import 'package:frankn/widgets/ssh/terminal_context_menu.dart';
import 'package:xterm/xterm.dart';

class SShScreen extends StatefulWidget {
  final RtcClient client;
  const SShScreen({super.key, required this.client});

  @override
  State<SShScreen> createState() => _SShScreenState();
}

class _SShScreenState extends State<SShScreen> {
  late final SshController _controller;
  final _userController = TextEditingController(text: 'scott');
  final _passController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: true,
          body: Column(
            children: [
              Expanded(
                child: SafeArea(
                  child: TerminalContextMenu(
                    terminal: _controller.terminal,
                    child: TerminalView(
                      _controller.terminal,
                      theme: SshTheme.terminalTheme,
                      textStyle: TerminalStyle(
                        fontSize: SettingsService().terminalFontSize,
                        fontFamily: 'JetBrainsMonoNerdFont',
                      ),
                    ),
                  ),
                ),
              ),
              _buildHud(isKeyboardVisible),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller = SshController(widget.client);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _controller.terminal.write('\x1b[36mFRANKN TERMINAL v1.2\x1b[0m\r\n');
    _controller.terminal.write('Status: \x1b[32mREADY\x1b[0m\r\n');
    _controller.terminal.write('Uplink: \x1b[35mENCRYPTED P2P\x1b[0m\r\n\n');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showLoginDialog();
    });
  }

  Widget _buildHud(bool isKeyboardActive) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.voidBlack.withValues(alpha: 0.9),
        border: const Border(
          top: BorderSide(color: AppColors.neonCyan, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isKeyboardActive)
            SshKeyBar(
              ctrlActive: _controller.ctrlActive,
              altActive: _controller.altActive,
              onToggleCtrl: _controller.toggleCtrl,
              onToggleAlt: _controller.toggleAlt,
              onSendRaw: _controller.sendRaw,
            ),
          SshStatusBar(
            isConnected: _controller.isConnected,
            isConnecting: _controller.isConnecting,
            onExit: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showLoginDialog({String? error}) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelGrey,
        shape: const BeveledRectangleBorder(
          side: BorderSide(color: AppColors.neonCyan, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        title: Text(
          error != null ? "AUTHENTICATION FAILED" : "SSH AUTHENTICATION",
          style: TextStyle(
            color: error != null ? AppColors.errorRed : AppColors.neonCyan,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  error,
                  style: const TextStyle(
                    color: AppColors.errorRed,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            TextField(
              controller: _userController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "USERNAME",
                labelStyle: TextStyle(color: AppColors.textGrey, fontSize: 10),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.neonCyan),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "PASSCODE (LEAVE BLANK FOR HOST PWD)",
                labelStyle: TextStyle(color: AppColors.textGrey, fontSize: 10),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textGrey),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text(
              "ABORT",
              style: TextStyle(
                color: AppColors.errorRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          CyberButton(
            text: "INITIATE",
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _controller.startSession(
                  _userController.text,
                  _passController.text.isNotEmpty ? _passController.text : null,
                );
              } catch (e) {
                _showLoginDialog(error: e.toString());
              }
            },
          ),
        ],
      ),
    );
  }
}
