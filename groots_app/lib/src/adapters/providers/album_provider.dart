import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';

import 'package:get/get.dart';

import '../../config/environment.dart';
import '../../domain/models/album.dart';
import '../../service_layer/ipfs_local_node.dart';

class AlbumProvider {
  final InterceptedClient _client;

  AlbumProvider(this._client);

  String get _base => Environment().config.apiBaseUrl;

  Future<List<Album>> getAlbums() async {
    final res = await _client.get(Uri.parse('$_base/albums'));
    if (res.statusCode != 200) throw Exception(res.body);
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Album> getAlbum(String albumId) async {
    final res = await _client.get(Uri.parse('$_base/albums/$albumId'));
    if (res.statusCode != 200) throw Exception(res.body);
    return Album.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<String> createAlbum(Map<String, dynamic> payload) async {
    final res = await _client.post(
      Uri.parse('$_base/albums'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode != 201) throw Exception(res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['album_id'] as String;
  }

  Future<void> updateAlbum(String albumId, Map<String, dynamic> payload) async {
    final res = await _client.put(
      Uri.parse('$_base/albums/$albumId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  Future<void> deleteAlbum(String albumId) async {
    final res = await _client.delete(Uri.parse('$_base/albums/$albumId'));
    if (res.statusCode != 204) throw Exception(res.body);
  }

  Future<void> assignTrack(
    String albumId,
    String trackId, {
    int? trackNumber,
    int? discNumber,
    String? side,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/albums/$albumId/tracks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'track_id': trackId,
        'track_number': trackNumber,
        'disc_number': discNumber,
        'side': side,
      }),
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  Future<void> unassignTrack(String albumId, String trackId) async {
    final res = await _client.delete(
      Uri.parse('$_base/albums/$albumId/tracks/$trackId'),
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  Future<List<Album>> searchAlbums(String query) async {
    final uri = Uri.parse(
      '$_base/albums/search',
    ).replace(queryParameters: {'q': query});
    final res = await _client.get(uri);
    if (res.statusCode != 200) throw Exception(res.body);
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<String>> getGenres() async {
    final res = await _client.get(Uri.parse('$_base/genres'));
    if (res.statusCode != 200) throw Exception(res.body);
    return (jsonDecode(res.body) as List).cast<String>();
  }

  Future<List<Album>> getCatalogue() async {
    final res = await _client.get(Uri.parse('$_base/albums/catalogue'));
    if (res.statusCode != 200) throw Exception(res.body);
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> uploadCover(String albumId, Uint8List bytes, String mime) async {
    final ext = mime.endsWith('png') ? 'png' : 'jpg';
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_base/albums/$albumId/cover'),
    );
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: 'cover.$ext'),
    );
    final streamed = await _client.send(req);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) throw Exception(body);
  }

  String coverUrl(String cid) => Get.find<IpfsLocalNode>().coverUrl(cid);
}
