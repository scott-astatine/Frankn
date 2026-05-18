import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/file_browser/file_browser_state.dart';
import 'package:frankn/utils/file_browser/file_browser_ui.dart';
import 'package:frankn/utils/utils.dart';

/// A specialized modal file browser used for selecting a directory on the host.
class RemoteDirSelector extends StatefulWidget {
  final RtcThinClient client;
  final String initialPath;

  const RemoteDirSelector({
    super.key,
    required this.client,
    this.initialPath = '/home/',
  });

  @override
  State<RemoteDirSelector> createState() => _RemoteDirSelectorState();
}

class _RemoteDirSelectorState extends State<RemoteDirSelector> {
  late final FileBrowserState _browserState;

  @override
  void initState() {
    super.initState();
    _browserState = FileBrowserState(widget.client);
    _browserState.setCurrentPath(widget.initialPath);
    _browserState.refreshDirectory();
    _browserState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _browserState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _createNewFolder() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.neonCyan),
        ),
        title: const Text(
          "CREATE NEW FOLDER",
          style: TextStyle(
            color: AppColors.neonCyan,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1,
          ),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: "Folder Name",
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white10),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.neonCyan),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ABORT", style: TextStyle(color: AppColors.textGrey)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final currentPath = _browserState.currentPath;
                final newPath = currentPath.endsWith('/') 
                    ? "$currentPath$name" 
                    : "$currentPath/$name";
                
                widget.client.sendDcMsg({
                  DcMsg.Key: "mkdir",
                  "path": newPath,
                });
                
                // Wait briefly for host to create, then refresh
                Future.delayed(const Duration(milliseconds: 300), () {
                  _browserState.refreshDirectory();
                });
                
                Navigator.pop(context);
              }
            },
            child: const Text(
              "CREATE",
              style: TextStyle(color: AppColors.neonCyan, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: AppColors.voidBlack,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.neonCyan, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.folder_open, color: AppColors.neonCyan),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "SELECT_REMOTE_DIRECTORY",
                    style: TextStyle(
                      color: AppColors.neonCyan,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, color: AppColors.neonCyan),
                  onPressed: _createNewFolder,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Breadcrumbs
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

          // Directory List
          Expanded(
            child: ListView.builder(
              itemCount: _browserState.entries.length,
              itemBuilder: (context, index) {
                final entry = _browserState.entries[index];
                if (!entry['is_dir']) return const SizedBox.shrink();

                return ListTile(
                  leading: const Icon(Icons.folder, color: AppColors.matrixGreen, size: 20),
                  title: Text(
                    entry['name'],
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  onTap: () {
                    _browserState.navigateDown(entry['name']);
                  },
                );
              },
            ),
          ),

          // Footer Action
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _browserState.currentPath),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonCyan.withValues(alpha: 0.1),
                  foregroundColor: AppColors.neonCyan,
                  side: const BorderSide(color: AppColors.neonCyan, width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("CHOOSE_CURRENT_DIRECTORY", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
