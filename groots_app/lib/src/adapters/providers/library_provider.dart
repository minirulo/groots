import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';

import '../../config/environment.dart';
import '../../domain/models/track.dart';
import '../storage.dart';

typedef CoverResult = ({Uint8List bytes, String mime});

class LibraryProvider {
  final InterceptedClient _client;
  final SecureStorage _storage;

  LibraryProvider(this._client, this._storage);

  String get _base => Environment().config.apiBaseUrl;

  Future<List<Track>> getTracks() async {
    final res = await _client.get(Uri.parse('$_base/library'));
    if (res.statusCode != 200) throw Exception(res.body);
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> addTrack(Map<String, dynamic> payload) async {
    final res = await _client.post(
      Uri.parse('$_base/library'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode != 201) throw Exception(res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Mobile upload: sends raw bytes as multipart to POST /library/upload.
  /// The server handles ipfs add + pin + register in one call.
  /// Optional [source] declares the music origin (e.g. "cd", "vinyl").
  Future<Map<String, dynamic>> uploadTrack({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String? source,
    String? hintArtist,
    String? hintTitle,
    String? hintAlbum,
    int? hintYear,
    int? hintTrackNumber,
  }) async {
    final token = await _storage.getToken();
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_base/library/upload'),
    );
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    if (source != null) req.fields['source'] = source;
    if (hintArtist != null) req.fields['hint_artist'] = hintArtist;
    if (hintTitle != null) req.fields['hint_title'] = hintTitle;
    if (hintAlbum != null) req.fields['hint_album'] = hintAlbum;
    if (hintYear != null) req.fields['hint_year'] = hintYear.toString();
    if (hintTrackNumber != null) req.fields['hint_track_number'] = hintTrackNumber.toString();
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 201) throw Exception(body);
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<void> removeTrack(String trackId) async {
    final res = await _client.delete(Uri.parse('$_base/library/$trackId'));
    if (res.statusCode != 204) throw Exception(res.body);
  }

  Future<void> pinTrack(String trackId) async {
    final res = await _client.post(Uri.parse('$_base/library/$trackId/pin'));
    if (res.statusCode != 200) throw Exception(res.body);
  }

  Future<String> getStreamUrl(String trackId) async {
    final res = await _client.get(Uri.parse('$_base/library/$trackId/stream'));
    if (res.statusCode != 200) throw Exception(res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['stream_url'] as String;
  }

  /// Sends the first [headBytes] of an audio file to the server and returns
  /// the embedded cover art, or null if none is found.
  Future<CoverResult?> extractCover({
    required Uint8List headBytes,
    required String filename,
  }) async {
    final token = await _storage.getToken();
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_base/library/extract-cover'),
    );
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(
      http.MultipartFile.fromBytes('file', headBytes, filename: filename),
    );
    final streamed = await req.send();
    if (streamed.statusCode == 204) return null;
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) throw Exception(body);
    final data = jsonDecode(body) as Map<String, dynamic>;
    return (
      bytes: base64Decode(data['data'] as String),
      mime: data['mime'] as String,
    );
  }
}
