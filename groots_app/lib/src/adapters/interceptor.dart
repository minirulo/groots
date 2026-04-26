import 'package:http_interceptor/http_interceptor.dart';

import 'storage.dart';

class AuthInterceptor implements InterceptorContract {
  final SecureStorage _storage;

  AuthInterceptor(this._storage);

  @override
  Future<BaseRequest> interceptRequest({required BaseRequest request}) async {
    final token = await _storage.getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.headers['X-Groots-Client'] = 'groots-macos';
    return request;
  }

  @override
  Future<BaseResponse> interceptResponse({
    required BaseResponse response,
  }) async => response;

  @override
  Future<bool> shouldInterceptRequest() async => true;

  @override
  Future<bool> shouldInterceptResponse() async => true;
}
