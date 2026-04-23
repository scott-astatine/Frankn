import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/host_list_panel.dart';
import 'package:frankn/widgets/quick_functions.dart';

class MobileLayout extends StatelessWidget {
  final RtcThinClient client;
  const MobileLayout({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HostConnectionState>(
      stream: client.hostStateStream,
      initialData: client.currentHostState,
      builder: (context, snapshot) {
        final isAuthenticated =
            snapshot.data == HostConnectionState.authenticated;
        return isAuthenticated
            ? QuickFunction(client: client)
            : HostListPanel(client: client);
      },
    );
  }
}
