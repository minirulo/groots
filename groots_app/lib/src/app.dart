import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import 'config/environment.dart';
import 'config/theme.dart';
import 'service_layer/app_binding.dart';
import 'service_layer/blocs/admin/admin_bloc.dart';
import 'service_layer/blocs/album/album_bloc.dart';
import 'service_layer/blocs/authentication/authentication_bloc.dart';
import 'service_layer/blocs/library/library_bloc.dart';
import 'service_layer/blocs/playlist/playlist_bloc.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/splash_page.dart';

class SoundNetApp extends StatelessWidget {
  const SoundNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => Get.find<AuthenticationBloc>()),
        BlocProvider(create: (_) => Get.find<LibraryBloc>()),
        BlocProvider(create: (_) => Get.find<AlbumBloc>()),
        BlocProvider(create: (_) => Get.find<PlaylistBloc>()),
        BlocProvider(create: (_) => Get.find<AdminBloc>()),
      ],
      child: GetMaterialApp(
        title: Environment().config.appName,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        initialBinding: AppBinding(),
        initialRoute: SplashPage.route,
        getPages: [
          GetPage(name: SplashPage.route, page: () => const SplashPage()),
          GetPage(name: LoginPage.route, page: () => const LoginPage()),
          GetPage(name: HomePage.route, page: () => const HomePage()),
        ],
      ),
    );
  }
}
