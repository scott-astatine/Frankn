import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';

class TrackpadScreen extends StatefulWidget {
  final RtcThinClient client;
  const TrackpadScreen({super.key, required this.client});

  @override
  State<TrackpadScreen> createState() => _TrackpadScreenState();
}

class _TrackpadScreenState extends State<TrackpadScreen> {
  double _dx = 0;
  double _dy = 0;
  double _scrollX = 0;
  double _scrollY = 0;

  int _pointerCount = 0;
  int _maxPointers = 0;
  Timer? _batchTimer;

  bool _isDragging = false;

  final FocusNode _keyboardFocusNode = FocusNode();
  final TextEditingController _inputController = TextEditingController();

  // Sticky Modifier States
  ModState _ctrl = ModState.off;
  ModState _alt = ModState.off;
  ModState _shift = ModState.off;
  ModState _super = ModState.off;

  @override
  void initState() {
    super.initState();
    _batchTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _flushMouseEvents();
      _flushScrollEvents();
    });
  }

  void _flushMouseEvents() {
    final int dxInt = _dx.truncate();
    final int dyInt = _dy.truncate();
    if (dxInt != 0 || dyInt != 0) {
      widget.client.sendInputMsg({
        'type': InputSig.MouseMove,
        'dx': dxInt.toDouble(),
        'dy': dyInt.toDouble(),
      });
      _dx -= dxInt;
      _dy -= dyInt;
    }
  }

  void _flushScrollEvents() {
    final int sxInt = _scrollX.truncate();
    final int syInt = _scrollY.truncate();
    if (sxInt != 0 || syInt != 0) {
      widget.client.sendInputMsg({
        'type': 'scroll',
        'dx': sxInt.toDouble(),
        'dy': syInt.toDouble(),
      });
      _scrollX -= sxInt;
      _scrollY -= syInt;
    }
  }

  @override
  void dispose() {
    _batchTimer?.cancel();
    _keyboardFocusNode.dispose();
    _inputController.dispose();
    super.dispose();
  }

  // --- KEYBOARD LOGIC ---

  void _lockMod(String mod) {
    setState(() {
      switch (mod) {
        case 'CTRL':
          _ctrl = (_ctrl == ModState.locked) ? ModState.off : ModState.locked;
          _syncMod(29, _ctrl);
          break;
        case 'ALT':
          _alt = (_alt == ModState.locked) ? ModState.off : ModState.locked;
          _syncMod(56, _alt);
          break;
        case 'SHIFT':
          _shift = (_shift == ModState.locked) ? ModState.off : ModState.locked;
          _syncMod(42, _shift);
          break;
        case 'SUPER':
          _super = (_super == ModState.locked) ? ModState.off : ModState.locked;
          _syncMod(125, _super);
          break;
      }
    });
  }

  void _toggleMod(String mod) {
    setState(() {
      switch (mod) {
        case 'CTRL':
          if (_ctrl == ModState.locked) {
            _ctrl = ModState.off;
          } else {
            _ctrl = (_ctrl == ModState.active) ? ModState.off : ModState.active;
          }
          _syncMod(29, _ctrl);
          break;
        case 'ALT':
          if (_alt == ModState.locked) {
            _alt = ModState.off;
          } else {
            _alt = (_alt == ModState.active) ? ModState.off : ModState.active;
          }
          _syncMod(56, _alt);
          break;
        case 'SHIFT':
          if (_shift == ModState.locked) {
            _shift = ModState.off;
          } else {
            _shift = (_shift == ModState.active) ? ModState.off : ModState.active;
          }
          _syncMod(42, _shift);
          break;
        case 'SUPER':
          if (_super == ModState.locked) {
            _super = ModState.off;
          } else {
            _super = (_super == ModState.active) ? ModState.off : ModState.active;
          }
          _syncMod(125, _super);
          break;
      }
    });
  }

  void _syncMod(int code, ModState state) {
    final bool down = state != ModState.off;
    widget.client.sendInputMsg({
      'type': InputSig.KeyPress,
      'key_code': code,
      'down': down,
    });
  }

  void _sendKey(int code) {
    // 1. Ensure all active/locked mods are down (redundant but safe)
    // 2. Press key
    widget.client.sendInputMsg({
      'type': InputSig.KeyPress,
      'key_code': code,
      'down': true,
    });
    widget.client.sendInputMsg({
      'type': InputSig.KeyPress,
      'key_code': code,
      'down': false,
    });

    // 3. Auto-release "active" (but not locked) mods
    setState(() {
      if (_ctrl == ModState.active) {
        _ctrl = ModState.off;
        _syncMod(29, _ctrl);
      }
      if (_alt == ModState.active) {
        _alt = ModState.off;
        _syncMod(56, _alt);
      }
      if (_shift == ModState.active) {
        _shift = ModState.off;
        _syncMod(42, _shift);
      }
      if (_super == ModState.active) {
        _super = ModState.off;
        _syncMod(125, _super);
      }
    });
  }

  void _handleTextInput(String text) {
    if (text.isEmpty) {
      // The zero-width space was deleted! Send a backspace.
      _sendKey(14); // BSPC keycode
      _inputController.text = '\u200B';
      return;
    }

    // Remove the zero-width space from the beginning if it's there
    final actualText = text.startsWith('\u200B') ? text.substring(1) : text;

    if (actualText.isNotEmpty) {
      widget.client.sendInputMsg({'type': InputSig.Text, 'text': actualText});
    }

    // Reset the controller with just the zero-width space
    _inputController.text = '\u200B';

    // Auto-release active mods after typing
    setState(() {
      if (_ctrl == ModState.active) {
        _ctrl = ModState.off;
        _syncMod(29, _ctrl);
      }
      if (_alt == ModState.active) {
        _alt = ModState.off;
        _syncMod(56, _alt);
      }
      if (_shift == ModState.active) {
        _shift = ModState.off;
        _syncMod(42, _shift);
      }
      if (_super == ModState.active) {
        _super = ModState.off;
        _syncMod(125, _super);
      }
    });
  }

  // --- MOUSE LOGIC ---

  void _handleTap() {
    if (_maxPointers <= 1) {
      _sendClick(1);
    } else if (_maxPointers == 2) {
      _sendClick(2);
    } else if (_maxPointers == 3) {
      _sendClick(3);
    }
    _maxPointers = 0;
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (_pointerCount == 1) {
      setState(() {
        _isDragging = true;
      });
      widget.client.sendInputMsg({
        'type': InputSig.MouseClick,
        'button': 1,
        'down': true,
      });
    }
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_isDragging) {
      setState(() {
        _isDragging = false;
      });
      widget.client.sendInputMsg({
        'type': InputSig.MouseClick,
        'button': 1,
        'down': false,
      });
    }
  }

  void _sendClick(int button) {
    widget.client.sendInputMsg({
      'type': InputSig.MouseClick,
      'button': button,
      'down': true,
    });
    widget.client.sendInputMsg({
      'type': InputSig.MouseClick,
      'button': button,
      'down': false,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: Stack(
        children: [
          // Hidden Input for Voice/Keyboard
          Positioned(
            top: -100,
            child: SizedBox(
              width: 1,
              height: 1,
              child: TextField(
                controller: _inputController,
                focusNode: _keyboardFocusNode,
                onChanged: _handleTextInput,
                onSubmitted: (_) {
                  _sendKey(28); // ENTER keycode
                  _keyboardFocusNode.requestFocus(); // Keep keyboard open
                },
                textInputAction: TextInputAction.send,
              ),
            ),
          ),

          // 1. Trackpad Area
          Positioned.fill(
            bottom: isKeyboardVisible
                ? 100
                : 0, // Space for the toolbar if keyboard is open
              child: Listener(
                onPointerDown: (e) {
                  setState(() {
                    if (_pointerCount == 0) _maxPointers = 0;
                    _pointerCount++;
                    if (_pointerCount > _maxPointers) {
                      _maxPointers = _pointerCount;
                    }
                  });
                },
                onPointerUp: (e) {
                  setState(() {
                    _pointerCount--;
                    if (_pointerCount < 0) _pointerCount = 0;
                  });
                },
                onPointerMove: (e) {
                  final sens = SettingsService().trackpadSensitivity;
                  if (_pointerCount <= 1) {
                    _dx += e.delta.dx * sens;
                    _dy += e.delta.dy * sens;
                  } else if (_pointerCount == 2) {
                    _scrollX += e.delta.dx * sens;
                    _scrollY += e.delta.dy * sens;
                  }
                },
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) {
                    final sens = SettingsService().trackpadSensitivity;
                    _scrollX += e.scrollDelta.dx * sens;
                    _scrollY += e.scrollDelta.dy * sens;
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleTap,
                  onLongPressStart: _handleLongPressStart,
                  onLongPressEnd: _handleLongPressEnd,
                  child: Container(
                  color: Colors.transparent,
                  child: Center(
                    child: Icon(
                      Icons.touch_app_outlined,
                      size: 80,
                      color: AppColors.neonCyan.withValues(alpha: 0.05),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Floating button to summon keyboard when hidden
          if (!isKeyboardVisible)
            Positioned(
              bottom: 30,
              right: 30,
              child: FloatingActionButton(
                backgroundColor: AppColors.neonCyan.withValues(alpha: 0.1),
                foregroundColor: AppColors.neonCyan,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: AppColors.neonCyan.withValues(alpha: 0.3),
                  ),
                ),
                onPressed: () {
                  _keyboardFocusNode.requestFocus();
                  SystemChannels.textInput.invokeMethod('TextInput.show');
                },
                child: const Icon(Icons.keyboard_outlined),
              ),
            ),

          // 2. Compact Modifier Toolbar (Visible only when keyboard is up)
          if (isKeyboardVisible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1A1F),
                  border: Border(
                    top: BorderSide(
                      color: AppColors.neonCyan.withValues(alpha: 0.2),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _buildKey("ESC", 1),
                        _buildModKey("CTRL", _ctrl),
                        _buildModKey("ALT", _alt),
                        _buildModKey("SHIFT", _shift),
                        _buildModKey("SUPER", _super),
                        _buildKey("TAB", 15),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildKey("←", 105),
                        _buildKey("↑", 103),
                        _buildKey("↓", 108),
                        _buildKey("→", 106),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              SystemChannels.textInput.invokeMethod(
                                'TextInput.hide',
                              );
                            },
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.keyboard_hide_outlined,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModKey(String label, ModState state) {
    Color color = Colors.white54;
    Color glow = Colors.transparent;
    Color borderColor = Colors.white10;

    if (state == ModState.active) {
      color = AppColors.neonCyan;
      glow = AppColors.neonCyan.withValues(alpha: 0.15);
      borderColor = AppColors.neonCyan.withValues(alpha: 0.5);
    }
    if (state == ModState.locked) {
      color = AppColors.neonPink;
      glow = AppColors.neonPink.withValues(alpha: 0.2);
      borderColor = AppColors.neonPink.withValues(alpha: 0.6);
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: () => _toggleMod(label),
          onDoubleTap: () => _lockMod(label),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: glow,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKey(String label, int code) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: () => _sendKey(code),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
