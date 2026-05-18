import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/screens/sync_manager_screen.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/main.dart';
import 'package:frankn/widgets/cyber_alert_dialog.dart';
import 'package:frankn/widgets/dohee_chat/model_selector_dialog.dart';
import 'package:google_fonts/google_fonts.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _client = RtcThinClient();

  void _showLanguageSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border(
            top: BorderSide(color: AppColors.neonPink, width: 1.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSelectorTile(
              "ENGLISH",
              _settings.localeCode == 'en',
              () async {
                await _settings.setLocaleCode('en');
                appLocale.value = const Locale('en');
                if (!context.mounted) return;
                Navigator.pop(context);
                setState(() {});
              },
            ),
            _buildSelectorTile("한국어", _settings.localeCode == 'ko', () async {
              await _settings.setLocaleCode('ko');
              appLocale.value = const Locale('ko');
              if (!context.mounted) return;
              Navigator.pop(context);
              setState(() {});
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectorTile(String label, bool isSelected, VoidCallback onTap) {
    return ListTile(
      title: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14,
          letterSpacing: 1,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.neonPink)
          : null,
      onTap: onTap,
    );
  }

  void _showFontSizeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border(
            top: BorderSide(color: AppColors.neonPink, width: 1.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [8, 9, 10, 12, 13, 14, 16, 18, 20]
              .map(
                (size) => ListTile(
                  title: Text(
                    "$size PX",
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontFamily: 'JetBrainsMonoNerdFont',
                    ),
                  ),
                  trailing: _settings.terminalFontSize == size.toDouble()
                      ? const Icon(Icons.check, color: AppColors.neonPink)
                      : null,
                  onTap: () async {
                    await _settings.setTerminalFontSize(size.toDouble());
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _showTrackpadSensitivitySelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border(
            top: BorderSide(color: AppColors.neonPink, width: 1.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [1.0, 1.25, 1.5, 2.0, 2.5, 3.0]
              .map(
                (size) => ListTile(
                  title: Text(
                    "${size}X MULTIPLIER",
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontFamily: 'JetBrainsMonoNerdFont',
                    ),
                  ),
                  trailing: _settings.trackpadSensitivity == size
                      ? const Icon(Icons.check, color: AppColors.neonPink)
                      : null,
                  onTap: () async {
                    await _settings.setTrackpadSensitivity(size);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _renameHost() {
    final hostId = _client.currentHostId;
    if (hostId == null) return;

    final controller = TextEditingController(text: _client.currentHostName);
    showDialog(
      context: context,
      builder: (context) => CyberAlertDialog(
        title: "RENAME_HOST",
        content: TextField(
          controller: controller,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white10),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.neonPink),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "ABORT",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await _settings.updateHostName(hostId, newName);
                _client.currentHostName = newName;
                if (!context.mounted) return;
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text(
              "UPDATE",
              style: TextStyle(
                color: AppColors.neonPink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editSignalingUrl() {
    final controller = TextEditingController(text: _settings.signalingUrl);

    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return CyberAlertDialog(
          title: l10n.signalingServer,
          content: TextField(
            controller: controller,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white10),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.neonPink),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "ABORT",
                style: TextStyle(color: AppColors.textGrey),
              ),
            ),
            TextButton(
              onPressed: () async {
                final newUrl = controller.text.trim();
                if (newUrl.isNotEmpty && newUrl.startsWith('ws')) {
                  await _settings.setSignalingUrl(newUrl);
                  _client.disconnectFromHost();
                  _client.connectToSignaling();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  setState(() {});

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Re-initializing Neural Link to new server...',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: AppColors.matrixGreen,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Invalid URL format. Must start with ws:// or wss://',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: AppColors.errorRed,
                    ),
                  );
                }
              },
              child: const Text(
                "UPDATE",
                style: TextStyle(
                  color: AppColors.neonPink,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editDefaultModel() async {
    final selectedModel = await showDialog<String>(
      context: context,
      builder: (context) =>
          ModelSelectorDialog(client: _client, isSettingsMode: true),
    );

    if (selectedModel != null && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.settings,
          style: GoogleFonts.jetBrainsMono(
            color: Colors.grey[400],
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: 2,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          _buildSectionHeader(l10n.settings),
          const SizedBox(height: 12),
          _buildSettingsGroup(
            children: [
              if (_client.currentHostId != null) ...[
                _buildSettingsItem(
                  title: l10n.hostAlias,
                  value: _client.currentHostName ?? "UNKNOWN",
                  icon: Icons.terminal_rounded,
                  iconColor: Colors.cyan,
                  onTap: _renameHost,
                ),
                _buildSettingsItem(
                  title: l10n.storageSync,
                  value: l10n.manageDir,
                  icon: Icons.sync_rounded,
                  iconColor: Colors.green,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SyncManagerScreen(),
                      ),
                    );
                  },
                ),
              ],
              _buildSettingsItem(
                title: l10n.signalingServer,
                value: _settings.signalingUrl,
                icon: Icons.cell_tower_rounded,
                iconColor: Colors.pinkAccent,
                onTap: _editSignalingUrl,
              ),
              if (_client.currentHostId != null)
                _buildSettingsItem(
                  title: "Default LLM",
                  value: _settings.llmDefaultModel.isEmpty
                      ? "NOT_SET"
                      : _settings.llmDefaultModel,
                  icon: Icons.memory_rounded,
                  iconColor: Colors.indigo,
                  onTap: _editDefaultModel,
                  isLast: true,
                ),
            ],
          ),

          const SizedBox(height: 32),
          _buildSectionHeader("UI 기본 설정 (UI DEFAULTS)"),
          const SizedBox(height: 12),
          _buildSettingsGroup(
            children: [
              _buildSettingsItem(
                title: l10n.language,
                value: _settings.localeCode == 'ko' ? "한국어" : "ENGLISH",
                icon: Icons.language_rounded,
                iconColor: Colors.blue,
                onTap: _showLanguageSelector,
              ),
              _buildSettingsItem(
                title: l10n.terminalFontSize,
                value: "${_settings.terminalFontSize.toInt()} PX",
                icon: Icons.text_fields_rounded,
                iconColor: Colors.grey[400]!,
                valueColor: Colors.white,
                onTap: _showFontSizeSelector,
              ),
              _buildSettingsItem(
                title: l10n.trackpadSensitivity,
                value: "${_settings.trackpadSensitivity}X",
                icon: Icons.mouse_rounded,
                iconColor: Colors.grey[400]!,
                valueColor: Colors.white,
                onTap: _showTrackpadSensitivitySelector,
                isLast: true,
              ),
            ],
          ),

          const SizedBox(height: 48),
          _buildSectionHeader(l10n.appReset, color: Colors.red[800]),
          const SizedBox(height: 12),
          _buildDangerGroup(),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: color ?? Colors.grey[600],
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.5,
      ),
    );
  }

  Widget _buildSettingsGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x4D18181B), // Zinc-900 at 30%
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xCC27272A)), // Zinc-800 at 80%
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsItem({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    Color? valueColor,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            isLast ? 16 : 0,
          ), // Adjust ripple for last item
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.grey[300],
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          style: GoogleFonts.jetBrainsMono(
                            color:
                                valueColor ?? iconColor.withValues(alpha: 0.9),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey[700],
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isLast) Container(height: 1, color: Colors.grey[900]),
      ],
    );
  }

  Widget _buildDangerGroup() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red[900]!.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[900]!.withValues(alpha: 0.5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: InkWell(
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => CyberAlertDialog(
                  title: "CRITICAL_RESET",
                  titleColor: Colors.red,
                  borderColor: Colors.red[900]!,
                  content: const Text(
                    "Terminate all persistent links and system configurations?",
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text(
                        "ABORT",
                        style: TextStyle(color: AppColors.textGrey),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        "EXECUTE",
                        style: TextStyle(
                          color: Colors.red[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _settings.clearAll();
                if (!mounted) return;
                Navigator.pop(context);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red[600],
                    size: 22,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    "모든 데이터 지우기",
                    style: GoogleFonts.inter(
                      color: Colors.red[100],
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            "FORGET_INTENTS",
                            style: GoogleFonts.jetBrainsMono(
                              color: Colors.red[600],
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.red[900],
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
