import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class FileBrowserItem extends StatelessWidget {
  final RemoteEntry entry;
  final bool isGrid;
  final String fullPath;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(String) onDelete;
  final Function(String, int) onDownload;
  final Function(String, int) onSaveAs;
  final Function(String, String) onEdit;
  final Function(String, String) onViewImage;

  const FileBrowserItem({
    super.key,
    required this.entry,
    required this.isGrid,
    required this.fullPath,
    this.isSelected = false,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onDownload,
    required this.onSaveAs,
    required this.onEdit,
    required this.onViewImage,
  });

  void _showContextMenu(BuildContext context) {
    final bool isDir = entry.isDir;
    final String name = entry.name;
    final int size = entry.size;
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              border: Border(
                top: BorderSide(
                  color: AppColors.neonCyan.withValues(alpha: 0.8),
                  width: 2,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${l10n.intentHandler.toUpperCase()} // ${name.toUpperCase()}",
                  style: const TextStyle(
                    color: AppColors.neonCyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 2,
                    fontFamily: 'JetBrainsMonoNerdFont',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isDir ? Icons.folder_open_rounded : Icons.insert_drive_file_outlined,
                      color: isDir ? AppColors.neonCyan.withValues(alpha: 0.6) : AppColors.neonPink.withValues(alpha: 0.6),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isDir ? "DIRECTORY" : FileUtils.formatSize(size),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontFamily: 'JetBrainsMonoNerdFont',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "SYS_RESRC: LOCAL_FS",
                      style: TextStyle(
                        color: AppColors.textGrey.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontFamily: 'JetBrainsMonoNerdFont',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Column(
                  children: [
                    if (!isDir) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: CyberButton(
                                text: l10n.download.toUpperCase(),
                                icon: Icons.download_for_offline_rounded,
                                isSmall: true,
                                onPressed: () {
                                  Navigator.pop(context);
                                  onDownload(fullPath, size);
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: CyberButton(
                                text: l10n.saveAs.toUpperCase(),
                                icon: Icons.drive_file_move_rounded,
                                isSmall: true,
                                onPressed: () {
                                  Navigator.pop(context);
                                  onSaveAs(fullPath, size);
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: CyberButton(
                                text: l10n.edit.toUpperCase(),
                                icon: Icons.edit_note_rounded,
                                isSmall: true,
                                onPressed: () {
                                  Navigator.pop(context);
                                  onEdit(fullPath, name);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: CyberButton(
                            text: l10n.delete.toUpperCase(),
                            icon: Icons.delete_forever_rounded,
                            variant: CyberButtonVariant.destructive,
                            isSmall: true,
                            onPressed: () {
                              Navigator.pop(context);
                              onDelete(fullPath);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDir = entry.isDir;
    final String name = entry.name;
    final l10n = AppLocalizations.of(context)!;
    final String sizeStr = isDir
        ? l10n.directory.toUpperCase()
        : FileUtils.formatSize(entry.size);
    final String modified = entry.modified;
    final Color color = isDir ? AppColors.cyberYellow : AppColors.neonCyan;

    return Padding(
      padding: isGrid
          ? const EdgeInsets.all(4.0)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: CyberCard(
            borderColor: isSelected
                ? AppColors.neonCyan
                : (color.withValues(alpha: 0.1)),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: isGrid ? _buildGrid(color, name, sizeStr) : _buildList(color, name, sizeStr, modified, context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(Color color, String name, String sizeStr) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.neonCyan.withValues(alpha: 0.2)
                : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isSelected
                ? Icons.check
                : (entry.isDir
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined),
            color: isSelected ? AppColors.neonCyan : color,
            size: 28,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sizeStr,
          style: const TextStyle(
            fontFamily: 'JetBrainsMonoNerdFont',
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: Colors.white24,
          ),
        ),
      ],
    );
  }

  Widget _buildList(Color color, String name, String sizeStr, String modified, BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.neonCyan.withValues(alpha: 0.2)
                : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isSelected
                ? Icons.check
                : (entry.isDir
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined),
            color: isSelected ? AppColors.neonCyan : color,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    sizeStr,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMonoNerdFont',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white24,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "::",
                    style: TextStyle(
                      color: Colors.white10,
                      fontSize: 8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    modified,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMonoNerdFont',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white24,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.more_vert,
            color: Colors.white10,
            size: 20,
          ),
          onPressed: () => _showContextMenu(context),
        ),
      ],
    );
  }

  bool isDirIcon(RemoteEntry entry) => entry.isDir;
}
