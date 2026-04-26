import 'package:flutter/material.dart';

enum MusicSource {
  cd,
  vinyl,
  digitalDownload,
  streamingPurchase,
  other;

  String get label => switch (this) {
        cd => 'CD',
        vinyl => 'Vinyl / LP',
        digitalDownload => 'Digital Download',
        streamingPurchase => 'Streaming Purchase',
        other => 'Other',
      };

  String get description => switch (this) {
        cd => 'Ripped from a physical CD',
        vinyl => 'Recorded from a vinyl record',
        digitalDownload => 'Purchased and downloaded',
        streamingPurchase => 'Bought via a streaming service',
        other => 'Another source',
      };

  String get apiValue => switch (this) {
        cd => 'cd',
        vinyl => 'vinyl',
        digitalDownload => 'digital_download',
        streamingPurchase => 'streaming_purchase',
        other => 'other',
      };

  IconData get icon => switch (this) {
        cd => Icons.album_outlined,
        vinyl => Icons.radio_outlined,
        digitalDownload => Icons.download_outlined,
        streamingPurchase => Icons.headphones_outlined,
        other => Icons.more_horiz,
      };
}
