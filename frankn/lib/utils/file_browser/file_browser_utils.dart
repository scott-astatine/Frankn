/// File browser utility functions and helpers.
///
/// Contains shared utilities for file type detection, path manipulation,
/// and file browser-specific logic that can be used across multiple screens.
library;

import 'package:flutter/material.dart';

/// File type detection and categorization utilities.
class FileTypeHelper {
  /// Returns true if the file extension indicates an image format.
  static bool isImage(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext);
  }

  /// Returns true if the file can be viewed as text/code.
  static bool canViewAsText(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    const textExtensions = {
      'txt',
      'rs',
      'dart',
      'py',
      'js',
      'sh',
      'json',
      'yaml',
      'yml',
      'md',
      'cpp',
      'hpp',
      'h',
      'c',
      'java',
      'xml',
      'html',
      'css',
      'toml',
      'conf',
      'service',
      'log',
      'lock',
      'gitignore',
    };
    return textExtensions.contains(ext) || !filename.contains('.');
  }

  /// Gets the appropriate icon for a file based on its extension.
  static IconData getIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'mp4':
      case 'mkv':
      case 'mov':
        return Icons.movie;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.music_note;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
        return Icons.archive;
      case 'rs':
      case 'dart':
      case 'py':
      case 'js':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }
}

/// Path manipulation utilities for file browser navigation.
class PathHelper {
  /// Normalizes a path by removing trailing slashes (except for root).
  static String normalize(String path) {
    if (path.endsWith("/") && path.length > 1) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  /// Gets the parent directory path.
  static String getParent(String path) {
    final normalized = normalize(path);
    if (normalized == "/") return "/";

    final parts = normalized.split('/')..removeWhere((s) => s.isEmpty);
    if (parts.isNotEmpty) parts.removeLast();

    return "/${parts.join('/')}${parts.isEmpty ? '' : '/'}";
  }

  /// Joins a directory path with a filename.
  static String join(String directory, String filename) {
    String result = directory;
    if (!result.endsWith("/")) result += "/";
    return result + filename;
  }

  /// Gets the filename from a full path.
  static String getFilename(String path) {
    return path
        .split('/')
        .lastWhere((part) => part.isNotEmpty, orElse: () => '');
  }
}

/// File browser-specific constants and enums.
class FileBrowserConstants {
  static const String defaultPath = "/home/";
  static const String rootPath = "/";
}

/// Sorting options for file browser.
enum SortOption {
  name('name', 'Sort by Name'),
  size('size', 'Sort by Size'),
  modified('modified', 'Sort by Date');

  const SortOption(this.value, this.label);
  final String value;
  final String label;
}
