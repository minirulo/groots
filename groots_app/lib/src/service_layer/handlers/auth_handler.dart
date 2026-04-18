import '../../adapters/providers/auth_provider.dart';
import '../../adapters/storage.dart';
import '../commands.dart';

class AuthHandler {
  final AuthProvider _provider;
  final SecureStorage _storage;

  AuthHandler({required AuthProvider provider, required SecureStorage storage})
      : _provider = provider,
        _storage = storage;

  Future<void> login(LoginCommand cmd) async {
    final token = await _provider.login(email: cmd.email, password: cmd.password);
    await _storage.saveToken(token);
  }

  Future<void> register(RegisterCommand cmd) async {
    await _provider.register(username: cmd.username, email: cmd.email, password: cmd.password);
  }

  Future<void> logout() async {
    await _storage.deleteToken();
  }
}
