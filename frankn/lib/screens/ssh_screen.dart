import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/ssh/ssh_controller.dart';
import 'package:frankn/widgets/ssh/ssh_theme.dart';
import 'package:frankn/widgets/ssh/key_bar.dart';
import 'package:frankn/widgets/ssh/status_bar.dart';
import 'package:frankn/widgets/ssh/terminal_context_menu.dart';
import 'package:frankn/widgets/cyber_alert_dialog.dart';
import 'package:xterm/xterm.dart';

class SShScreen extends StatefulWidget {
  final RtcThinClient client;
  const SShScreen({super.key, required this.client});

  @override
  State<SShScreen> createState() => _SShScreenState();
}

class _SShScreenState extends State<SShScreen> {
  late final SshController _controller;
  final _userController = TextEditingController(text: '');
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
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.client.activeSshController != null) {
      _controller = widget.client.activeSshController as SshController;
    } else {
      _controller = SshController(widget.client);
      widget.client.activeSshController = _controller;

      _controller.terminal.write('\x1b[36mFRANKN TERMINAL v1.2\x1b[0m\r\n');
      _controller.terminal.write('Status: \x1b[32mREADY\x1b[0m\r\n');
      _controller.terminal.write('Uplink: \x1b[35mENCRYPTED P2P\x1b[0m\r\n\n');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_controller.isConnected && !_controller.isConnecting) {
        if (widget.client.lastSshUsername != null) {
          _attemptAutoLogin();
        } else {
          _loginDialog();
        }
      }
    });
  }

  Future<void> _attemptAutoLogin() async {
    try {
      await _controller.startSession(
        widget.client.lastSshUsername!,
        widget.client.lastSshPassword,
      );
    } catch (e) {
      widget.client.lastSshUsername = null;
      widget.client.lastSshPassword = null;
      if (mounted) _loginDialog(error: "Session restored failed: ${e.toString()}");
    }
  }

  void _handleExplicitExit() {
    if (widget.client.activeSshController != null) {
      final ctrl = widget.client.activeSshController as SshController;
      ctrl.stopSession();
      ctrl.dispose();
      widget.client.activeSshController = null;
    }
    widget.client.lastSshUsername = null;
    widget.client.lastSshPassword = null;
    Navigator.pop(context);
  }

  Widget _buildHud(bool isKeyboardActive) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.9),
        border: const Border(
          top: BorderSide(color: AppColors.accentPrimary, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isKeyboardActive)
            SshKeyBar(
              ctrlState: _controller.ctrlState,
              altState: _controller.altState,
              shiftState: _controller.shiftState,
              onToggleCtrl: _controller.toggleCtrl,
              onLockCtrl: _controller.lockCtrl,
              onToggleAlt: _controller.toggleAlt,
              onLockAlt: _controller.lockAlt,
              onToggleShift: _controller.toggleShift,
              onLockShift: _controller.lockShift,
              onSendRaw: _controller.sendRaw,
            ),
          SshStatusBar(
            isConnected: _controller.isConnected,
            isConnecting: _controller.isConnecting,
            onExit: _handleExplicitExit,
          ),
        ],
      ),
    );
  }

  void _loginDialog({String? error}) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CyberAlertDialog(
        borderColor: error != null ? AppColors.accentError : AppColors.accentPrimary,
        titleColor: error != null ? AppColors.accentError : AppColors.accentPrimary,
        title: error != null ? "AUTHENTICATION FAILED" : "SSH AUTHENTICATION",
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  error,
                  style: const TextStyle(
                    color: AppColors.accentError,
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
                labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accentPrimary),
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
                labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (widget.client.activeSshController != null) {
                final ctrl = widget.client.activeSshController as SshController;
                ctrl.stopSession();
                ctrl.dispose();
                widget.client.activeSshController = null;
              }
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text(
              "ABORT",
              style: TextStyle(
                color: AppColors.accentError,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          CyberButton(
            text: "INITIATE",
            onPressed: () async {
              Navigator.pop(context);
              final user = _userController.text;
              final pass = _passController.text.isNotEmpty ? _passController.text : null;
              try {
                await _controller.startSession(user, pass);
                widget.client.lastSshUsername = user;
                widget.client.lastSshPassword = pass;
              } catch (e) {
                _loginDialog(error: e.toString());
              }
            },
          ),
        ],
      ),
    );
  }
}
