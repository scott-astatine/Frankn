import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/services/file_transfer_mixin.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';
import 'package:share_plus/share_plus.dart';

class ImageViewerScreen extends StatefulWidget {
  final RtcClient client;
  final String remotePath;
  final String fileName;

  const ImageViewerScreen({
    super.key,
    required this.client,
    required this.remotePath,
    required this.fileName,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> with FileTransferMixin {
  @override
  RtcClient get client => widget.client;

  File? _imageFile;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setupTransferListener();
    _loadFile();
  }

  @override
  void refreshDirectory() {}

  void _loadFile() {
    downloadFile(
      widget.remotePath,
      showNotification: false,
      onComplete: (file) async {
        setState(() {
          _imageFile = file;
          _isInitialized = true;
        });
      },
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildBody(),
          ),

          if (_isInitialized)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildTinyStatusBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.neonCyan),
            const SizedBox(height: 16),
            Text(
              transferMsg.isEmpty ? "FETCHING IMAGE..." : transferMsg,
              style: const TextStyle(
                color: AppColors.neonCyan,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.file(
          _imageFile!,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildTinyStatusBar() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.deepSpace.withValues(alpha: 0.8),
        border: const Border(
          top: BorderSide(color: AppColors.neonCyan, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.chevron_left,
              color: AppColors.neonCyan,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "${widget.fileName}  —  ${widget.remotePath}",
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 10,
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.share, color: AppColors.neonCyan, size: 16),
            onPressed: () {
              if (_imageFile != null) {
                SharePlus.instance.share(ShareParams(
                  files: [XFile(_imageFile!.path)],
                  text: widget.fileName,
                ));
              }
            },
          ),
          const SizedBox(width: 12),
          const Icon(Icons.image_outlined, color: AppColors.neonCyan, size: 16),
        ],
      ),
    );
  }
}
