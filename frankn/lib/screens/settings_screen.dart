import 'package:flutter/material.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/settings/settings_tile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _editSignalingUrl() {
    final controller =
        TextEditingController(text: SettingsService().signalingUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelGrey,
        shape: const BeveledRectangleBorder(
            side: BorderSide(color: AppColors.neonCyan)),
        title: const Text("SIGNALING SERVER",
            style: TextStyle(color: AppColors.neonCyan, fontSize: 14)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "ws://...",
            hintStyle: TextStyle(color: AppColors.textGrey),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.neonCyan)),
          ),
          onSubmitted: (_) async {
              await SettingsService().setSignalingUrl(controller.text);
              if (context.mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL",
                  style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonCyan,
                foregroundColor: Colors.black),
            onPressed: () async {
              await SettingsService().setSignalingUrl(controller.text);
              if (context.mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  void _editFontSize() {
    double currentSize = SettingsService().terminalFontSize;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.panelGrey,
          shape: const BeveledRectangleBorder(
              side: BorderSide(color: AppColors.neonCyan)),
          title: const Text("TERMINAL FONT SIZE",
              style: TextStyle(color: AppColors.neonCyan, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${currentSize.toInt()}px",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              Slider(
                value: currentSize,
                min: 8,
                max: 24,
                divisions: 16,
                activeColor: AppColors.neonCyan,
                inactiveColor: AppColors.textGrey,
                onChanged: (v) => setState(() => currentSize = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CANCEL",
                    style: TextStyle(color: AppColors.textGrey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonCyan,
                  foregroundColor: Colors.black),
              onPressed: () async {
                await SettingsService().setTerminalFontSize(currentSize);
                if (context.mounted) {
                  Navigator.pop(context);
                  this.setState(() {});
                }
              },
              child: const Text("SAVE"),
            ),
          ],
        ),
      ),
    );
  }

  void _editColorScheme() {
    final schemes = ["Cyberpunk", "Matrix", "Vaporwave", "Monokai"];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelGrey,
        shape: const BeveledRectangleBorder(
            side: BorderSide(color: AppColors.neonCyan)),
        title: const Text("COLOR SCHEME",
            style: TextStyle(color: AppColors.neonCyan, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: schemes
              .map((s) => ListTile(
                    title: Text(s,
                        style: TextStyle(
                            color: s == SettingsService().colorScheme
                                ? AppColors.neonCyan
                                : Colors.white)),
                    onTap: () async {
                      await SettingsService().setColorScheme(s);
                      if (context.mounted) {
                        Navigator.pop(context);
                        setState(() {});
                      }
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      appBar: AppBar(
        title: const Text(
          "SYSTEM CONFIG",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        backgroundColor: AppColors.deepSpace,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.neonCyan),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          const SettingsSectionHeader(title: "CONNECTION"),
          SettingsTile(
            title: "Signaling Server",
            subtitle: SettingsService().signalingUrl,
            icon: Icons.router,
            onTap: _editSignalingUrl,
          ),
          SettingsTile(
            title: "Identity",
            subtitle: RtcClient().selfId ?? "Unknown",
            icon: Icons.fingerprint,
            iconColor: AppColors.neonPink,
            onTap: () {}, // Just info
          ),

          const SettingsSectionHeader(title: "TERMINAL"),
          SettingsTile(
            title: "Font Size",
            subtitle: "${SettingsService().terminalFontSize.toInt()}px",
            icon: Icons.format_size,
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textGrey),
            onTap: _editFontSize,
          ),
          SettingsTile(
            title: "Color Scheme",
            subtitle: SettingsService().colorScheme,
            icon: Icons.palette,
            iconColor: AppColors.cyberYellow,
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textGrey),
            onTap: _editColorScheme,
          ),

          const SettingsSectionHeader(title: "ABOUT"),
          SettingsTile(
            title: "Version",
            subtitle: "Frankn Client v1.0.0",
            icon: Icons.info_outline,
            iconColor: AppColors.textWhite,
          ),
          SettingsTile(
            title: "License",
            subtitle: "MIT Open Source",
            icon: Icons.description,
            iconColor: AppColors.textWhite,
          ),
        ],
      ),
    );
  }
}
