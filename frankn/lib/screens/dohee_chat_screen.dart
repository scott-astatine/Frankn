import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/cyber_alert_dialog.dart';
import 'package:frankn/widgets/dohee_chat/chat_message.dart';
import 'package:frankn/widgets/dohee_chat/message_bubble.dart';
import 'package:frankn/widgets/dohee_chat/antigravity_field.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

// ========== DATA MODELS ==========

enum ChatRole { operator, assistant, system }

// ========== MAIN SCREEN ==========

class ChatScreen extends StatefulWidget {
  final RtcThinClient client;
  final String modelPath;

  const ChatScreen({super.key, required this.client, required this.modelPath});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// ========== THEME CONSTANTS ==========

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _aiSub;
  StreamSubscription? _cmdSub;

  bool _isModelLoading = true;
  bool _isStreaming = false;

  Timer? _throttleTimer;
  String? _chatId;
  String _tokenBuffer = "";

  final ValueNotifier<List<dynamic>> _availableChats = ValueNotifier([]);

  String _systemPrompt = SettingsService().llmSystemPrompt;
  String _currentProvider = SettingsService().llmProvider;
  String _currentModel = "";
  List<String> _availableModels = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeoColors.background,
      body: Stack(
        children: [
          // Antigravity Interactive Particle Field
          const Positioned.fill(child: AntigravityField()),

          // Main Chat Content
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: SelectionArea(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        kToolbarHeight + 40,
                        16,
                        120,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) =>
                          MessageBubble(message: _messages[index]),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Glassmorphic Header
          Positioned(top: 0, left: 0, right: 0, child: _buildHeader()),

          // Floating Streaming Indicator
          if (_isStreaming)
            Positioned(
              bottom: 115,
              left: 24,
              child: _buildStreamingIndicator(),
            ),

          // Glassmorphic Input Deck
          Positioned(bottom: 30, left: 20, right: 20, child: _buildInputDeck()),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (var msg in _messages) {
      msg.dispose();
    }
    _aiSub?.cancel();
    _cmdSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _throttleTimer?.cancel();
    widget.client.sendDcMsg(const DcMsgLlmStop());
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentModel = widget.modelPath;
    _startModel(_currentModel);

    _aiSub = widget.client.aiStream.listen((msg) {
      _handleToken(msg);
    });

    _cmdSub = widget.client.genDcMsgStream.listen((msg) {
      if (!mounted) return;
      if (msg is HostMsgToolApprovalRequest) {
        _showApprovalDialog(msg);
      }
      if (msg is HostMsgResponse) {
        final data = msg.data;
        if (data != null && data is Map) {
          if (data['models'] != null) {
            setState(() {
              _availableModels = (data['models'] as List)
                  .map((m) => m['name'] as String)
                  .toList();
            });
          } else if (data['chats'] != null) {
            _availableChats.value = data['chats'];
          } else if (data['id'] != null && data['messages'] != null) {
            _loadChatData(Map<String, dynamic>.from(data));
          }
        }
      }
    });

    widget.client.sendDcMsg(const DcMsgListModels());
  }

  Widget _buildConnectionStatus() {
    return Stack(
      children: [
        const Icon(Icons.memory_rounded, color: NeoColors.zinc, size: 22),
        Positioned(
          top: 0,
          right: 0,
          child: _PulsingDot(color: NeoColors.fuchsia),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: kToolbarHeight + 45,
          padding: const EdgeInsets.fromLTRB(16, 35, 16, 0),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: NeoColors.fuchsia,
                  size: 22,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  "NEURAL CHAT // DOHEE",
                  style: GoogleFonts.inter(
                    color: NeoColors.fuchsia,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    shadows: [
                      Shadow(
                        color: NeoColors.fuchsia.withValues(alpha: 0.5),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                ),
              ),
              _buildConnectionStatus(),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.history_rounded,
                  color: NeoColors.zinc,
                  size: 20,
                ),
                onPressed: _showHistory,
              ),
              IconButton(
                icon: const Icon(
                  Icons.tune_rounded,
                  color: NeoColors.zinc,
                  size: 20,
                ),
                onPressed: _showSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "SESSION_HISTORY",
                style: GoogleFonts.jetBrainsMono(
                  color: NeoColors.fuchsia,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _chatId = null;
                    _messages.clear();
                    _messages.add(
                      ChatMessage(
                        role: ChatRole.system,
                        content: "Neural Link Established // New Session",
                      ),
                    );
                  });
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.add, color: NeoColors.cyan, size: 16),
                label: Text(
                  "NEW_CHAT",
                  style: GoogleFonts.jetBrainsMono(
                    color: NeoColors.cyan,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ValueListenableBuilder<List<dynamic>>(
              valueListenable: _availableChats,
              builder: (context, chats, _) {
                if (chats.isEmpty) {
                  return Center(
                    child: Text(
                      "NO_SESSIONS_FOUND",
                      style: GoogleFonts.jetBrainsMono(
                        color: NeoColors.zinc,
                        fontSize: 12,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return ListTile(
                      title: Text(
                        chat['title'] ?? 'UNKNOWN_SESSION',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        "ID: ${chat['id'].toString().substring(0, 8)}...",
                        style: GoogleFonts.jetBrainsMono(
                          color: NeoColors.zinc,
                          fontSize: 10,
                        ),
                      ),
                      onTap: () {
                        widget.client.sendDcMsg(
                          DcMsgLlmLoadChat(chatId: chat['id']),
                        );
                        Navigator.pop(context);
                      },
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: NeoColors.zinc,
                          size: 18,
                        ),
                        onPressed: () {
                          widget.client.sendDcMsg(
                            DcMsgLlmDeleteChat(chatId: chat['id']),
                          );
                          // Optimistically remove
                          final newChats = List<dynamic>.from(
                            _availableChats.value,
                          )..removeAt(index);
                          _availableChats.value = newChats;
                          if (_chatId == chat['id']) {
                            setState(() {
                              _chatId = null;
                              _messages.clear();
                              _messages.add(
                                ChatMessage(
                                  role: ChatRole.system,
                                  content:
                                      "Neural Link Established // New Session",
                                ),
                              );
                            });
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputDeck() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
              ),
            ],
          ),
          child: Row(
            children: [
              Text(
                ">",
                style: GoogleFonts.jetBrainsMono(
                  color: NeoColors.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  maxLines: 5,
                  minLines: 1,
                  cursorColor: NeoColors.cyan,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: "ENTER DIRECTIVE, BITCH...",
                    hintStyle: GoogleFonts.inter(
                      color: NeoColors.zinc.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.north_east_rounded,
                  color: NeoColors.cyan,
                  size: 24,
                ),
                onPressed: _isModelLoading ? null : _sendMessage,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.jetBrainsMono(
        color: NeoColors.zinc,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildStreamingIndicator() {
    return Row(
      children: [
        Text(
          "DOHEE_IS_STREAMING_TOKENS...",
          style: GoogleFonts.jetBrainsMono(
            color: NeoColors.fuchsia.withValues(alpha: 0.8),
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        _PulsingDot(color: NeoColors.fuchsia),
      ],
    );
  }

  void _handleToken(HostMsgLlmToken msg) {
    final token = msg.token;
    final isFinal = msg.isFinal;

    if (_isStreaming == false && !isFinal) {
      setState(() => _isStreaming = true);
    }

    if (_messages.isEmpty ||
        _messages.last.role != ChatRole.assistant ||
        !_messages.last.isStreamingNotifier.value) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: token,
            isStreaming: !isFinal,
          ),
        );
      });
      _tokenBuffer = "";
    } else {
      _tokenBuffer += token;
      if (isFinal) {
        _throttleTimer?.cancel();
        _messages.last.contentNotifier.value += _tokenBuffer;
        _messages.last.isStreamingNotifier.value = false;
        _tokenBuffer = "";
        setState(() => _isStreaming = false);
      } else {
        if (_throttleTimer == null || !_throttleTimer!.isActive) {
          _throttleTimer = Timer(const Duration(milliseconds: 150), () {
            if (_tokenBuffer.isNotEmpty && _messages.isNotEmpty) {
              _messages.last.contentNotifier.value += _tokenBuffer;
              _tokenBuffer = "";
              _scrollToBottomIfNeeded();
              setState(() {});
            }
          });
        }
      }
    }
    _scrollToBottomIfNeeded();
  }

  void _showApprovalDialog(HostMsgToolApprovalRequest request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: NeoColors.darkZinc,
          shape: Border.all(color: NeoColors.cyan, width: 2),
          title: Text(
            "🛡️ Direct Action Approval Required",
            style: GoogleFonts.jetBrainsMono(
              color: NeoColors.cyan,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "The agent is requesting to execute the following workstation operation:",
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Text(
                  "TOOL: ${request.tool.toUpperCase()}",
                  style: GoogleFonts.jetBrainsMono(
                    color: NeoColors.fuchsia,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: NeoColors.zinc.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    request.args,
                    style: GoogleFonts.jetBrainsMono(
                      color: NeoColors.cyan.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _sendApprovalResponse(request.approvalId, false);
              },
              child: Text(
                "🛑 REJECT",
                style: GoogleFonts.jetBrainsMono(color: AppColors.accentError),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: NeoColors.cyan.withValues(alpha: 0.2),
                side: const BorderSide(color: NeoColors.cyan),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _sendApprovalResponse(request.approvalId, true);
              },
              child: Text(
                "✓ APPROVE",
                style: GoogleFonts.jetBrainsMono(color: NeoColors.cyan),
              ),
            ),
          ],
        );
      },
    );
  }

  void _sendApprovalResponse(String approvalId, bool approved) {
    widget.client.sendDcMsg(
      DcMsgToolApprovalResponse(approvalId: approvalId, approved: approved),
    );
  }

  void _loadChatData(Map<String, dynamic> data) {
    setState(() {
      _chatId = data['id'];
      _messages.clear();
      _messages.add(
        ChatMessage(
          role: ChatRole.system,
          content:
              "Neural Link Established // Loaded Session: ${data['title']}",
        ),
      );
      final msgs = data['messages'] as List<dynamic>;
      for (var m in msgs) {
        final roleStr = m['role'] as String;
        if (roleStr == 'system') continue;
        _messages.add(
          ChatMessage(
            role: roleStr == 'user' ? ChatRole.operator : ChatRole.assistant,
            content: m['content'] as String,
            isStreaming: false,
          ),
        );
      }
    });
    _scrollToBottomIfNeeded(force: true);
  }

  void _scrollToBottomIfNeeded({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.position.pixels;
        if (force) {
          _scrollController.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        } else if (maxScroll - currentScroll <= 300) {
          _scrollController.jumpTo(maxScroll);
        }
      }
    });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _chatId ??= const Uuid().v4();

    setState(() {
      _messages.add(ChatMessage(role: ChatRole.operator, content: text));
      _messages.add(
        ChatMessage(role: ChatRole.assistant, content: "", isStreaming: true),
      );
      _inputController.clear();
      _isStreaming = true;
    });

    widget.client.sendDcMsg(
      DcMsgLlmChat(message: text, systemPrompt: _systemPrompt, chatId: _chatId),
    );
    _scrollToBottomIfNeeded(force: true);
  }

  void _showHistory() {
    widget.client.sendDcMsg(const DcMsgLlmListChats());
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: NeoColors.fuchsia, width: 1),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _buildHistoryPanel(),
    );
  }

  void _showSettings() {
    String tempPrompt = _systemPrompt;
    String tempProvider = _currentProvider;
    String tempModel = _currentModel;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return CyberAlertDialog(
            title: "NEURAL_CORE_CONFIG",
            titleColor: NeoColors.fuchsia,
            borderColor: NeoColors.fuchsia,
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSettingLabel("PROVIDER_UPSTREAM"),
                  DropdownButtonFormField<String>(
                    initialValue: tempProvider,
                    dropdownColor: const Color(0xFF1A1A1A),
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white10),
                      ),
                    ),
                    items: ["Ollama", "Local (llama.cpp) (Deprecated)"]
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => tempProvider = val);
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildSettingLabel("WEIGHTS_VARIANT"),
                  if (_availableModels.isEmpty)
                    const Text(
                      "No models found in vault.",
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _availableModels.contains(tempModel)
                          ? tempModel
                          : null,
                      dropdownColor: const Color(0xFF1A1A1A),
                      isExpanded: true,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                      items: _availableModels
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(m, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => tempModel = val);
                      },
                    ),
                  const SizedBox(height: 20),
                  _buildSettingLabel("SYSTEM_DIRECTIVE"),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(text: tempPrompt),
                    onChanged: (val) => tempPrompt = val,
                    maxLines: 5,
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.03),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: NeoColors.fuchsia),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "ABORT",
                  style: GoogleFonts.jetBrainsMono(
                    color: NeoColors.zinc,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  setState(() {
                    _systemPrompt = tempPrompt;
                    _currentProvider = tempProvider;
                  });
                  await SettingsService().setLlmSystemPrompt(tempPrompt);
                  await SettingsService().setLlmProvider(tempProvider);

                  if (tempModel != _currentModel && tempModel.isNotEmpty) {
                    await SettingsService().setLlmDefaultModel(tempModel);
                    _switchModel(tempModel);
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
                child: Text(
                  "APPLY_PATCH",
                  style: GoogleFonts.jetBrainsMono(
                    color: NeoColors.fuchsia,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _startModel(String path) {
    setState(() => _isModelLoading = true);
    widget.client.sendDcMsg(DcMsgLlmStart(modelPath: path));
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _isModelLoading = false;
          _messages.add(
            ChatMessage(
              role: ChatRole.system,
              content: "Neural Link Established // Gemma-2B-Uncensored Active",
            ),
          );
        });
      }
    });
  }

  void _switchModel(String newPath) {
    widget.client.sendDcMsg(const DcMsgLlmStop());
    setState(() {
      _currentModel = newPath;
      _messages.add(
        ChatMessage(
          role: ChatRole.system,
          content: "Switching Neural Weights to $newPath...",
        ),
      );
    });
    _startModel(newPath);
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.5),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }
}
