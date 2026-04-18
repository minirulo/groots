import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

import 'src/config/environment.dart';
import 'src/init.dart';
import 'src/service_layer/ipfs_local_node.dart';

void main() async {
  Environment().initConfig(Environment.production);
  await init();

  SchedulerBinding.instance.addPostFrameCallback((_) {
    final node = Get.find<IpfsLocalNode>();
    node.start().ignore();
  });
}
