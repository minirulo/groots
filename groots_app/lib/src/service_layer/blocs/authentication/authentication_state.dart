import '../../../domain/models/user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthenticationState {
  final AuthStatus status;
  final User? user;
  final String? error;

  const AuthenticationState._({required this.status, this.user, this.error});

  const AuthenticationState.unknown() : this._(status: AuthStatus.unknown);
  const AuthenticationState.authenticated(User user)
      : this._(status: AuthStatus.authenticated, user: user);
  const AuthenticationState.unauthenticated({String? error})
      : this._(status: AuthStatus.unauthenticated, error: error);
}
