import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';

import '../../config/environment.dart';
import '../../domain/models/album.dart';
import '../../domain/models/track.dart';

class AdminProvider {
  final InterceptedClient _client;

  AdminProvider(this._client);

  String get _base => Environment().config.apiBaseUrl;

  Future<Map<String, dynamic>> ingestTrack({
    required String filename,
    required List<int> content,
    required String mimeType,
  }) async {
    final uri = Uri.parse('$_base/admin/library/ingest');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      content,
      filename: filename,
    ));

    // Copy auth headers from intercepted client by making a dummy request pattern
    // We use the raw multipart approach and manually attach the auth token
    final streamedResponse = await _client.send(request);
    final res = await http.Response.fromStream(streamedResponse);
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Track>> getCentralLibrary() async {
    final res = await _client.get(Uri.parse('$_base/admin/library'));
    if (res.statusCode != 200) throw Exception(res.body);
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Album>> searchAlbums(String query) async {
    final uri = Uri.parse('$_base/albums/search').replace(
      queryParameters: {'q': query},
    );
    final res = await _client.get(uri);
    if (res.statusCode != 200) throw Exception(res.body);
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
  }
}
