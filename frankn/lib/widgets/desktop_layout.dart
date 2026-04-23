import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/host_list_panel.dart';
import 'package:frankn/widgets/quick_functions.dart';

class DesktopLayout extends StatelessWidget {
  const DesktopLayout({super.key, required RtcThinClient client})
    : _client = client;

  final RtcThinClient _client;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 1, child: HostListPanel(client: _client)),
        const VerticalDivider(color: AppColors.neonCyan, width: 1),
        Expanded(
          flex: 3,
          child: StreamBuilder<HostConnectionState>(
            stream: _client.hostStateStream,
            initialData: _client.currentHostState,
            builder: (context, snapshot) {
              if (snapshot.data == HostConnectionState.authenticated) {
                return QuickFunction(client: _client);
              }
              return const Center(
                child: Text(
                  "WAITING FOR UPLINK...",
                  style: TextStyle(
                    color: AppColors.textGrey,
                    letterSpacing: 1.5,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
