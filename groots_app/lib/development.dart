import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

import 'src/config/environment.dart';
import 'src/init.dart';
import 'src/service_layer/ipfs_local_node.dart';

void main() async {
  Environment().initConfig(Environment.development);
  await init();

  // Start the local Kubo peer after the widget tree (and AppBinding) are up.
  // Non-blocking — the app streams from the central node while the daemon warms up.
  SchedulerBinding.instance.addPostFrameCallback((_) {
    final node = Get.find<IpfsLocalNode>();
    node.start().ignore();
  });
}
