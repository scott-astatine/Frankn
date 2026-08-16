import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdfx/pdfx.dart';
import 'package:frankn/services/file_transfer_mixin.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/utils/utils.dart';

class PdfViewerScreen extends StatefulWidget {
  final RtcThinClient? client;
  final String? remotePath;
  final String fileName;
  final String? localFilePath;

  const PdfViewerScreen({
    super.key,
    this.client,
    this.remotePath,
    required this.fileName,
    this.localFilePath,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> with FileTransferMixin {
  String? _activeDownloadId;
  StreamSubscription? _transferSub;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isImmersive = false;
  bool _isNightMode = false;

  int _currentPage = 1;
  int _totalPages = 0;

  PdfControllerPinch? _pdfController;
  Future<PdfDocument>? _pdfDocumentFuture;

  @override
  RtcThinClient get client => widget.client ?? RtcThinClient();

  @override
  void initState() {
    super.initState();
    if (widget.localFilePath != null) {
      _initPdf(widget.localFilePath!);
    } else {
      setupTransferListener();

      _transferSub = client.transferProgressStream.listen((msg) {
        if (msg is TransferProgressComplete) {
          if (msg.id == _activeDownloadId || msg.fileName == widget.fileName) {
            final String? path = msg.finalPath;
            if (path != null) {
              _initPdf(path);
            }
          }
        } else if (msg is TransferProgressFailed) {
          if (msg.id == _activeDownloadId) {
            if (mounted) {
              setState(() {
                isLoading = false;
                _hasError = true;
              });
            }
          }
        }
      });

      _loadFile();
    }
  }

  void _loadFile() async {
    if (widget.remotePath == null) return;
    if (mounted) {
      setState(() {
        isLoading = true;
        _hasError = false;
      });
    }
    _activeDownloadId = await downloadFile(
      widget.remotePath!,
      showNotification: false,
      isTemporary: true,
    );
  }

  Future<void> _initPdf(String path) async {
    try {
      final documentFuture = PdfDocument.openFile(path);
      final doc = await documentFuture;
      if (mounted) {
        setState(() {
          _totalPages = doc.pagesCount;
          _pdfDocumentFuture = Future.value(doc);
          _pdfController = PdfControllerPinch(
            document: _pdfDocumentFuture!,
            initialPage: 1,
          );
          _isInitialized = true;
          isLoading = false;
        });
      }
    } catch (e) {
      client.log("PDF VIEWER ERROR: Failed to open PDF: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pdfController?.dispose();
    _transferSub?.cancel();
    if (!_isInitialized && _activeDownloadId != null) {
      client.sendIntent(IsolateAction.cancelTransfer, {
        'id': _activeDownloadId,
      });
      client.log("PDF VIEWER: Cancelled background download due to exit");
    }
    super.dispose();
  }

  @override
  void refreshDirectory() {}

  void _toggleImmersive() {
    setState(() {
      _isImmersive = !_isImmersive;
    });
    if (_isImmersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. PDF Content or Loader
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleImmersive,
              behavior: HitTestBehavior.translucent,
              child: _buildBody(),
            ),
          ),

          // 2. Sliding App Bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            top: _isImmersive ? -100 : 0,
            left: 0,
            right: 0,
            child: _buildHeader(),
          ),

          // 3. Sliding Bottom Control Deck
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            bottom: _isImmersive ? -120 : 0,
            left: 0,
            right: 0,
            child: _buildBottomDeck(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading && _pdfDocumentFuture == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: AppColors.markdownPrimaryLight,
            ),
            const SizedBox(height: 16),
            Text(
              "FETCHING PDF DOCUMENT...",
              style: GoogleFonts.jetBrainsMono(
                color: AppColors.markdownPrimaryLight,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.accentError,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              "FAILED TO LOAD PDF DOCUMENT",
              style: GoogleFonts.jetBrainsMono(
                color: AppColors.accentError,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.markdownPrimary, width: 0.5),
              ),
              child: Text(
                "RETRY CONNECTION",
                style: GoogleFonts.jetBrainsMono(
                  color: AppColors.markdownPrimaryLight,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_pdfDocumentFuture == null || _pdfController == null) {
      return Center(
        child: Text(
          "DOCUMENT EMPTY",
          style: GoogleFonts.jetBrainsMono(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      );
    }

    Widget viewer = PdfViewPinch(
      controller: _pdfController!,
      onPageChanged: (page) {
        setState(() {
          _currentPage = page;
        });
      },
    );

    if (_isNightMode) {
      viewer = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1.0,  0.0,  0.0, 0.0, 255.0, // Red
           0.0, -1.0,  0.0, 0.0, 255.0, // Green
           0.0,  0.0, -1.0, 0.0, 255.0, // Blue
           0.0,  0.0,  0.0, 1.0,   0.0, // Alpha
        ]),
        child: viewer,
      );
    }

    return viewer;
  }

  Widget _buildHeader() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          height: kToolbarHeight + 24,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.8),
            border: Border(
              bottom: BorderSide(
                color: AppColors.markdownPrimary.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 24, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.chevron_left,
                  color: AppColors.markdownPrimaryLight,
                  size: 24,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  widget.fileName,
                  style: GoogleFonts.jetBrainsMono(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomDeck() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.8),
            border: Border(
              top: BorderSide(
                color: AppColors.markdownPrimary.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 1. Page navigation HUD
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.navigate_before, color: AppColors.textPrimary),
                      onPressed: _currentPage > 1
                          ? () => _pdfController?.animateToPage(
                              pageNumber: _currentPage - 1,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut)
                          : null,
                    ),
                    Text(
                      "PAGE $_currentPage / $_totalPages",
                      style: GoogleFonts.jetBrainsMono(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.navigate_next, color: AppColors.textPrimary),
                      onPressed: _currentPage < _totalPages
                          ? () => _pdfController?.animateToPage(
                              pageNumber: _currentPage + 1,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut)
                          : null,
                    ),
                  ],
                ),

                // 2. Control deck toggles (Night Mode & Zoom reset)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.zoom_out_map, color: AppColors.textPrimary),
                      tooltip: "Reset Zoom",
                      onPressed: () {
                        _pdfController?.animateToPage(
                            pageNumber: _currentPage,
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeInOut);
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        _isNightMode ? Icons.light_mode : Icons.dark_mode,
                        color: _isNightMode ? AppColors.accentWarning : AppColors.textPrimary,
                      ),
                      tooltip: "Toggle Night Mode",
                      onPressed: () {
                        setState(() {
                          _isNightMode = !_isNightMode;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
