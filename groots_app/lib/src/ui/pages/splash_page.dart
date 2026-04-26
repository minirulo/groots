import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../service_layer/blocs/authentication/authentication_bloc.dart';
import '../../service_layer/blocs/authentication/authentication_event.dart';
import '../../service_layer/blocs/authentication/authentication_state.dart';
import 'home_page.dart';
import 'login_page.dart';

class SplashPage extends StatefulWidget {
  static const route = '/';
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    context.read<AuthenticationBloc>().add(AuthenticationStarted());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthenticationBloc, AuthenticationState>(
      listener: (context, state) {
        switch (state.status) {
          case AuthStatus.authenticated:
            Navigator.of(context).pushReplacementNamed(HomePage.route);
          case AuthStatus.unauthenticated:
            Navigator.of(context).pushReplacementNamed(LoginPage.route);
          case AuthStatus.unknown:
            break;
        }
      },
      child: const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
