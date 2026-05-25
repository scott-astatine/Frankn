import 'dart:io';
import 'package:flutter/material.dart';
import 'package:frankn/services/permission_service.dart';
import 'package:frankn/utils/file_browser/file_browser_ui.dart';
import 'package:frankn/utils/utils.dart';
import 'package:google_fonts/google_fonts.dart';

/// A premium cyberpunk-themed local file/directory selector modal running fully in Dart.
/// Bypasses native Android Storage Access Framework (SAF) activity thread freezes.
class LocalDirSelector extends StatefulWidget {
  final String? initialPath;
  final bool pickFiles; // true to pick a file, false to pick a directory

  const LocalDirSelector({
    super.key,
    this.initialPath,
    this.pickFiles = false,
  });

  @override
  State<LocalDirSelector> createState() => _LocalDirSelectorState();
}

class _LocalDirSelectorState extends State<LocalDirSelector> {
  late String _currentPath;
  List<Directory> _subDirs = [];
  List<File> _files = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Default starting point: user-visible internal storage root on Android
    final initial = widget.initialPath;
    if (initial != null && initial.isNotEmpty && Directory(initial).existsSync()) {
      _currentPath = initial;
    } else {
      if (Platform.isAndroid) {
        _currentPath = '/storage/emulated/0';
      } else {
        _currentPath = Platform.isWindows ? 'C:\\' : '/';
      }
    }
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        // Fallback if path is invalid or non-existent
        final fallbackPath = Platform.isAndroid ? '/storage/emulated/0' : '/';
        if (path != fallbackPath) {
          _loadDirectory(fallbackPath);
          return;
        }
        throw FileSystemException("Directory does not exist", path);
      }

      final List<Directory> tempDirs = [];
      final List<File> tempFiles = [];

      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue; // skip hidden files

        if (entity is Directory) {
          tempDirs.add(entity);
        } else if (entity is File && widget.pickFiles) {
          tempFiles.add(entity);
        }
      }

      // Sort alphabetically (case-insensitive)
      tempDirs.sort((a, b) {
        final nameA = a.path.split(Platform.pathSeparator).last.toLowerCase();
        final nameB = b.path.split(Platform.pathSeparator).last.toLowerCase();
        return nameA.compareTo(nameB);
      });

      if (widget.pickFiles) {
        tempFiles.sort((a, b) {
          final nameA = a.path.split(Platform.pathSeparator).last.toLowerCase();
          final nameB = b.path.split(Platform.pathSeparator).last.toLowerCase();
          return nameA.compareTo(nameB);
        });
      }

      if (mounted) {
        setState(() {
          _currentPath = path;
          _subDirs = tempDirs;
          _files = tempFiles;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().contains("Permission denied")
              ? "ACCESS DENIED\nTAP TO GRANT STORAGE PERMISSIONS"
              : "DIRECTORY CORRUPT OR UNREADABLE\n$e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePermissionRequest() async {
    final granted = await PermissionService().requestStoragePermissions();
    if (granted) {
      _loadDirectory(_currentPath);
    }
  }

  void _navigateUp() {
    if (_currentPath == '/' || _currentPath == '') return;
    
    // Check if we are at Windows drive roots
    if (Platform.isWindows && RegExp(r'^[a-zA-Z]:\\$').hasMatch(_currentPath)) {
      return;
    }

    final parentDir = Directory(_currentPath).parent;
    if (parentDir.path == _currentPath) return; // reached system root
    _loadDirectory(parentDir.path);
  }

  void _createNewFolder() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.neonCyan, width: 1.5),
        ),
        title: Text(
          "INITIALIZE LOCAL DIRECTORY",
          style: GoogleFonts.jetBrainsMono(
            color: AppColors.neonCyan,
            fontWeight: FontWeight.w900,
            fontSize: 13,
            letterSpacing: 1,
          ),
        ),
        content: TextField(
          controller: controller,
          style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: "FOLDER_NAME",
            hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 11),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white10),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.neonCyan),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "ABORT",
              style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                try {
                  final sep = Platform.pathSeparator;
                  final newPath = _currentPath.endsWith(sep)
                      ? "$_currentPath$name"
                      : "$_currentPath$sep$name";
                  final newDir = Directory(newPath);
                  if (!await newDir.exists()) {
                    await newDir.create();
                  }
                  _loadDirectory(_currentPath);
                } catch (e) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        "⚡ DIRECTORY CREATION FAILED: $e",
                        style: const TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: AppColors.voidBlack,
                    ),
                  );
                }
                navigator.pop();
              }
            },
            child: Text(
              "CREATE",
              style: GoogleFonts.jetBrainsMono(color: AppColors.neonCyan, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleLabel = widget.pickFiles ? "SELECT_LOCAL_FILE" : "SELECT_LOCAL_DIRECTORY";

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: AppColors.voidBlack,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.neonCyan, width: 1.5)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Drag handle & border glow top accent
            const SizedBox(height: 12),
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),

            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    widget.pickFiles ? Icons.insert_drive_file_outlined : Icons.folder_open_outlined,
                    color: AppColors.neonCyan,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      titleLabel,
                      style: GoogleFonts.jetBrainsMono(
                        color: AppColors.neonCyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined, color: AppColors.neonCyan, size: 20),
                    onPressed: _createNewFolder,
                    tooltip: "Create Directory",
                  ),
                  IconButton(
                    icon: const Icon(Icons.drive_file_move_rtl, color: Colors.white38, size: 20),
                    onPressed: _navigateUp,
                    tooltip: "Parent Directory",
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Breadcrumbs Bar
            FileBrowserAppBar.buildBreadcrumbs(
              path: _currentPath,
              onBreadcrumbTap: (path) {
                _loadDirectory(path);
              },
            ),

            // Async Progress Indicator
            if (_isLoading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.neonCyan,
                backgroundColor: Colors.transparent,
              )
            else
              const SizedBox(height: 2),

            // File & Directory Listing Area
            Expanded(
              child: _errorMessage != null
                  ? _buildErrorState()
                  : (_subDirs.isEmpty && _files.isEmpty)
                      ? _buildEmptyState()
                      : _buildListView(),
            ),

            // Directory Selection Action Button
            if (!widget.pickFiles && _errorMessage == null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context, _currentPath);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonCyan.withValues(alpha: 0.1),
                      foregroundColor: AppColors.neonCyan,
                      side: const BorderSide(color: AppColors.neonCyan, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      "CHOOSE_CURRENT_DIRECTORY",
                      style: GoogleFonts.jetBrainsMono(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView() {
    final showParentItem = _currentPath != '/' && _currentPath != '';
    final listCount = _subDirs.length + _files.length + (showParentItem ? 1 : 0);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: listCount,
      itemBuilder: (context, index) {
        int listIndex = index;

        // Parent Directory row ("..")
        if (showParentItem) {
          if (listIndex == 0) {
            return ListTile(
              leading: const Icon(Icons.subdirectory_arrow_left_rounded, color: AppColors.neonPink, size: 18),
              title: Text(
                "..",
                style: GoogleFonts.jetBrainsMono(
                  color: AppColors.textGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                "PARENT_DIRECTORY",
                style: GoogleFonts.jetBrainsMono(color: Colors.white10, fontSize: 9),
              ),
              onTap: _navigateUp,
            );
          }
          listIndex--;
        }

        // Subdirectories listing
        if (listIndex < _subDirs.length) {
          final dir = _subDirs[listIndex];
          final dirName = dir.path.split(Platform.pathSeparator).last;
          return ListTile(
            leading: const Icon(Icons.folder_outlined, color: AppColors.cyberYellow, size: 20),
            title: Text(
              dirName,
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              _loadDirectory(dir.path);
            },
          );
        }

        // Files listing (only shows when widget.pickFiles = true)
        final fileIndex = listIndex - _subDirs.length;
        final file = _files[fileIndex];
        final fileName = file.path.split(Platform.pathSeparator).last;
        final size = file.lengthSync();
        final sizeStr = FileUtils.formatSize(size);
        final fileIcon = FileUtils.getFileIcon(fileName);

        return ListTile(
          leading: Icon(fileIcon, color: AppColors.neonCyan, size: 18),
          title: Text(
            fileName,
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white70,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            sizeStr,
            style: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 10),
          ),
          onTap: () {
            // Pick file and return file path
            Navigator.pop(context, file.path);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.05),
          ),
          const SizedBox(height: 12),
          Text(
            "NO_ELEMENTS_FOUND",
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white24,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: InkWell(
          onTap: _errorMessage!.startsWith("ACCESS DENIED") ? _handlePermissionRequest : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.errorRed.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.gpp_bad_outlined,
                  color: AppColors.errorRed,
                  size: 40,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jetBrainsMono(
                    color: AppColors.errorRed,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    height: 1.5,
                  ),
                ),
                if (_errorMessage!.startsWith("ACCESS DENIED")) ...[
                  const SizedBox(height: 16),
                  Text(
                    "[ TAP TO ACTIVATE ACCESS ]",
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
