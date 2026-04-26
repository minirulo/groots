import 'dart:convert';
import 'package:http_interceptor/http_interceptor.dart';

import '../../config/environment.dart';

class AuthProvider {
  final InterceptedClient _client;

  AuthProvider(this._client);

  String get _base => Environment().config.apiBaseUrl;

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'email': email, 'password': password}),
    );
    if (res.statusCode != 201) throw Exception(res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<String> login({required String email, required String password}) async {
    final res = await _client.post(
      Uri.parse('$_base/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    if (res.statusCode != 200) throw Exception(res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['access_token'] as String;
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _client.get(Uri.parse('$_base/users/me'));
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
