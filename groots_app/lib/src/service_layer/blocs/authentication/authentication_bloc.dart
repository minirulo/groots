import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../adapters/providers/auth_provider.dart';
import '../../../adapters/storage.dart';
import '../../../domain/models/user.dart';
import '../../commands.dart';
import '../../messagebus.dart';
import 'authentication_event.dart';
import 'authentication_state.dart';

class AuthenticationBloc extends Bloc<AuthenticationEvent, AuthenticationState> {
  final Messagebus _bus;
  final AuthProvider _authProvider;
  final SecureStorage _storage;

  AuthenticationBloc({
    required Messagebus bus,
    required AuthProvider authProvider,
    required SecureStorage storage,
  })  : _bus = bus,
        _authProvider = authProvider,
        _storage = storage,
        super(const AuthenticationState.unknown()) {
    on<AuthenticationStarted>(_onStarted);
    on<AuthenticationLoginRequested>(_onLoginRequested);
    on<AuthenticationRegisterRequested>(_onRegisterRequested);
    on<AuthenticationLogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onStarted(AuthenticationStarted event, Emitter<AuthenticationState> emit) async {
    final token = await _storage.getToken();
    if (token == null) {
      emit(const AuthenticationState.unauthenticated());
      return;
    }
    try {
      final data = await _authProvider.getMe();
      emit(AuthenticationState.authenticated(User.fromJson(data)));
    } catch (_) {
      await _storage.deleteToken();
      emit(const AuthenticationState.unauthenticated());
    }
  }

  Future<void> _onLoginRequested(
    AuthenticationLoginRequested event,
    Emitter<AuthenticationState> emit,
  ) async {
    try {
      await _bus.handle(LoginCommand(email: event.email, password: event.password));
      final data = await _authProvider.getMe();
      emit(AuthenticationState.authenticated(User.fromJson(data)));
    } catch (e) {
      emit(AuthenticationState.unauthenticated(error: e.toString()));
    }
  }

  Future<void> _onRegisterRequested(
    AuthenticationRegisterRequested event,
    Emitter<AuthenticationState> emit,
  ) async {
    try {
      await _bus.handle(RegisterCommand(
        username: event.username,
        email: event.email,
        password: event.password,
      ));
      await _bus.handle(LoginCommand(email: event.email, password: event.password));
      final data = await _authProvider.getMe();
      emit(AuthenticationState.authenticated(User.fromJson(data)));
    } catch (e) {
      emit(AuthenticationState.unauthenticated(error: e.toString()));
    }
  }

  Future<void> _onLogoutRequested(
    AuthenticationLogoutRequested event,
    Emitter<AuthenticationState> emit,
  ) async {
    await _bus.handle(LogoutCommand());
    emit(const AuthenticationState.unauthenticated());
  }
}
