import 'package:flutter/material.dart';
import 'package:frankn/screens/dohee_chat_screen.dart';

class ChatMessage {
  final ChatRole role;
  final ValueNotifier<String> contentNotifier;
  final ValueNotifier<bool> isStreamingNotifier;
  final String timestamp;

  ChatMessage({
    required this.role,
    required String content,
    bool isStreaming = false,
  }) : contentNotifier = ValueNotifier<String>(content),
       isStreamingNotifier = ValueNotifier<bool>(isStreaming),
       timestamp = _formatTimestamp();

  static String _formatTimestamp() {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
  }

  void dispose() {
    contentNotifier.dispose();
    isStreamingNotifier.dispose();
  }
}
