import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/utils/utils.dart';
import 'package:xterm/xterm.dart';

class TerminalContextMenu extends StatefulWidget {
  final Terminal terminal;
  final TerminalController controller;
  final Widget child;

  const TerminalContextMenu({
    super.key,
    required this.terminal,
    required this.controller,
    required this.child,
  });

  @override
  State<TerminalContextMenu> createState() => _TerminalContextMenuState();
}

class _TerminalContextMenuState extends State<TerminalContextMenu> {
  Offset? _downPosition;
  DateTime? _downTime;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        // Handle desktop right click immediately
        if (event.buttons == 2) {
          _showMenu(context, event.position);
          return;
        }

        _downPosition = event.position;
        _downTime = DateTime.now();
      },
      onPointerUp: (event) {
        final downTime = _downTime;
        final downPos = _downPosition;
        if (downTime == null || downPos == null) return;

        final duration = DateTime.now().difference(downTime);
        final distance = (event.position - downPos).distance;

        // Reset tracking
        _downTime = null;
        _downPosition = null;

        final isLongPress = duration.inMilliseconds > 500;
        final isSelectionActive = widget.controller.selection != null;
        final hasNotMoved = distance < 15;

        if (isSelectionActive && hasNotMoved) {
          // Case A: Tapped on an existing active selection (e.g., after double-tap)
          _showMenu(context, event.position);
        } else if (isLongPress) {
          if (hasNotMoved) {
            // Case B: Long press without dragging (e.g., to Paste/Clear)
            _showMenu(context, event.position);
          } else if (isSelectionActive) {
            // Case C: Hold, drag to select text, and release
            _showMenu(context, event.position);
          }
          // Case D: User just scrolled the terminal page (moved > 15px with no active selection), do nothing
        }
      },
      onPointerCancel: (event) {
        _downTime = null;
        _downPosition = null;
      },
      child: widget.child,
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
      color: AppColors.surfaceSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.accentPrimary, width: 1),
      ),
      items: [
        if (widget.controller.selection != null)
          PopupMenuItem(
            value: 'copy',
            height: 32,
            child: _buildMenuItem('COPY', Icons.copy),
            onTap: () async {
              final selection = widget.controller.selection;
              if (selection != null) {
                final text = widget.terminal.buffer.getText(selection);
                if (text.isNotEmpty) {
                  await Clipboard.setData(ClipboardData(text: text));
                  widget.controller.clearSelection();
                }
              }
            },
          ),
        PopupMenuItem(
          value: 'paste',
          height: 32,
          child: _buildMenuItem('PASTE', Icons.paste),
          onTap: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data?.text != null) {
              widget.terminal.paste(data!.text!);
            }
          },
        ),
        PopupMenuItem(
          value: 'clear',
          height: 32,
          child: _buildMenuItem('CLEAR', Icons.clear_all),
          onTap: () {
            widget.terminal.buffer.clear();
            widget.terminal.buffer.setCursor(0, 0);
          },
        ),
      ],
    );
  }

  Widget _buildMenuItem(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.accentPrimary),
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
