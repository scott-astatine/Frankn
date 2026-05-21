import 'package:flutter/material.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/screens/code_editor_screen.dart';
import 'package:frankn/screens/image_viewer_screen.dart';
import 'package:frankn/services/file_transfer_mixin.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/file_browser/file_browser_state.dart';
import 'package:frankn/utils/file_browser/file_browser_ui.dart';
import 'package:frankn/utils/file_browser/file_browser_utils.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/widgets/file_browser_item.dart';

class FileBrowserScreen extends StatefulWidget {
  final RtcThinClient client;
  const FileBrowserScreen({super.key, required this.client});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen>
    with FileTransferMixin {
  late final FileBrowserState _browserState;
  bool _isGridView = false;
  @override
  RtcThinClient get client => widget.client;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      appBar: FileBrowserAppBar.buildDefault(
        context: context,
        currentPath: _browserState.currentPath,
        isGridView: _isGridView,
        selectedCount: _browserState.selectedPaths.length,
        onToggleView: () => setState(() => _isGridView = !_isGridView),
        onSearch: () => _browserState.setIsSearching(true),
        onNavigateUp: () => _browserState.navigateUp(),
        onClearSelection: () => _browserState.clearSelection(),
        onDeleteSelected: _handleBulkDelete,
        onDownloadSelected: _handleBulkDownload,
        isSearching: _browserState.isSearching,
        searchController: _browserState.searchController,
        onSearchChanged: (val) => _browserState.setSearchQuery(val),
        onExitSearch: () => _browserState.exitSearch(),
        onUpload: () => uploadFile(_browserState.currentPath),
        onSort: (val) {
          if (val == "name") _browserState.setSortBy(SortOption.name);
          if (val == "size") _browserState.setSortBy(SortOption.size);
          if (val == "modified") _browserState.setSortBy(SortOption.modified);
        },
      ),
      body: Column(
        children: [
          FileBrowserAppBar.buildBreadcrumbs(
            path: _browserState.currentPath,
            onBreadcrumbTap: (path) {
              _browserState.setCurrentPath(path);
              _browserState.refreshDirectory();
            },
          ),
          if (_browserState.isLoading)
            const LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.neonCyan,
              backgroundColor: Colors.transparent,
            ),
          if (isLoading)
            Column(
              children: [
                LinearProgressIndicator(
                  value: transferProgress,
                  minHeight: 4,
                  color: AppColors.neonPink,
                  backgroundColor: AppColors.deepSpace,
                ),
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Text(
                    transferMsg,
                    style: const TextStyle(
                      color: AppColors.neonPink,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          Expanded(child: _buildMainContent(l10n)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _browserState.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _browserState = FileBrowserState(widget.client);
    _browserState.addListener(_onStateChanged);
    _browserState.refreshDirectory();
    setupTransferListener();
  }

  @override
  void refreshDirectory() => _browserState.refreshDirectory();

  Widget _buildItem(dynamic rawEntry, bool isGrid) {
    final entry = RemoteEntry.fromJson(Map<String, dynamic>.from(rawEntry));
    final fullPath = PathHelper.join(
      _browserState.currentPath,
      entry.name,
    );
    return FileBrowserItem(
      entry: entry,
      isGrid: isGrid,
      fullPath: fullPath,
      isSelected: _browserState.isSelected(fullPath),
      onTap: () {
        if (_browserState.selectedPaths.isNotEmpty) {
          _browserState.toggleSelection(fullPath);
          return;
        }
        if (entry.isDir) {
          _browserState.navigateDown(entry.name);
        } else {
          final name = entry.name;
          final icon = FileUtils.getFileIcon(name);

          if (icon == Icons.image) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImageViewerScreen(
                  remotePath: fullPath,
                  fileName: name,
                  client: widget.client,
                ),
              ),
            );
          } else if (icon == Icons.code ||
              icon == Icons.article_outlined ||
              name.endsWith('.txt')) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CodeEditorScreen(
                  remotePath: fullPath,
                  fileName: name,
                  client: widget.client,
                ),
              ),
            );
          } else {
            // For PDFs, Videos, and other binaries, just trigger a normal download with notification
            downloadFile(fullPath, size: entry.size);
          }
        }
      },
      onLongPress: () => _browserState.toggleSelection(fullPath),
      onDelete: (path) =>
          widget.client.sendDcMsg(DcMsgDeleteFile(path: path)),
      onDownload: (path, size) => downloadFile(path, size: size),
      onEdit: (path, name) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CodeEditorScreen(
            remotePath: path,
            fileName: name,
            client: widget.client,
          ),
        ),
      ),
      onViewImage: (path, name) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerScreen(
            remotePath: path,
            fileName: name,
            client: widget.client,
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(AppLocalizations l10n) {
    final entries = _browserState.getFilteredEntries();
    if (entries.isEmpty && !_browserState.isLoading) {
      return Center(
        child: Text(
          l10n.noDataFound.toUpperCase().replaceAll(" ", "_"),
          style: const TextStyle(
            fontFamily: 'JetBrainsMonoNerdFont',
            color: Colors.white24,
          ),
        ),
      );
    }

    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 5,
          mainAxisSpacing: 2,
          childAspectRatio: 0.75,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) => _buildItem(entries[index], true),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) => _buildItem(entries[index], false),
    );
  }

  void _handleBulkDelete() {
    final paths = _browserState.selectedPaths.toList();
    for (var path in paths) {
      widget.client.sendDcMsg(DcMsgDeleteFile(path: path));
    }
    _browserState.clearSelection();
    _browserState.refreshDirectory();
  }

  void _handleBulkDownload() {
    final entries = _browserState.getFilteredEntries();
    final paths = _browserState.selectedPaths.toList();
    for (var path in paths) {
      final rawEntry = entries.firstWhere(
        (e) =>
            PathHelper.join(_browserState.currentPath, e['name'] as String) ==
            path,
        orElse: () => null,
      );
      if (rawEntry != null) {
          final entry = RemoteEntry.fromJson(Map<String, dynamic>.from(rawEntry));
          downloadFile(path, size: entry.size);
      }
    }
    _browserState.clearSelection();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }
}
