import 'package:flutter/material.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/main.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/utils/cyber_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _client = RtcClient();

  void _showLanguageSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.neonCyan, width: 1.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSelectorTile("ENGLISH", _settings.localeCode == 'en', () async {
              await _settings.setLocaleCode('en');
              appLocale.value = const Locale('en');
              if (!context.mounted) return;
              Navigator.pop(context);
              setState(() {});
            }),
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
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
      trailing: isSelected ? const Icon(Icons.check, color: AppColors.neonCyan) : null,
      onTap: onTap,
    );
  }

  void _showFontSizeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.neonCyan, width: 1.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [10, 12, 13, 14, 16, 18, 20].map((size) => ListTile(
            title: Text("$size PX", style: const TextStyle(fontWeight: FontWeight.w900, fontFamily: 'JetBrainsMonoNerdFont')),
            trailing: _settings.terminalFontSize == size.toDouble() ? const Icon(Icons.check, color: AppColors.neonCyan) : null,
            onTap: () async {
              await _settings.setTerminalFontSize(size.toDouble());
              if (!context.mounted) return;
              Navigator.pop(context);
              setState(() {});
            },
          )).toList(),
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
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.neonCyan)),
        title: const Text("RENAME_HOST", style: TextStyle(color: AppColors.neonCyan, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.neonCyan)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ABORT", style: TextStyle(color: AppColors.textGrey))),
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
            child: const Text("UPDATE", style: TextStyle(color: AppColors.neonCyan, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _editSignalingUrl() {
    final controller = TextEditingController(text: _settings.signalingUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.neonCyan)),
        title: const Text("SIGNALING_SERVER", style: TextStyle(color: AppColors.neonCyan, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.neonCyan)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ABORT", style: TextStyle(color: AppColors.textGrey))),
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
                    content: Text('Re-initializing Neural Link to new server...', style: TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: AppColors.matrixGreen,
                  ),
                );
              } else {
                 ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid URL format. Must start with ws:// or wss://', style: TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: AppColors.errorRed,
                  ),
                );
              }
            },
            child: const Text("UPDATE", style: TextStyle(color: AppColors.neonCyan, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      appBar: AppBar(
        title: Text(l10n.settings.toUpperCase(), 
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader(l10n.neuralLinkConfiguration),
          const SizedBox(height: 12),
          if (_client.currentHostId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildSettingCard(
                title: "ACTIVE_HOST_ALIAS",
                value: _client.currentHostName?.toUpperCase() ?? "UNKNOWN",
                icon: Icons.edit_note_outlined,
                onTap: _renameHost,
                accentColor: AppColors.neonCyan,
              ),
            ),
          _buildSettingCard(
            title: l10n.signalingServer.toUpperCase(),
            value: _settings.signalingUrl,
            icon: Icons.hub_outlined,
            onTap: _editSignalingUrl,
            accentColor: AppColors.neonPink,
          ),
          
          const SizedBox(height: 32),
          _buildSectionHeader(l10n.uiPreferences),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _buildOpSettingCard(l10n.language.toUpperCase(), _settings.localeCode == 'ko' ? "한국어" : "ENGLISH", Icons.language, _showLanguageSelector),
              _buildOpSettingCard(l10n.terminalFontSize.toUpperCase(), "${_settings.terminalFontSize.toInt()} PX", Icons.format_size, _showFontSizeSelector),
            ],
          ),

          const SizedBox(height: 32),
          _buildSectionHeader(l10n.appReset),
          const SizedBox(height: 12),
          _buildSettingCard(
            title: l10n.clearAllData.toUpperCase(),
            value: "FORGET_ALL_INTENTS",
            icon: Icons.delete_forever_outlined,
            accentColor: AppColors.errorRed,
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF0F0F0F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.errorRed)),
                  title: const Text("CRITICAL_RESET"),
                  content: const Text("Terminate all persistent links and system configurations?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ABORT")),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("EXECUTE", style: TextStyle(color: AppColors.errorRed))),
                  ],
                ),
              );
              if (confirm == true) {
                await _settings.clearAll();
                if (!context.mounted) return;
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2));
  }

  Widget _buildSettingCard({required String title, required String value, required IconData icon, required VoidCallback onTap, Color accentColor = Colors.white24}) {
    return CyberCard(
      borderColor: accentColor.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: accentColor == Colors.white24 ? Colors.white38 : accentColor, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpSettingCard(String title, String value, IconData icon, VoidCallback onTap) {
    return CyberCard(
      borderColor: Colors.white.withValues(alpha: 0.05),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.neonCyan, size: 22),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
