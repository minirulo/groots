import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service_layer/ipfs_local_node.dart';

/// AppBar indicator that shows the local IPFS node status and allows the user
/// to start or stop the daemon with a single tap.
///
/// Only rendered on macOS — returns an empty widget on all other platforms.
class IpfsStatusIndicator extends StatelessWidget {
  const IpfsStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || (!Platform.isMacOS && !Platform.isLinux)) return const SizedBox.shrink();

    final node = Get.find<IpfsLocalNode>();

    return Obx(() {
      final nodeStatus = node.status.value;
      final busy = nodeStatus == IpfsNodeStatus.starting ||
          nodeStatus == IpfsNodeStatus.stopping;

      final Color dotColor;
      final String tooltip;

      switch (nodeStatus) {
        case IpfsNodeStatus.running:
          dotColor = Colors.greenAccent;
          tooltip = 'Local IPFS node: running — tap to stop';
        case IpfsNodeStatus.starting:
          dotColor = Colors.amber;
          tooltip = 'Local IPFS node: starting…';
        case IpfsNodeStatus.stopping:
          dotColor = Colors.orange;
          tooltip = 'Local IPFS node: stopping…';
        case IpfsNodeStatus.stopped:
          dotColor = Colors.grey;
          tooltip = 'Local IPFS node: stopped — tap to start';
      }

      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: busy
              ? null
              : () {
                  if (node.isRunning.value) {
                    node.stop();
                  } else {
                    node.start();
                  }
                },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                busy
                    ? SizedBox(
                        width: 8,
                        height: 8,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: dotColor,
                        ),
                      )
                    : Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: dotColor.withAlpha(120),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                const SizedBox(width: 6),
                Text(
                  'IPFS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: busy ? 0.5 : 0.8),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
