import 'package:flutter/material.dart';
import 'package:frankn/services/file_transfer_mixin.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/file_browser/file_browser_state.dart';
import 'package:frankn/utils/file_browser/file_browser_ui.dart';
import 'package:frankn/utils/file_browser/file_browser_utils.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/file_browser_item.dart';
import 'package:frankn/screens/code_editor_screen.dart';
import 'package:frankn/screens/image_viewer_screen.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

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
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    _browserState = FileBrowserState(widget.client);
    _browserState.addListener(_onStateChanged);
    _browserState.refreshDirectory();
    setupTransferListener();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _browserState.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  void refreshDirectory() => _browserState.refreshDirectory();

  void _handleBulkDelete() {
    final paths = _browserState.selectedPaths.toList();
    for (var path in paths) {
      widget.client.sendDcMsg({DcMsg.Key: DcMsg.DeleteFile, "path": path});
    }
    _browserState.clearSelection();
    _browserState.refreshDirectory();
  }

  void _handleBulkDownload() {
    final paths = _browserState.selectedPaths.toList();
    for (var path in paths) {
      downloadFile(path);
    }
    _browserState.clearSelection();
  }

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
        onSort: (val) {
          if (val == "name") _browserState.setSortBy(SortOption.name);
          if (val == "size") _browserState.setSortBy(SortOption.size);
          if (val == "modified") _browserState.setSortBy(SortOption.modified);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => uploadFile(_browserState.currentPath),
        backgroundColor: AppColors.neonCyan,
        child: const Icon(Icons.upload_file, color: AppColors.voidBlack),
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

  Widget _buildMainContent(AppLocalizations l10n) {
    final entries = _browserState.getFilteredEntries();
    if (entries.isEmpty && !_browserState.isLoading)
      return Center(
        child: Text(
          l10n.noDataFound.toUpperCase().replaceAll(" ", "_"),
          style: const TextStyle(
            fontFamily: 'JetBrainsMonoNerdFont',
            color: Colors.white24,
          ),
        ),
      );

    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85,
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

  Widget _buildItem(dynamic entry, bool isGrid) {
    final fullPath = PathHelper.join(
      _browserState.currentPath,
      entry['name'] as String,
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
        if (entry['is_dir']) {
          _browserState.navigateDown(entry['name']);
        } else {
          final name = entry['name'] as String;
          if (FileUtils.getFileIcon(name) == Icons.image) {
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
          } else {
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
          }
        }
      },
      onLongPress: () => _browserState.toggleSelection(fullPath),
      onDelete: (path) =>
          widget.client.sendDcMsg({DcMsg.Key: DcMsg.DeleteFile, "path": path}),
      onDownload: (path) => downloadFile(path),
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
}
