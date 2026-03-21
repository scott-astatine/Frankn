import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class FileBrowserItem extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool isGrid;
  final String fullPath;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(String) onDelete;
  final Function(String) onDownload;
  final Function(String, String) onEdit;
  final Function(String, String) onViewImage;

  const FileBrowserItem({
    super.key, required this.entry, required this.isGrid, required this.fullPath,
    this.isSelected = false, required this.onTap, required this.onLongPress,
    required this.onDelete, required this.onDownload, required this.onEdit, required this.onViewImage,
  });

  void _showContextMenu(BuildContext context) {
    final bool isDir = entry['is_dir'] ?? false;
    final String name = entry['name'] ?? 'UNKNOWN';
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Color(0xFF0F0F0F), borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)), border: Border(top: BorderSide(color: Colors.white10, width: 2))),
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${l10n.intentHandler.toUpperCase()} // ${name.toUpperCase()}", style: const TextStyle(color: AppColors.neonCyan, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
            const SizedBox(height: 24),
            Row(
              children: [
                if (!isDir) ...[
                  Expanded(child: Padding(padding: const EdgeInsets.only(right: 4), child: CyberButton(text: l10n.download.toUpperCase(), isSmall: true, onPressed: () { Navigator.pop(context); onDownload(fullPath); }))),
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: CyberButton(text: l10n.edit.toUpperCase(), isSmall: true, onPressed: () { Navigator.pop(context); onEdit(fullPath, name); }))),
                ],
                Expanded(child: Padding(padding: EdgeInsets.only(left: isDir ? 0 : 4), child: CyberButton(text: l10n.delete.toUpperCase(), variant: CyberButtonVariant.destructive, isSmall: true, onPressed: () { Navigator.pop(context); onDelete(fullPath); }))),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDir = entry['is_dir'] ?? false;
    final String name = entry['name'] ?? 'UNKNOWN';
    final l10n = AppLocalizations.of(context)!;
    final String sizeStr = isDir ? l10n.directory.toUpperCase() : FileUtils.formatSize(entry['size'] as int);
    final String modified = entry['modified'] ?? "00:00:00";
    final Color color = isDir ? AppColors.cyberYellow : AppColors.neonCyan;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap, onLongPress: onLongPress, borderRadius: BorderRadius.circular(16),
          child: CyberCard(
            borderColor: isSelected ? AppColors.neonCyan : (color.withValues(alpha: 0.1)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: isSelected ? AppColors.neonCyan.withValues(alpha: 0.2) : color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                    child: Icon(isSelected ? Icons.check : (isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined), color: isSelected ? AppColors.neonCyan : color, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Row(children: [
                          Text(sizeStr, style: const TextStyle(fontFamily: 'JetBrainsMonoNerdFont', fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white24)),
                          const SizedBox(width: 8), const Text("::", style: TextStyle(color: Colors.white10, fontSize: 8)), const SizedBox(width: 8),
                          Text(modified, style: const TextStyle(fontFamily: 'JetBrainsMonoNerdFont', fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white24)),
                        ]),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.more_vert, color: Colors.white10, size: 20), onPressed: () => _showContextMenu(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
