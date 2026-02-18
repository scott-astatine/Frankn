import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';

class ProcessManagerScreen extends StatefulWidget {
  final RtcClient client;
  const ProcessManagerScreen({super.key, required this.client});

  @override
  State<ProcessManagerScreen> createState() => _ProcessManagerScreenState();
}

class _ProcessManagerScreenState extends State<ProcessManagerScreen> {
  List<dynamic> _processes = [];
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _fetchProcesses();

    widget.client.commandResponseStream.listen((resp) {
      if (mounted) {
        final Map<String, dynamic> data;
        if (resp['type'] == 'response' && resp.containsKey('data')) {
          data = resp['data'] as Map<String, dynamic>;
        } else {
          data = resp;
        }

        if (data.containsKey('processes')) {
          setState(() {
            _processes = data['processes'];
            _stats = data['stats'];
            _isLoading = false;
          });
        } else if (data.containsKey('message') &&
            data['message'].toString().contains("Terminated")) {
          _showSnack(data['message'], AppColors.matrixGreen);
          _fetchProcesses();
        }
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
      ),
    );
  }

  void _fetchProcesses() {
    setState(() => _isLoading = true);
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.ListProcesses});
  }

  void _killProcess(String pid, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelGrey,
        shape: const BeveledRectangleBorder(
          side: BorderSide(color: AppColors.errorRed, width: 1),
        ),
        title: const Text(
          "TERMINATE PROCESS",
          style: TextStyle(
            color: AppColors.errorRed,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          "Confirm termination of $name (PID: $pid)?",
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              widget.client.sendDcMsg({
                DcMsg.Key: DcMsg.Kill,
                "proc": pid,
              });
            },
            child: const Text("CONFIRM"),
          ),
        ],
      ),
    );
  }

  void _showDetails(dynamic proc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.voidBlack,
        shape: const BeveledRectangleBorder(
          side: BorderSide(color: AppColors.neonCyan),
        ),
        title: Text(
          proc['name'].toString().toUpperCase(),
          style: const TextStyle(
            color: AppColors.neonCyan,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow("PID", proc['pid'].toString()),
              _buildDetailRow("STATUS", proc['status'].toString()),
              _buildDetailRow(
                "CPU",
                "${(proc['cpu'] as num).toStringAsFixed(1)}%",
              ),
              _buildDetailRow(
                "MEM",
                FileUtils.formatSize((proc['memory'] as num).toInt()),
              ),
              const SizedBox(height: 12),
              const Text(
                "COMMAND:",
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  proc['cmd'] ?? "N/A",
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 11,
                    color: AppColors.matrixGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "CLOSE",
              style: TextStyle(color: AppColors.neonCyan),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredProcs = _processes
        .where(
          (p) => p['name'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildSystemStats(),
                _buildSearchBar(),
                if (_isLoading && _processes.isEmpty)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.neonCyan,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        0,
                        8,
                        0,
                        40,
                      ), // Extra bottom padding for status bar
                      itemCount: filteredProcs.length,
                      itemBuilder: (context, index) {
                        final proc = filteredProcs[index];
                        return _buildProcessItem(proc);
                      },
                    ),
                  ),
              ],
            ),
          ),

          if (!isKeyboardVisible)
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

  Widget _buildTinyStatusBar() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.deepSpace.withValues(alpha: 0.9),
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
          const Text(
            "PROCESS_CORE",
            style: TextStyle(
              color: AppColors.textGrey,
              fontSize: 10,
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          if (_isLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.neonCyan,
              ),
            )
          else
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                Icons.refresh,
                color: AppColors.neonCyan,
                size: 16,
              ),
              onPressed: _fetchProcesses,
            ),
        ],
      ),
    );
  }

  Widget _buildSystemStats() {
    if (_stats == null) return const SizedBox.shrink();
    final cpu = (_stats!['cpu_load'] as num).toDouble();
    final usedMem = (_stats!['used_mem'] as num).toInt();
    final totalMem = (_stats!['total_mem'] as num).toInt();
    final memPerc = (usedMem / totalMem);

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.panelGrey.withValues(alpha: 0.3),
      child: Row(
        children: [
          Expanded(
            child: _buildStatMini(
              "CPU_LOAD",
              cpu / 100,
              "${cpu.toStringAsFixed(1)}%",
              AppColors.neonPink,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildStatMini(
              "MEM_USAGE",
              memPerc,
              "${(memPerc * 100).round()}%",
              AppColors.neonCyan,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatMini(String label, double val, String text, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: val.clamp(0.0, 1.0),
          backgroundColor: color.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 2,
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          hintText: "FILTER PROCESSES...",
          hintStyle: TextStyle(
            color: AppColors.textGrey.withValues(alpha: 0.5),
            fontSize: 12,
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: AppColors.neonCyan,
            size: 18,
          ),
          isDense: true,
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: AppColors.neonCyan.withValues(alpha: 0.3),
            ),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.neonCyan),
          ),
        ),
      ),
    );
  }

  Widget _buildProcessItem(dynamic proc) {
    final cpu = (proc['cpu'] as num).toDouble();
    final mem = (proc['memory'] as num).toInt();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.panelGrey.withValues(alpha: 0.4),
        border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _showDetails(proc),
        title: Text(
          proc['name'].toString().toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            children: [
              _buildBadge("P: ${proc['pid']}", AppColors.textGrey),
              const SizedBox(width: 8),
              _buildBadge(
                "C: ${cpu.toStringAsFixed(1)}%",
                cpu > 50 ? AppColors.errorRed : AppColors.cyberYellow,
              ),
              const SizedBox(width: 8),
              _buildBadge(
                "M: ${FileUtils.formatSize(mem)}",
                AppColors.matrixGreen,
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, color: AppColors.errorRed, size: 18),
          onPressed: () => _killProcess(proc['pid'].toString(), proc['name']),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontFamily: 'Courier',
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
