import 'package:flutter/material.dart';
import 'package:frankn/screens/code_editor_screen.dart';
import 'package:frankn/screens/image_viewer_screen.dart';
import 'package:frankn/services/file_transfer_mixin.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/file_browser/file_browser_state.dart';
import 'package:frankn/utils/file_browser/file_browser_ui.dart';
import 'package:frankn/utils/file_browser/file_browser_utils.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/file_browser_item.dart';

/// File browser screen for navigating and managing remote files.
///
/// This screen acts as the "View" in the MVVM-like architecture.
/// It observes [FileBrowserState] and rebuilds when state changes.
///
/// INTEGRATION:
/// - [FileTransferMixin]: Provides `downloadFile`, `uploadFile` methods.
/// - [FileBrowserState]: Holds the data (path, entries, selection).
/// - [RtcClient]: Used to send commands like `DeleteFile`.
class FileBrowserScreen extends StatefulWidget {
  final RtcClient client;
  const FileBrowserScreen({super.key, required this.client});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen>
    with FileTransferMixin {
  @override
  RtcClient get client => widget.client;

  late final FileBrowserState _browserState;

  // ================== LIFECYCLE ==================

  @override
  void initState() {
    super.initState();
    // Initialize the state manager and subscribe to updates
    _browserState = FileBrowserState(widget.client);
    _browserState.addListener(_onStateChanged);
    
    // Trigger initial directory fetch
    _browserState.refreshDirectory();
    
    // Initialize file transfer listeners (from Mixin)
    setupTransferListener();
  }

  @override
  void dispose() {
    _browserState.removeListener(_onStateChanged);
    _browserState.dispose();
    super.dispose();
  }

  // Trigger UI rebuild when state changes
  void _onStateChanged() => setState(() {});

  // ================== API ==================

  @override
  void refreshDirectory() => _browserState.refreshDirectory();

  // ================== DATA OPERATIONS ==================

  void _toggleSelection(String path) => _browserState.toggleSelection(path);

  void _navigateUp() => _browserState.navigateUp();

  void _navigateDown(String directoryName) =>
      _browserState.navigateDown(directoryName);

  // ================== BULK ACTIONS ==================

  Future<void> _bulkDelete() async {
    final confirmed = await FileBrowserDialogs.showBulkDelete(
      context,
      _browserState.selectedPaths.length,
    );
    if (confirmed == true) {
      for (final path in _browserState.selectedPaths) {
        widget.client.sendDcMsg({DcMsg.Key: DcMsg.DeleteFile, "path": path});
      }
      _browserState.refreshDirectory();
    }
  }

  Future<void> _bulkDownload() async {
    // Sequentially download each selected file
    for (final path in _browserState.selectedPaths) {
      await downloadFile(path);
    }
    _browserState.clearSelection();
  }

  void _deleteFile(String path, String name) async {
    final confirmed = await FileBrowserDialogs.showSingleDelete(context, name);
    if (confirmed) {
      widget.client.sendDcMsg({DcMsg.Key: DcMsg.DeleteFile, "path": path});
      _browserState.refreshDirectory();
    }
  }

  // ================== UI BUILDERS ==================

  @override
  Widget build(BuildContext context) {
    // Intercept back button to navigate up directory tree first
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _navigateUp();
          // If at root, actually pop the screen
          if (_browserState.currentPath == "/" ||
              _browserState.currentPath == "/home/") {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.voidBlack,
        appBar: _buildAppBar(),
        floatingActionButton: _buildFloatingActionButton(),
        body: Column(
          children: [
            if (_browserState.isLoading) _buildProgressIndicator(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    // Show Selection AppBar if items are selected
    if (_browserState.selectedPaths.isNotEmpty) {
      return FileBrowserAppBar.buildSelection(
        selectedCount: _browserState.selectedPaths.length,
        onClearSelection: _browserState.clearSelection,
        onBulkDownload: _bulkDownload,
        onBulkDelete: _bulkDelete,
      );
    }
    // Show Search AppBar if searching
    if (_browserState.isSearching) {
      return FileBrowserAppBar.buildSearch(
        controller: _browserState.searchController,
        searchQuery: _browserState.searchQuery,
        onExitSearch: _browserState.exitSearch,
        onQueryChanged: (query) {
          _browserState.setSearchQuery(query);
        },
      );
    }
    // Default AppBar with navigation controls
    return FileBrowserAppBar.buildDefault(
      currentPath: _browserState.currentPath,
      sortBy: _browserState.sortBy,
      showHidden: _browserState.showHidden,
      onSearch: () => _browserState.setIsSearching(true),
      onSortChanged: (sort) {
        _browserState.setSortBy(sort);
        _browserState.refreshDirectory();
      },
      onToggleHidden: () {
        _browserState.setShowHidden(!_browserState.showHidden);
        _browserState.refreshDirectory();
      },
      onNavigateUp: _navigateUp,
    );
  }

  Widget _buildFloatingActionButton() {
    if (_browserState.selectedPaths.isNotEmpty) return const SizedBox.shrink();
    return FloatingActionButton(
      onPressed: () => uploadFile(_browserState.currentPath),
      backgroundColor: AppColors.cyberYellow,
      child: const Icon(Icons.upload_file, color: AppColors.voidBlack),
    );
  }

  Widget _buildProgressIndicator() {
    return Column(
      children: [
        LinearProgressIndicator(
          backgroundColor: Colors.transparent,
          valueColor: const AlwaysStoppedAnimation(AppColors.neonCyan),
          minHeight: 2,
          value: _browserState.transferProgress > 0 ? _browserState.transferProgress : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            _browserState.transferMessage,
            style: const TextStyle(
              color: AppColors.neonCyan,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_browserState.isLoading && _browserState.entries.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.neonCyan),
      );
    }

    final filteredEntries = _browserState.getFilteredEntries();

    if (filteredEntries.isEmpty) {
      return const Center(
        child: Text(
          "NO DATA",
          style: TextStyle(color: AppColors.textGrey, letterSpacing: 2),
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredEntries.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) =>
          _buildFileItem(filteredEntries[index], index),
    );
  }

  Widget _buildFileItem(dynamic entry, int index) {
    final name = entry['name'];
    final fullPath = PathHelper.join(_browserState.currentPath, name);
    final isSelected = _browserState.isSelected(fullPath);
    final isDirectory = entry['is_dir'];

    return FileBrowserItem(
      entry: entry,
      fullPath: fullPath,
      isSelected: isSelected,
      selectionMode: _browserState.selectedPaths.isNotEmpty,
      onTap: () => _handleItemTap(entry, name, fullPath, isDirectory),
      onLongPress: () {
        if (!isDirectory) _toggleSelection(fullPath);
      },
      onDoubleTap: () =>
          _handleItemDoubleTap(entry, name, fullPath, isDirectory),
      onDelete: (path) => _deleteFile(path, name),
      onDownload: (path) => downloadFile(path),
      onEdit: (path, name) => _openCodeEditor(path, name),
      onViewImage: (path, name) => _openImageViewer(path, name),
    );
  }

  void _handleItemTap(
    dynamic entry,
    String name,
    String fullPath,
    bool isDirectory,
  ) {
    // If in selection mode, tap toggles selection (files only)
    if (_browserState.selectedPaths.isNotEmpty) {
      if (!isDirectory) _toggleSelection(fullPath);
      return;
    }
    // Otherwise navigate into directory
    if (isDirectory) {
      _navigateDown(name);
    }
  }

  void _handleItemDoubleTap(
    dynamic entry,
    String name,
    String fullPath,
    bool isDirectory,
  ) {
    if (_browserState.selectedPaths.isNotEmpty || isDirectory) return;

    // Detect type and open appropriate viewer
    if (FileTypeHelper.isImage(name)) {
      _openImageViewer(fullPath, name);
    } else if (FileTypeHelper.canViewAsText(name)) {
      _openCodeEditor(fullPath, name);
    }
  }

  void _openCodeEditor(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CodeEditorScreen(
          client: widget.client,
          remotePath: path,
          fileName: name,
        ),
      ),
    );
  }

  void _openImageViewer(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageViewerScreen(
          client: widget.client,
          remotePath: path,
          fileName: name,
        ),
      ),
    );
  }
}