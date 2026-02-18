/// File browser UI components and builders.
///
/// Contains reusable UI components for the file browser including
/// app bars, dialogs, and navigation elements.
library;

import 'package:flutter/material.dart';
import 'package:frankn/utils/file_browser/file_browser_utils.dart';
import 'package:frankn/utils/utils.dart';

/// UI builders for file browser app bars.
class FileBrowserAppBar {
  /// Builds the default app bar with navigation and controls.
  static AppBar buildDefault({
    required String currentPath,
    required SortOption sortBy,
    required bool showHidden,
    required VoidCallback onSearch,
    required Function(SortOption) onSortChanged,
    required VoidCallback onToggleHidden,
    required VoidCallback onNavigateUp,
  }) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "FILE BROWSER",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          Text(
            currentPath,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textGrey,
              fontFamily: 'Courier',
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.deepSpace,
      actions: [
        _buildSearchButton(onSearch),
        _buildSortMenu(sortBy, onSortChanged),
        _buildVisibilityToggle(showHidden, onToggleHidden),
        _buildBackButton(onNavigateUp),
      ],
    );
  }

  /// Builds the selection mode app bar.
  static AppBar buildSelection({
    required int selectedCount,
    required VoidCallback onClearSelection,
    required VoidCallback onBulkDownload,
    required VoidCallback onBulkDelete,
  }) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: onClearSelection,
      ),
      title: Text(
        "$selectedCount SELECTED",
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.neonCyan,
        ),
      ),
      backgroundColor: AppColors.deepSpace,
      actions: [
        IconButton(
          icon: const Icon(Icons.download, color: AppColors.neonCyan),
          onPressed: onBulkDownload,
        ),
        IconButton(
          icon: const Icon(Icons.delete_forever, color: AppColors.errorRed),
          onPressed: onBulkDelete,
        ),
      ],
    );
  }

  /// Builds the search mode app bar.
  static AppBar buildSearch({
    required TextEditingController controller,
    required String searchQuery,
    required VoidCallback onExitSearch,
    required Function(String) onQueryChanged,
  }) {
    return AppBar(
      backgroundColor: AppColors.deepSpace,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.neonCyan),
        onPressed: onExitSearch,
      ),
      title: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontFamily: 'Courier',
        ),
        decoration: const InputDecoration(
          hintText: "SEARCH IN DIRECTORY...",
          hintStyle: TextStyle(color: AppColors.textGrey, fontSize: 12),
          border: InputBorder.none,
        ),
        onChanged: onQueryChanged,
      ),
      actions: [
        if (searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear, color: AppColors.textGrey),
            onPressed: () {
              controller.clear();
              onQueryChanged("");
            },
          ),
      ],
    );
  }

  static Widget _buildSearchButton(VoidCallback onPressed) {
    return IconButton(
      icon: const Icon(Icons.search, size: 20, color: AppColors.neonCyan),
      onPressed: onPressed,
    );
  }

  static Widget _buildVisibilityToggle(
    bool showHidden,
    VoidCallback onPressed,
  ) {
    return IconButton(
      icon: Icon(
        showHidden ? Icons.visibility : Icons.visibility_off,
        size: 20,
      ),
      onPressed: onPressed,
    );
  }

  static Widget _buildBackButton(VoidCallback onPressed) {
    return IconButton(
      icon: const Icon(Icons.drive_file_move_rtl),
      onPressed: onPressed,
    );
  }

  static PopupMenuButton<SortOption> _buildSortMenu(
    SortOption currentSort,
    Function(SortOption) onSelected,
  ) {
    return PopupMenuButton<SortOption>(
      icon: const Icon(Icons.sort, size: 20),
      onSelected: onSelected,
      itemBuilder: (context) => SortOption.values.map((option) {
        return PopupMenuItem(value: option, child: Text(option.label));
      }).toList(),
    );
  }
}

/// Dialog builders for file browser operations.
class FileBrowserDialogs {
  /// Shows bulk delete confirmation dialog.
  static Future<bool?> showBulkDelete(
    BuildContext context,
    int itemCount,
  ) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelGrey,
        shape: const BeveledRectangleBorder(
          side: BorderSide(color: AppColors.errorRed, width: 1),
        ),
        title: const Text(
          "CONFIRM DELETION",
          style: TextStyle(
            color: AppColors.errorRed,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          "Permanently delete $itemCount items from host?",
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("DELETE ALL"),
          ),
        ],
      ),
    );
  }

  /// Shows single file delete confirmation dialog.
  static Future<bool> showSingleDelete(
    BuildContext context,
    String filename,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.panelGrey,
            shape: const BeveledRectangleBorder(
              side: BorderSide(color: AppColors.errorRed, width: 1),
            ),
            title: const Text(
              "DELETE FILE?",
              style: TextStyle(
                color: AppColors.errorRed,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              "Are you sure you want to delete '$filename'?",
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "CANCEL",
                  style: TextStyle(color: AppColors.textGrey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.errorRed,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("DELETE"),
              ),
            ],
          ),
        ) ??
        false;
  }
}
