import 'dart:convert';
import 'package:http_interceptor/http_interceptor.dart';

import '../../config/environment.dart';
import '../../domain/models/discogs.dart';

class DiscogsProvider {
  final InterceptedClient _client;

  DiscogsProvider(this._client);

  String get _base => Environment().config.apiBaseUrl;

  Future<List<DiscogsReleaseSummary>> search({
    String? barcode,
    String? artist,
    String? album,
    String? q,
    String? format,
  }) async {
    final params = <String, String>{
      if (barcode != null) 'barcode': barcode,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (q != null) 'q': q,
      if (format != null) 'format': format,
    };
    final uri =
        Uri.parse('$_base/discogs/search').replace(queryParameters: params);
    final res = await _client.get(uri);
    if (res.statusCode != 200) throw Exception(res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = data['results'] as List;
    return results
        .map((r) => DiscogsReleaseSummary.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<DiscogsRelease> getRelease(int releaseId) async {
    final res =
        await _client.get(Uri.parse('$_base/discogs/releases/$releaseId'));
    if (res.statusCode != 200) throw Exception(res.body);
    return DiscogsRelease.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }
}
