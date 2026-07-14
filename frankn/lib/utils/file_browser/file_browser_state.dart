/// File browser state management.
///
/// Contains the state logic for file browser operations including
/// directory navigation, file selection, and search functionality.
///
/// ARCHITECTURE:
/// This class acts as the "ViewModel" or "Controller" for the File Browser.
/// It holds all mutable state (current path, entries, selection) and exposes
/// methods to modify that state. It listens to the [RtcThinClient] stream for
/// updates from the host and notifies listeners (the UI) when changes occur.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/file_browser/file_browser_utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';

/// State manager for file browser operations.
class FileBrowserState with ChangeNotifier {
  final RtcThinClient client;
  StreamSubscription? _responseSub;

  FileBrowserState(this.client) {
    if (client.lastNavigatedPath != null) {
      _currentPath = client.lastNavigatedPath!;
    } else if (client.homeDir != null) {
      _currentPath = client.homeDir!;
    }
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

  // ========== SETTERS WITH NOTIFICATION ==========

  void setCurrentPath(String path) {
    _currentPath = path;
    client.lastNavigatedPath = path;
    notifyListeners();
  }

  /// Updates the file list and clears selection/loading state.
  /// Called when directory listing response is received.
  void setEntries(List<dynamic> entries) {
    _entries = entries;
    _isLoading = false;
    _selectedPaths.clear();
    notifyListeners();
  }

  void setSortBy(SortOption sort) {
    _sortBy = sort;
    _fetchDirectory();
  }

  void setShowHidden(bool show) {
    _showHidden = show;
    _fetchDirectory();
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
    _selectedPaths.clear();

    client.sendDcMsg(DcMsgLs(
      path: _currentPath,
      sortBy: _sortBy.value,
      showHidden: _showHidden,
    ));
  }

  /// Listens to the global [RtcThinClient] response stream.
  /// This connects the UI state to the networking layer.
  void _listenForResponses() {
    _responseSub = client.genDcMsgStream.listen((msg) {
      // Handle directory listing response
      if (msg is HostMsgResponse) {
        final data = msg.data;
        if (data is Map && data.containsKey('entries')) {
          setEntries(data['entries']);
        }
      } else if (msg is HostMsgUnknown && msg.raw.containsKey('entries')) {
        setEntries(msg.raw['entries']);
      }
    });
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
    _responseSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }
}
