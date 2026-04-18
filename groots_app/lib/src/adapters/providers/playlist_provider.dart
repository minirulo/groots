import 'dart:convert';

import 'package:http_interceptor/http_interceptor.dart';

import '../../config/environment.dart';
import '../../domain/models/playlist.dart';

class PlaylistProvider {
  final InterceptedClient _client;

  PlaylistProvider(this._client);

  String get _base => Environment().config.apiBaseUrl;

  Future<List<Playlist>> getPlaylists() async {
    final res = await _client.get(Uri.parse('$_base/playlists'));
    if (res.statusCode != 200) throw Exception(res.body);
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String> createPlaylist(String name) async {
    final res = await _client.post(
      Uri.parse('$_base/playlists'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode != 201) throw Exception(res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['playlist_id'] as String;
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    final res = await _client.patch(
      Uri.parse('$_base/playlists/$playlistId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final res = await _client.delete(Uri.parse('$_base/playlists/$playlistId'));
    if (res.statusCode != 204) throw Exception(res.body);
  }

  Future<void> addTrack(String playlistId, String trackId) async {
    final res = await _client.post(
      Uri.parse('$_base/playlists/$playlistId/tracks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'track_id': trackId}),
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    final res = await _client
        .delete(Uri.parse('$_base/playlists/$playlistId/tracks/$trackId'));
    if (res.statusCode != 200) throw Exception(res.body);
  }
}
