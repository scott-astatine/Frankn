import 'package:flutter/material.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class FileBrowserAppBar {
  static Widget buildDefaultContent({
    required BuildContext context,
    required String currentPath,
    required bool isGridView,
    required VoidCallback onToggleView,
    required VoidCallback onSearch,
    required VoidCallback onNavigateUp,
    required Function(String) onSort,
    required bool showHidden,
    required VoidCallback onToggleShowHidden,
    VoidCallback? onUpload,
    int selectedCount = 0,
    VoidCallback? onDeleteSelected,
    VoidCallback? onDownloadSelected,
    VoidCallback? onClearSelection,
    bool isSearching = false,
    TextEditingController? searchController,
    Function(String)? onSearchChanged,
    VoidCallback? onExitSearch,
  }) {
    final l10n = AppLocalizations.of(context)!;

    if (selectedCount > 0) {
      return Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.neonCyan),
            onPressed: onClearSelection,
          ),
          Expanded(
            child: Text(
              "$selectedCount ${l10n.selected.toUpperCase()}",
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: AppColors.textWhite,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download, color: AppColors.neonCyan),
            onPressed: onDownloadSelected,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: AppColors.errorRed),
            onPressed: onDeleteSelected,
          ),
        ],
      );
    }

    if (isSearching) {
      return Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.neonCyan),
            onPressed: onExitSearch,
          ),
          Expanded(
            child: TextField(
              controller: searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: l10n.search.toUpperCase(),
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                border: InputBorder.none,
              ),
              onChanged: onSearchChanged,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: AppColors.neonCyan),
            onPressed: () {
              searchController?.clear();
              onSearchChanged?.call("");
            },
          ),
        ],
      );
    }

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.neonCyan),
          onPressed: () => Navigator.pop(context),
        ),
        Expanded(
          child: Text(
            l10n.fileBrowser.toUpperCase().replaceAll(" ", "_"),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: AppColors.neonCyan,
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            isGridView ? Icons.view_list : Icons.grid_view,
            size: 20,
            color: AppColors.neonCyan,
          ),
          onPressed: onToggleView,
        ),
        IconButton(
          icon: const Icon(Icons.search, size: 20, color: AppColors.neonCyan),
          onPressed: onSearch,
        ),
        PopupMenuButton<String>(
          icon: const Icon(
            Icons.more_vert,
            color: AppColors.neonCyan,
            size: 20,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: AppColors.neonCyan.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          onSelected: (val) {
            if (val == "upload") {
              onUpload?.call();
            } else if (val == "toggle_hidden") {
              onToggleShowHidden();
            } else {
              onSort(val);
            }
          },
          color: AppColors.voidBlack,
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              height: 32,
              child: Text(
                "[CONSOLE_ACTIONS]",
                style: TextStyle(
                  color: AppColors.neonCyan.withValues(alpha: 0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  fontFamily: 'JetBrainsMonoNerdFont',
                ),
              ),
            ),
            const PopupMenuDivider(height: 8),
            PopupMenuItem(
              value: "name",
              child: Row(
                children: [
                  const Icon(
                    Icons.sort_by_alpha,
                    color: AppColors.neonCyan,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.sortByName.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontFamily: 'JetBrainsMonoNerdFont',
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: "size",
              child: Row(
                children: [
                  const Icon(
                    Icons.analytics_outlined,
                    color: AppColors.neonCyan,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.sortBySize.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontFamily: 'JetBrainsMonoNerdFont',
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: "modified",
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    color: AppColors.neonCyan,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.sortByDate.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontFamily: 'JetBrainsMonoNerdFont',
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(height: 8),
            PopupMenuItem(
              value: "toggle_hidden",
              child: Row(
                children: [
                  Icon(
                    showHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: AppColors.cyberYellow,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    showHidden ? "HIDE HIDDEN FILES" : "SHOW HIDDEN FILES",
                    style: const TextStyle(
                      color: AppColors.cyberYellow,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontFamily: 'JetBrainsMonoNerdFont',
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(height: 8),
            PopupMenuItem(
              value: "upload",
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_upload_outlined,
                    color: AppColors.neonPink,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "UPLOAD FILE",
                    style: TextStyle(
                      color: AppColors.neonPink,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontFamily: 'JetBrainsMonoNerdFont',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.drive_file_move_rtl, size: 20),
          onPressed: onNavigateUp,
        ),
      ],
    );
  }

  static Widget buildBreadcrumbs({
    required String path,
    required Function(String) onBreadcrumbTap,
  }) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    List<String> breadcrumbs = ["/"];
    String currentAccumulated = "/";
    for (var part in parts) {
      currentAccumulated += "$part/";
      breadcrumbs.add(currentAccumulated);
    }

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.voidBlack,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: breadcrumbs.length,
        separatorBuilder: (_, index) =>
            const Icon(Icons.chevron_right, size: 14, color: Colors.white24),
        itemBuilder: (context, index) {
          final isLast = index == breadcrumbs.length - 1;
          final l10n = AppLocalizations.of(context)!;
          final label = index == 0 ? l10n.root : parts[index - 1];
          return TextButton(
            onPressed: isLast
                ? null
                : () => onBreadcrumbTap(breadcrumbs[index]),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'JetBrainsMonoNerdFont',
                fontSize: 10,
                fontWeight: isLast ? FontWeight.w900 : FontWeight.bold,
                color: isLast ? AppColors.neonCyan : AppColors.textGrey,
              ),
            ),
          );
        },
      ),
    );
  }
}
