/// File browser state management.
///
/// Contains the state logic for file browser operations including
/// directory navigation, file selection, and search functionality.
///
/// ARCHITECTURE:
/// This class acts as the "ViewModel" or "Controller" for the File Browser.
/// It holds all mutable state (current path, entries, selection) and exposes
/// methods to modify that state. It listens to the [RtcClient] stream for
/// updates from the host and notifies listeners (the UI) when changes occur.
library;

import 'package:flutter/material.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/file_browser/file_browser_utils.dart';
import 'package:frankn/utils/utils.dart';

/// State manager for file browser operations.
class FileBrowserState with ChangeNotifier {
  final RtcClient client;

  FileBrowserState(this.client) {
    _listenForResponses();
  }

  // ========== STATE ==========

  /// The current directory path on the remote host.
  String _currentPath = FileBrowserConstants.defaultPath;

  /// List of file/folder entries in the current directory.
  List<dynamic> _entries = [];

  /// Current sorting criterion (Name, Size, Date).
  SortOption _sortBy = SortOption.name;

  /// Whether to show hidden files (starting with '.').
  bool _showHidden = false;

  /// Set of full paths for currently selected items (for bulk actions).
  final Set<String> _selectedPaths = {};

  // --- Search State ---
  bool _isSearching = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  // --- Status State ---
  bool _isLoading = false;
  String _transferMessage = "";
  double _transferProgress = 0.0;

  // ========== GETTERS ==========

  String get currentPath => _currentPath;
  List<dynamic> get entries => _entries;
  SortOption get sortBy => _sortBy;
  bool get showHidden => _showHidden;
  Set<String> get selectedPaths => _selectedPaths;
  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;
  TextEditingController get searchController => _searchController;
  bool get isLoading => _isLoading;
  String get transferMessage => _transferMessage;
  double get transferProgress => _transferProgress;

  // ========== SETTERS WITH NOTIFICATION ==========

  void setCurrentPath(String path) {
    _currentPath = path;
    notifyListeners();
  }

  /// Updates the file list and clears selection/loading state.
  /// Called when [DcMsg.Ls] response is received.
  void setEntries(List<dynamic> entries) {
    _entries = entries;
    _isLoading = false;
    _selectedPaths.clear();
    notifyListeners();
  }

  void setSortBy(SortOption sort) {
    _sortBy = sort;
    notifyListeners();
  }

  void setShowHidden(bool show) {
    _showHidden = show;
    notifyListeners();
  }

  void setIsSearching(bool searching) {
    _isSearching = searching;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setIsLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setTransferMessage(String message) {
    _transferMessage = message;
    notifyListeners();
  }

  void setTransferProgress(double progress) {
    _transferProgress = progress;
    notifyListeners();
  }

  // ========== SELECTION MANAGEMENT ==========

  void toggleSelection(String path) {
    if (_selectedPaths.contains(path)) {
      _selectedPaths.remove(path);
    } else {
      _selectedPaths.add(path);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedPaths.clear();
    notifyListeners();
  }

  bool isSelected(String path) => _selectedPaths.contains(path);

  // ========== NAVIGATION ==========

  /// Navigates to the parent directory.
  /// Handles special cases: exiting search, clearing selection, or stopping at root.
  void navigateUp() {
    if (_selectedPaths.isNotEmpty) {
      clearSelection();
      return;
    }
    if (_isSearching) {
      exitSearch();
      return;
    }
    if (_currentPath == FileBrowserConstants.rootPath) return;

    final newPath = PathHelper.getParent(_currentPath);
    setCurrentPath(newPath);
    _fetchDirectory();
  }

  /// Navigates into a subdirectory.
  void navigateDown(String directoryName) {
    final nextPath = PathHelper.join(_currentPath, directoryName);
    setCurrentPath(nextPath);
    _fetchDirectory();
  }

  void exitSearch() {
    setIsSearching(false);
    setSearchQuery("");
    _searchController.clear();
  }

  // ========== DATA OPERATIONS ==========

  void refreshDirectory() => _fetchDirectory();

  /// Sends a request to the host to list the current directory.
  /// This initiates the async flow: UI -> Client -> Host -> Client -> UI.
  void _fetchDirectory() {
    setIsLoading(true);
    clearSelection();
    setIsSearching(false);
    setSearchQuery("");
    _searchController.clear();

    client.sendDcMsg({
      DcMsg.Key: DcMsg.Ls,
      "path": _currentPath,
      "sort_by": _sortBy.value,
      "show_hidden": _showHidden,
    });
  }

  /// Listens to the global [RtcClient] response stream.
  /// This connects the UI state to the networking layer.
  void _listenForResponses() {
    client.commandResponseStream.listen((resp) {
      final data = _extractResponseData(resp);
      final type = resp['type'];

      // Handle directory listing response
      if (data.containsKey('entries')) {
        setEntries(data['entries']);
      } 
      // Handle file transfer completion (from FileTransferMixin)
      else if (type == DcMsg.FileTransferEnd) {
        setTransferMessage("");
        setTransferProgress(0.0);
        setIsLoading(false);
      }
      else if (type == DcMsg.FileTransferStart) {
        setTransferMessage("DOWNLOADING: ${resp['file_name']}");
        setTransferProgress(0.0);
        setIsLoading(true);
      }
      else if (type == DcMsg.FileChunk) {
        notifyListeners();
      }
    });
  }

  /// Helper to unwrap nested response data structures.
  Map<String, dynamic> _extractResponseData(Map<String, dynamic> resp) {
    if (resp['type'] == 'response' && resp.containsKey('data')) {
      return resp['data'] as Map<String, dynamic>;
    }
    return resp;
  }

  // ========== FILTERING ==========

  /// Filters the entry list based on the local search query.
  /// This is done client-side for immediate feedback.
  List<dynamic> getFilteredEntries() {
    return _entries.where((e) {
      final name = e['name'].toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  // ========== LIFECYCLE ==========

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}