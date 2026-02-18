# Frankn File Browser System

Comprehensive documentation for the file browser implementation in the Frankn Flutter client.

## Overview

The file browser is a modular, feature-rich component that enables remote file management over WebRTC. It provides a native-feeling interface for navigating, selecting, and managing files on the host system.

## Architecture

```
file_browser/
├── file_browser_screen.dart      # Main screen (304 lines)
├── file_browser_state.dart       # State management (196 lines)
├── file_browser_ui.dart           # UI components (260 lines)
├── file_browser_utils.dart        # Utilities & helpers (136 lines)
└── README.md                      # This file

Related:
├── widgets/file_browser_item.dart  # List item widget
├── services/file_transfer_mixin.dart # Transfer handling
└── services/rtc/rtc.dart        # WebRTC communication
```

## File Types and Responsibilities

### 1. file_browser_screen.dart

**Purpose:** Main screen orchestrator

**Responsibilities:**
- Scaffold and layout management
- Navigation flow (up/down directories)
- Screen lifecycle (init/dispose)
- Integration with transfer mixin
- Coordination between state and UI

**Key Methods:**
```dart
// Navigation
void _navigateUp()              // Go to parent directory
void _navigateDown(String dir)  // Enter subdirectory

// Handlers
void _handleItemTap(...)        // Single tap (select or enter)
void _handleItemDoubleTap(...)  // Double tap (open file)
void _deleteFile(...)           // Delete with confirmation
void _bulkDelete()              // Delete multiple files
void _bulkDownload()            // Download multiple files
```

**Lifecycle:**
```dart
@override
void initState() {
  // 1. Create state manager
  _browserState = FileBrowserState(widget.client);
  
  // 2. Listen for state changes
  _browserState.addListener(_onStateChanged);
  
  // 3. Initial data fetch
  _browserState.refreshDirectory();
  
  // 4. Setup transfer listener
  setupTransferListener();
}

@override
void dispose() {
  _browserState.removeListener(_onStateChanged);
  _browserState.dispose();
  super.dispose();
}
```

### 2. file_browser_state.dart

**Purpose:** Centralized state management using ChangeNotifier

**Responsibilities:**
- Directory navigation state
- File selection management
- Search functionality
- Filtering and sorting
- RTC communication
- State change notifications

**State Variables:**
```dart
// Navigation
String _currentPath = "/home/";      // Current directory path
List<dynamic> _entries = [];       // Directory contents

// Selection
Set<String> _selectedPaths = {};    // Selected file paths

// Display
SortOption _sortBy = SortOption.name;  // Sort method
bool _showHidden = false;           // Show hidden files

// Search
bool _isSearching = false;          // Search mode active
String _searchQuery = "";          // Current search text
TextEditingController _searchController;  // Search input

// Loading
bool _isLoading = false;           // Loading state
String _transferMessage = "";       // Transfer progress message
```

**State Notifications:**
```dart
// When state changes, listeners are notified
void _onStateChanged() => setState(() {});

// UI rebuilds automatically when state changes
_browserState.addListener(_onStateChanged);
```

**Key Methods:**
```dart
// Navigation
void navigateUp()         // Go to parent directory
void navigateDown(String dirName)  // Enter directory
void exitSearch()         // Exit search mode
void refreshDirectory()   // Reload current directory

// Selection
void toggleSelection(String path)  // Toggle selection
void clearSelection()     // Clear all selections
bool isSelected(String path)      // Check if selected

// Modifiers
void setCurrentPath(String path)
void setEntries(List<dynamic> entries)
void setSortBy(SortOption sort)
void setShowHidden(bool show)
void setIsSearching(bool searching)
void setSearchQuery(String query)
void setIsLoading(bool loading)
void setTransferMessage(String message)
```

**Filtering:**
```dart
List<dynamic> getFilteredEntries() {
  return _entries.where((e) {
    final name = e['name'].toString().toLowerCase();
    return name.contains(_searchQuery.toLowerCase());
  }).toList();
}
```

### 3. file_browser_ui.dart

**Purpose:** Reusable UI components and builders

**Components:**

#### App Bar Builders
```dart
// Default mode - navigation and controls
AppBar buildDefault({
  required String currentPath,
  required SortOption sortBy,
  required bool showHidden,
  required VoidCallback onSearch,
  required Function(SortOption) onSortChanged,
  required VoidCallback onToggleHidden,
  required VoidCallback onNavigateUp,
})

// Selection mode - bulk operations
AppBar buildSelection({
  required int selectedCount,
  required VoidCallback onClearSelection,
  required VoidCallback onBulkDownload,
  required VoidCallback onBulkDelete,
})

// Search mode - filtering
AppBar buildSearch({
  required TextEditingController controller,
  required String searchQuery,
  required VoidCallback onExitSearch,
  required Function(String) onQueryChanged,
})
```

#### Dialog Builders
```dart
// Bulk delete confirmation
Future<bool?> showBulkDelete(
  BuildContext context,
  int itemCount,
)

// Single file delete confirmation
Future<bool> showSingleDelete(
  BuildContext context,
  String filename,
)
```

**UI Flow:**
```
Default AppBar
    ├── Title: Current path
    ├── Search Button → Search AppBar
    ├── Sort Menu → Popup with options
    ├── Visibility Toggle → Show/hide hidden
    └── Back Button → Navigate up

Selection AppBar
    ├── Close → Clear selection
    ├── Title: "N SELECTED"
    ├── Download → Bulk download
    └── Delete → Bulk delete
```

### 4. file_browser_utils.dart

**Purpose:** Shared utilities and helpers

**Classes:**

#### FileTypeHelper
```dart
// Check file type
bool isImage(String filename)           // jpg, png, gif, etc.
bool canViewAsText(String filename)      // Code, config, text files
IconData getIcon(String filename)        // Appropriate icon
```

**Supported Image Formats:**
```dart
{'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}
```

**Supported Text Formats:**
```dart
{'txt', 'rs', 'dart', 'py', 'js', 'sh', 'json', 'yaml', 'yml',
 'md', 'cpp', 'hpp', 'h', 'c', 'java', 'xml', 'html', 'css',
 'toml', 'conf', 'service', 'log', 'lock', 'gitignore'}
```

#### PathHelper
```dart
String normalize(String path)     // Remove trailing slashes
String getParent(String path)    // Get parent directory
String join(String dir, String file)  // Combine path
String getFilename(String path) // Extract filename
```

**Examples:**
```dart
normalize("/home/user/")    // "/home/user"
getParent("/home/user/")   // "/home/"
join("/home/", "file.txt") // "/home/file.txt"
getFilename("/a/b/c.txt")  // "c.txt"
```

#### FileBrowserConstants
```dart
static const String defaultPath = "/home/";
static const String rootPath = "/";
```

#### SortOption Enum
```dart
enum SortOption {
  name('name', 'Sort by Name'),
  size('size', 'Sort by Size'),
  modified('modified', 'Sort by Date'),
}
```

## State Management Deep Dive

### ChangeNotifier Pattern

The file browser uses Flutter's ChangeNotifier for reactive state management:

```
┌─────────────────────────────────────────────────────────────┐
│                     FileBrowserState                         │
│                  (ChangeNotifier)                            │
├─────────────────────────────────────────────────────────────┤
│  - currentPath                                             │
│  - entries                                                 │
│  - selectedPaths                                           │
│  - isSearching                                            │
│  - sortBy                                                 │
│  - showHidden                                             │
├─────────────────────────────────────────────────────────────┤
│  + notifyListeners()  ──────► UI rebuilds                   │
└─────────────────────────────────────────────────────────────┘
         ▲
         │ addListener()
         │
┌────────┴────────┐
│  _onStateChanged  │  Called when state changes
│  setState((){})  │  Triggers widget rebuild
└─────────────────┘
```

### State Flow Diagram

```
User Action
    │
    ▼
┌─────────────────┐
│  State Change   │  ← State methods update variables
└────────┬────────┘
         │
         ▼ notifyListeners()
┌─────────────────┐
│  _onStateChanged│  ← Listener callback
└────────┬────────┘
         │
         ▼ setState()
┌─────────────────┐
│   Widget Build  │  ← UI rebuilds with new state
└────────┬────────┘
         │
         ▼
    Updated UI
```

### State vs UI State

**FileBrowserState manages:**
- Directory contents (`_entries`)
- Current path (`_currentPath`)
- Selection set (`_selectedPaths`)
- Search query (`_searchQuery`)
- Loading state (`_isLoading`)
- Transfer progress (`_transferMessage`)

**Widget State manages:**
- Animation controllers
- Focus nodes
- Scroll positions
- Dialog states

## Notification Handling for File Operations

### Transfer Notifications

The file browser uses `FileTransferMixin` to handle transfer notifications:

```dart
// In file_browser_screen.dart
mixin FileTransferMixin on State<FileBrowserScreen> {
  void setupTransferListener() {
    client.commandResponseStream.listen((resp) {
      if (resp['type'] == DcMsg.FileTransferEnd) {
        handleInternalTransferComplete(resp);
      }
    });
  }
}
```

### Notification Flow for Operations

#### Upload Flow
```
1. User taps FAB (upload)
   ↓
2. File picker opens
   ↓
3. User selects file
   ↓
4. sendUploadStart() → Host
   ├─ id: UUID
   ├─ path: Remote destination
   ├─ total_size: Bytes
   └─ hash: SHA256 (optional)
   ↓
5. Chunks sent via sendUploadChunk()
   ↓
6. sendUploadEnd() → Host
   ↓
7. Host validates hash
   ↓
8. FileTransferEnd response
   ↓
9. handleInternalTransferComplete()
   ↓
10. State refresh
```

#### Download Flow
```
1. User taps download (or bulk download)
   ↓
2. downloadFile(path) called
   ↓
3. sendDcMsg({DcMsg.GetFile, path})
   ↓
4. Host reads file
   ↓
5. FileTransferStart response
   ├─ id: Transfer UUID
   ├─ file_name: Filename
   ├─ total_size: Bytes
   └─ hash: SHA256 (optional)
   ↓
6. Binary chunks received
   ↓
7. FileTransferEnd response
   ↓
8. File saved to device
   ↓
9. Transfer complete notification
```

#### Delete Flow
```
1. User requests delete
   ↓
2. Confirmation dialog shown
   ↓
3. User confirms
   ↓
4. sendDcMsg({DcMsg.DeleteFile, path})
   ↓
5. Host deletes file
   ↓
6. Response received
   ↓
7. Directory refreshed
```

### onEdit Handler

The `onEdit` callback opens the code editor:

```dart
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
```

**Automatic Detection:**
```dart
void _handleItemDoubleTap(...) {
  if (FileTypeHelper.canViewAsText(name)) {
    _openCodeEditor(fullPath, name);
  }
}
```

## Integration Points

### RTC Integration
```dart
// Send command to host
client.sendDcMsg({
  DcMsg.Key: DcMsg.Ls,
  "path": _currentPath,
  "sort_by": _sortBy.value,
  "show_hidden": _showHidden,
});

// Listen for responses
client.commandResponseStream.listen((resp) {
  if (resp['data'].containsKey('entries')) {
    _browserState.setEntries(resp['data']['entries']);
  }
});
```

### File Transfer Integration
```dart
// Start transfer
await downloadFile(path);

// Listen for progress
client.mediaStatusStream.listen((status) {
  // Update transfer progress
});

// Complete handler
void handleInternalTransferComplete(Map<String, dynamic> resp) {
  setTransferMessage("");
  refreshDirectory();
}
```

### Navigation Integration
```dart
// Pop handling (Android back button)
PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, _) {
    if (!didPop) {
      _navigateUp();
      if (_currentPath == "/" || _currentPath == "/home/") {
        Navigator.of(context).pop();
      }
    }
  },
)
```

## Performance Considerations

### Large Directory Optimization
```dart
// Filter only when needed
List<dynamic> getFilteredEntries() {
  if (_searchQuery.isEmpty) return _entries;
  
  return _entries.where((e) {
    return e['name'].toLowerCase().contains(_searchQuery.toLowerCase());
  }).toList();
}
```

### Chunked Transfers
```dart
// Binary chunks use 36-byte header
// Transfer ID (36 bytes) + Data
// Efficient for large files
```

### Lazy Loading
```dart
// Only fetch directory when needed
void refreshDirectory() {
  setIsLoading(true);
  clearSelection();
  client.sendDcMsg({...});
}
```

## Error Handling

### Connection Loss
```dart
// Automatic reconnection handled by RTC layer
// State resets on disconnect
void _onStateChanged() {
  if (_browserState.currentHostState == HostConnectionState.disconnected) {
    _browserState.setIsLoading(false);
  }
}
```

### Transfer Errors
```dart
void handleInternalTransferComplete(Map<String, dynamic> resp) {
  if (resp['completed'] == true) {
    log("Transfer complete: ${resp['file_name']}");
    refreshDirectory();
  } else {
    log("Transfer failed: ${resp['error']}");
    setTransferMessage("Transfer failed");
  }
}
```

## Extending the File Browser

### Adding New File Types

In `file_browser_utils.dart`:

```dart
class FileTypeHelper {
  static bool isVideo(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return {'mp4', 'mkv', 'mov', 'avi'}.contains(ext);
  }
  
  static IconData getIcon(String filename) {
    if (isVideo(filename)) return Icons.movie;
    // ... existing logic
  }
}
```

### Adding New Operations

1. In `file_browser_state.dart`:
```dart
Future<void> compressFile(String path) async {
  client.sendDcMsg({
    DcMsg.Key: DcMsg.CompressFile,
    "path": path,
  });
}
```

2. In `file_browser_ui.dart`:
```dart
Widget _buildCompressButton() {
  return IconButton(
    icon: const Icon(Icons.archive),
    onPressed: () => _browserState.compressFile(selectedPath),
  );
}
```

## Testing Strategy

### Unit Tests
```dart
void main() {
  test('PathHelper.normalize removes trailing slashes', () {
    expect(PathHelper.normalize("/home/"), "/home");
  });
  
  test('FileTypeHelper.isImage detects images', () {
    expect(FileTypeHelper.isImage("photo.jpg"), true);
    expect(FileTypeHelper.isImage("document.txt"), false);
  });
}
```

### Integration Tests
```dart
testWidgets('Navigate to directory', (tester) async {
  await tester.pumpWidget(MyApp());
  
  // Verify initial state
  expect(find.text('FILE BROWSER'), findsOneWidget);
  
  // Navigate
  await tester.tap(find.byIcon(Icons.folder));
  await tester.pump();
  
  // Verify navigation
  expect(find.text('/home/user'), findsOneWidget);
});
```

## Related Documentation

- [RTC Service Documentation](../services/rtc/README.md)
- [File Transfer Mixin](../services/file_transfer_mixin.dart)
- [WebRTC Protocol Specification](../services/rtc/rtc.dart)
- [Host File System API](../../frankn-host/src/sys/fs.rs)
