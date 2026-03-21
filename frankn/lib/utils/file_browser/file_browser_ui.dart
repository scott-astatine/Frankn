import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class FileBrowserAppBar {
  static AppBar buildDefault({
    required BuildContext context,
    required String currentPath,
    required bool isGridView,
    required VoidCallback onToggleView,
    required VoidCallback onSearch,
    required VoidCallback onNavigateUp,
    required Function(String) onSort,
    int selectedCount = 0,
    VoidCallback? onDeleteSelected,
    VoidCallback? onDownloadSelected,
    VoidCallback? onClearSelection,
  }) {
    final l10n = AppLocalizations.of(context)!;

    if (selectedCount > 0) {
      return AppBar(
        title: Text("$selectedCount ${l10n.selected.toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        backgroundColor: AppColors.voidBlack,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: onClearSelection),
        actions: [
          IconButton(icon: const Icon(Icons.download, color: AppColors.neonCyan), onPressed: onDownloadSelected),
          IconButton(icon: const Icon(Icons.delete, color: AppColors.errorRed), onPressed: onDeleteSelected),
        ],
      );
    }

    return AppBar(
      title: Text(l10n.fileBrowser.toUpperCase().replaceAll(" ", "_"), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      backgroundColor: AppColors.voidBlack,
      actions: [
        IconButton(icon: Icon(isGridView ? Icons.view_list : Icons.grid_view, size: 20, color: AppColors.neonCyan), onPressed: onToggleView),
        IconButton(icon: const Icon(Icons.search, size: 20, color: AppColors.neonCyan), onPressed: onSearch),
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort, color: AppColors.neonCyan, size: 20),
          onSelected: onSort,
          color: const Color(0xFF0F0F0F),
          itemBuilder: (context) => [
            PopupMenuItem(value: "name", child: Text(l10n.sortByName.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
            PopupMenuItem(value: "size", child: Text(l10n.sortBySize.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
            PopupMenuItem(value: "modified", child: Text(l10n.sortByDate.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          ],
        ),
        IconButton(icon: const Icon(Icons.drive_file_move_rtl, size: 20), onPressed: onNavigateUp),
      ],
    );
  }

  static Widget buildBreadcrumbs({required String path, required Function(String) onBreadcrumbTap}) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    List<String> breadcrumbs = ["/"];
    String currentAccumulated = "/";
    for (var part in parts) {
      currentAccumulated += "$part/";
      breadcrumbs.add(currentAccumulated);
    }

    return Container(
      height: 32, padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(color: Colors.black, border: Border(bottom: BorderSide(color: Colors.white10))),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: breadcrumbs.length,
        separatorBuilder: (_, index) => const Icon(Icons.chevron_right, size: 14, color: Colors.white24),
        itemBuilder: (context, index) {
          final isLast = index == breadcrumbs.length - 1;
          final l10n = AppLocalizations.of(context)!;
          final label = index == 0 ? l10n.root : parts[index - 1]; 
          return TextButton(
            onPressed: isLast ? null : () => onBreadcrumbTap(breadcrumbs[index]),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(label, style: TextStyle(fontFamily: 'JetBrainsMonoNerdFont', fontSize: 10, fontWeight: isLast ? FontWeight.w900 : FontWeight.bold, color: isLast ? AppColors.neonCyan : AppColors.textGrey)),
          );
        },
      ),
    );
  }
}