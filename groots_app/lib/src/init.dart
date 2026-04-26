import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app.dart';
import 'service_layer/audio_handler.dart';

Future<void> init() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audioHandler = await AudioService.init(
    builder: () => SoundNetAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'net.groots.channel.audio',
      androidNotificationChannelName: 'Groots',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  Get.put<SoundNetAudioHandler>(audioHandler);

  runApp(const SoundNetApp());
}
