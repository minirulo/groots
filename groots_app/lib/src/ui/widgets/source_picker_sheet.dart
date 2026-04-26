import 'package:flutter/material.dart';

import '../../domain/models/music_source.dart';

class SourcePickerSheet extends StatelessWidget {
  const SourcePickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Where is this music from?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'This helps us track the origin of your collection.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ...MusicSource.values.map(
              (source) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(source.icon, color: scheme.primary),
                title: Text(source.label),
                subtitle: Text(
                  source.description,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                onTap: () => Navigator.pop(context, source),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
