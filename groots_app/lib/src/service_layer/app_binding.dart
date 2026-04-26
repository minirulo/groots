import 'package:get/get.dart';
import 'package:http_interceptor/http_interceptor.dart';

import '../adapters/interceptor.dart';
import '../adapters/providers/admin_provider.dart';
import '../adapters/providers/album_provider.dart';
import '../adapters/providers/auth_provider.dart';
import '../adapters/providers/discogs_provider.dart';
import '../adapters/providers/library_provider.dart';
import '../adapters/providers/playlist_provider.dart';
import '../adapters/storage.dart';
import 'blocs/admin/admin_bloc.dart';
import 'blocs/album/album_bloc.dart';
import 'blocs/authentication/authentication_bloc.dart';
import 'blocs/library/library_bloc.dart';
import 'blocs/playlist/playlist_bloc.dart';
import 'handlers/admin_handler.dart';
import 'handlers/album_handler.dart';
import 'handlers/auth_handler.dart';
import 'handlers/library_handler.dart';
import 'handlers/playlist_handler.dart';
import 'ipfs_local_node.dart';
import 'messagebus.dart';
import 'audio_handler.dart';
import 'player_service.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    final storage = SecureStorage();
    Get.put(storage);

    final client = InterceptedClient.build(
      interceptors: [AuthInterceptor(storage)],
      requestTimeout: const Duration(seconds: 15),
    );

    final authProvider = AuthProvider(client);
    final libraryProvider = LibraryProvider(client, storage);
    final albumProvider = AlbumProvider(client);
    final playlistProvider = PlaylistProvider(client);
    final adminProvider = AdminProvider(client);
    final discogsProvider = DiscogsProvider(client);
    Get.put(authProvider);
    Get.put(libraryProvider);
    Get.put(albumProvider);
    Get.put(playlistProvider);
    Get.put(adminProvider);
    Get.put(discogsProvider);

    final bus = Messagebus(
      authHandler: AuthHandler(provider: authProvider, storage: storage),
      libraryHandler: LibraryHandler(provider: libraryProvider),
      albumHandler: AlbumHandler(provider: albumProvider),
      playlistHandler: PlaylistHandler(provider: playlistProvider),
      adminHandler: AdminHandler(
        adminProvider: adminProvider,
        albumProvider: albumProvider,
      ),
    );
    Get.put(bus);

    // Register the local IPFS node — started lazily from the dev entry point.
    Get.put(IpfsLocalNode(), permanent: true);

    Get.put(
      AuthenticationBloc(
        bus: bus,
        authProvider: authProvider,
        storage: storage,
      ),
    );

    Get.put(LibraryBloc(bus: bus));
    Get.put(AlbumBloc(bus: bus));
    Get.put(PlaylistBloc(bus: bus));
    Get.put(AdminBloc(bus: bus));
    Get.put(PlayerService(Get.find<SoundNetAudioHandler>()));
  }
}
