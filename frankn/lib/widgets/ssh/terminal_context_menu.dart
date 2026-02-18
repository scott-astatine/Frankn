import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/utils/utils.dart';
import 'package:xterm/xterm.dart';

class TerminalContextMenu extends StatelessWidget {
  final Terminal terminal;
  final Widget child;

  const TerminalContextMenu({
    super.key,
    required this.terminal,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) => _showMenu(context, details.globalPosition),
      child: child,
    );
  }

  void _showMenu(BuildContext context, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: AppColors.panelGrey,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.neonCyan, width: 1),
      ),
      items: [
        // Note: Copy is handled natively by the terminal view's selection
        PopupMenuItem(
          value: 'paste',
          height: 32,
          child: _buildMenuItem('PASTE', Icons.paste),
          onTap: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data?.text != null) {
              terminal.paste(data!.text!);
            }
          },
        ),
        PopupMenuItem(
          value: 'clear',
          height: 32,
          child: _buildMenuItem('CLEAR', Icons.clear_all),
          onTap: () {
            terminal.buffer.clear();
            terminal.buffer.setCursor(0, 0);
            // terminal.refresh(); // Removed as it's undefined
          },
        ),
      ],
    );
  }

  Widget _buildMenuItem(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.neonCyan),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'JetBrainsMonoNerdFont',
          ),
        ),
      ],
    );
  }
}