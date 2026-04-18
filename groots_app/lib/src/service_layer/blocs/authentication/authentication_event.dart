abstract class AuthenticationEvent {}

class AuthenticationStarted extends AuthenticationEvent {}

class AuthenticationLoginRequested extends AuthenticationEvent {
  final String email;
  final String password;
  AuthenticationLoginRequested({required this.email, required this.password});
}

class AuthenticationRegisterRequested extends AuthenticationEvent {
  final String username;
  final String email;
  final String password;
  AuthenticationRegisterRequested({
    required this.username,
    required this.email,
    required this.password,
  });
}

class AuthenticationLogoutRequested extends AuthenticationEvent {}
