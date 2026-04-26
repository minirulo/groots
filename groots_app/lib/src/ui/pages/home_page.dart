import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../service_layer/blocs/admin/admin_bloc.dart';
import '../../service_layer/blocs/admin/admin_event.dart';
import '../../service_layer/blocs/album/album_bloc.dart';
import '../../service_layer/blocs/album/album_event.dart';
import '../../service_layer/blocs/authentication/authentication_bloc.dart';
import '../../service_layer/blocs/authentication/authentication_event.dart';
import '../../service_layer/blocs/authentication/authentication_state.dart';
import 'login_page.dart';
import '../../service_layer/blocs/library/library_bloc.dart';
import '../../service_layer/blocs/library/library_event.dart';
import '../../service_layer/blocs/playlist/playlist_bloc.dart';
import '../../service_layer/blocs/playlist/playlist_event.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

import '../../domain/models/album.dart';
import '../../domain/models/track.dart';
import '../views/admin_view.dart';
import '../views/albums_view.dart';
import '../views/playlists_view.dart';
import '../views/search_view.dart';
import '../views/sync_view.dart';
import '../widgets/ipfs_status_indicator.dart';
import '../widgets/player_bar.dart';

class HomePage extends StatefulWidget {
  static const route = '/home';
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  Album? _pendingAlbum;
  String? _pendingTrackId;
  AlbumSortBy _albumSortBy = AlbumSortBy.albumName;

  @override
  void initState() {
    super.initState();
    context.read<LibraryBloc>().add(LibraryLoadRequested());
    context.read<AlbumBloc>().add(AlbumLoadRequested());
    context.read<PlaylistBloc>().add(PlaylistLoadRequested());
    final isAdmin =
        context.read<AuthenticationBloc>().state.user?.isAdmin ?? false;
    if (isAdmin) {
      context.read<AdminBloc>().add(AdminCentralLibraryLoadRequested());
    }
  }

  void _navigateToTrack(Track track) {
    if (track.albumId == null) return;
    final albumState = context.read<AlbumBloc>().state;
    final matches = albumState.albums.where((a) => a.id == track.albumId);
    if (matches.isEmpty) return;
    setState(() {
      _index = 0;
      _pendingAlbum = matches.first;
      _pendingTrackId = track.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthenticationBloc>().state;
    final isAdmin = authState.user?.isAdmin ?? false;

    final isMobile = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };

    final pages = [
      AlbumsView(
        pendingAlbum: _pendingAlbum,
        onPendingAlbumConsumed: () => setState(() => _pendingAlbum = null),
        pendingTrackId: _pendingTrackId,
        onPendingTrackIdConsumed: () => setState(() => _pendingTrackId = null),
        sortBy: _albumSortBy,
        onSortChanged: (v) => setState(() => _albumSortBy = v),
      ),
      const PlaylistsView(),
      if (isMobile) SearchView(onTrackTapped: _navigateToTrack),
      if (!isMobile)
        SyncView(
          onSyncComplete: (album) => setState(() {
            _index = 0;
            _pendingAlbum = album;
          }),
        ),
      if (isAdmin && !isMobile) const AdminView(),
    ];

    // Clamp _index in case admin tab disappears (e.g. after re-auth)
    final safeIndex = _index.clamp(0, pages.length - 1);

    final mobileDestinations = [
      const NavigationDestination(
        icon: Icon(Icons.library_music_outlined),
        selectedIcon: Icon(Icons.library_music),
        label: 'Library',
      ),
      const NavigationDestination(
        icon: Icon(Icons.queue_music_outlined),
        selectedIcon: Icon(Icons.queue_music),
        label: 'Playlists',
      ),
      const NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: 'Search',
      ),
    ];

    final railDestinations = [
      const NavigationRailDestination(
        icon: Icon(Icons.album),
        label: Text('Library'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.queue_music),
        label: Text('Playlists'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.sync),
        label: Text('Sync'),
      ),
      if (isAdmin)
        const NavigationRailDestination(
          icon: Icon(Icons.admin_panel_settings),
          label: Text('Admin'),
        ),
    ];

    final body = Column(
      children: [
        Expanded(
          child: isMobile
              ? pages[safeIndex]
              : Row(
                  children: [
                    NavigationRail(
                      selectedIndex: safeIndex,
                      onDestinationSelected: (i) => setState(() => _index = i),
                      labelType: NavigationRailLabelType.all,
                      destinations: railDestinations,
                    ),
                    const VerticalDivider(thickness: 1, width: 1),
                    Expanded(child: pages[safeIndex]),
                  ],
                ),
        ),
        const PlayerBar(),
      ],
    );

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Groots'),
        actions: [
          const IpfsStatusIndicator(),
          if (isAdmin && !isMobile)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Admin',
                child: Icon(
                  Icons.verified_user,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
            ),
          if (isMobile && safeIndex == 0)
            PopupMenuButton<AlbumSortBy>(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Sort by',
              initialValue: _albumSortBy,
              onSelected: (v) => setState(() => _albumSortBy = v),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: AlbumSortBy.albumName,
                  child: ListTile(
                    leading: const Icon(Icons.album_outlined),
                    title: const Text('Album'),
                    trailing: _albumSortBy == AlbumSortBy.albumName
                        ? const Icon(Icons.check, size: 18)
                        : null,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: AlbumSortBy.artistName,
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Artist'),
                    trailing: _albumSortBy == AlbumSortBy.artistName
                        ? const Icon(Icons.check, size: 18)
                        : null,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: AlbumSortBy.genre,
                  child: ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Genre'),
                    trailing: _albumSortBy == AlbumSortBy.genre
                        ? const Icon(Icons.check, size: 18)
                        : null,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => context.read<AuthenticationBloc>().add(
              AuthenticationLogoutRequested(),
            ),
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: isMobile
          ? NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (i) => setState(() => _index = i),
              indicatorColor: Colors.transparent,
              destinations: mobileDestinations,
            )
          : null,
    );

    // CupertinoScaffold enables the iOS-style card-push effect when the player
    // sheet opens via showCupertinoModalBottomSheet.
    final view = isMobile
        ? CupertinoScaffold(
            transitionBackgroundColor: Colors.black,
            body: scaffold,
          )
        : scaffold;

    return BlocListener<AuthenticationBloc, AuthenticationState>(
      listenWhen: (_, state) => state.status == AuthStatus.unauthenticated,
      listener: (context, _) =>
          Navigator.of(context).pushReplacementNamed(LoginPage.route),
      child: view,
    );
  }
}
