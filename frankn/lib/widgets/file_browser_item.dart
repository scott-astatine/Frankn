import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';

class FileBrowserItem extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String fullPath;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onDoubleTap;
  final Function(String) onDelete;
  final Function(String) onDownload;
  final Function(String, String) onEdit;
  final Function(String, String) onViewImage;

  const FileBrowserItem({
    super.key,
    required this.entry,
    required this.fullPath,
    this.isSelected = false,
    this.selectionMode = false,
    required this.onTap,
    required this.onLongPress,
    this.onDoubleTap,
    required this.onDelete,
    required this.onDownload,
    required this.onEdit,
    required this.onViewImage,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDir = entry['is_dir'] ?? false;
    final bool isSymlink = entry['is_symlink'] ?? false;
    final String name = entry['name'] ?? 'Unknown';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.neonCyan.withValues(alpha: 0.1)
            : AppColors.panelGrey.withValues(alpha: 0.4),
        border: Border.all(
          color: isSelected
              ? AppColors.neonCyan
              : AppColors.neonCyan.withValues(alpha: 0.1),
          width: isSelected ? 1 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: GestureDetector(
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: ListTile(
          dense: true,
          onTap: onTap,
          leading: selectionMode && !isDir
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => onTap(),
                  activeColor: AppColors.neonCyan,
                  checkColor: Colors.black,
                  side: const BorderSide(color: AppColors.neonCyan),
                )
              : _buildIcon(isDir, isSymlink, name),
          title: Text(
            name,
            style: TextStyle(
              color: isSelected ? AppColors.neonCyan : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: isDir
              ? null
              : Text(
                  FileUtils.formatSize(entry['size'] as int),
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 10,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.bold,
                  ),
                ),
          trailing: selectionMode ? null : _buildActions(isDir, context),
        ),
      ),
    );
  }

  Widget _buildIcon(bool isDir, bool isSymlink, String name) {
    return Stack(
      children: [
        Icon(
          isDir ? Icons.folder : FileUtils.getFileIcon(name),
          color: isDir ? AppColors.cyberYellow : AppColors.neonCyan,
          size: 24,
        ),
        if (isSymlink)
          const Positioned(
            bottom: 0,
            right: 0,
            child: Icon(Icons.shortcut, color: Colors.white, size: 12),
          ),
      ],
    );
  }

  Widget _buildActions(bool isDir, BuildContext context) {
    final String name = entry['name'] ?? '';
    final bool isImg = _isImage(name);
    final bool isText = _canViewAsText(name);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, color: AppColors.textGrey, size: 20),
      color: AppColors.panelGrey,
      shape: const BeveledRectangleBorder(
        side: BorderSide(color: AppColors.neonCyan, width: 0.5),
      ),
      onSelected: (value) {
        if (value == 'delete') onDelete(fullPath);
        if (value == 'download') onDownload(fullPath);
        if (value == 'edit' || value == 'view_text') onEdit(fullPath, name);
        if (value == 'view_image') onViewImage(fullPath, name);
      },
      itemBuilder: (context) => [
        if (!isDir && isText)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit, color: AppColors.cyberYellow, size: 18),
                SizedBox(width: 8),
                Text(
                  'EDIT',
                  style: TextStyle(
                    color: AppColors.cyberYellow,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        if (!isDir && isImg)
          const PopupMenuItem(
            value: 'view_image',
            child: Row(
              children: [
                Icon(Icons.image, color: AppColors.neonCyan, size: 18),
                SizedBox(width: 8),
                Text(
                  'OPEN',
                  style: TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        if (!isDir && !isImg && !isText)
          const PopupMenuItem(
            value: 'view_text',
            child: Row(
              children: [
                Icon(Icons.article, color: AppColors.textGrey, size: 18),
                SizedBox(width: 8),
                Text(
                  'OPEN AS TEXT',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        if (!isDir)
          const PopupMenuItem(
            value: 'download',
            child: Row(
              children: [
                Icon(Icons.download, color: AppColors.neonCyan, size: 18),
                SizedBox(width: 8),
                Text(
                  'DOWNLOAD',
                  style: TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_forever, color: AppColors.errorRed, size: 18),
              SizedBox(width: 8),
              Text(
                'DELETE',
                style: TextStyle(
                  color: AppColors.errorRed,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isImage(String name) {
    final ext = name.split('.').last.toLowerCase();
    return {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext);
  }

  bool _canViewAsText(String name) {
    final ext = name.split('.').last.toLowerCase();
    const textExtensions = {
      'txt',
      'rs',
      'dart',
      'py',
      'js',
      'sh',
      'json',
      'yaml',
      'yml',
      'md',
      'cpp',
      'hpp',
      'h',
      'c',
      'java',
      'xml',
      'html',
      'css',
      'toml',
      'conf',
      'service',
      'log',
      'lock',
      'gitignore',
    };
    return textExtensions.contains(ext) || !name.contains('.');
  }
}
