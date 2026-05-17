from dependency_injector import containers, providers

from groots.adapters.impl.audio_fingerprinter import AudioFingerprinter
from groots.adapters.impl.discogs_client import DiscogsClient
from groots.adapters.impl.ipfs_client import IPFSClient
from groots.adapters.impl.metadata_extractor import MetadataExtractor
from groots.domain.commands import (
    AddTrack,
    AddTrackToPlaylist,
    AssignTrackToAlbum,
    CreateAlbum,
    CreatePlaylist,
    DeleteAlbum,
    DeletePlaylist,
    IngestCentralTrack,
    LoginUser,
    PinTrack,
    RegisterUser,
    RemoveTrack,
    RemoveTrackFromPlaylist,
    RenamePlaylist,
    ReplaceRecording,
    UnassignTrackFromAlbum,
    UpdateAlbum,
    UploadAlbumCover,
    UploadTrack,
)
from groots.service_layer.handlers import (
    admin_handler,
    album_handler,
    library_handler,
    playlist_handler,
    user_handler,
)
from groots.service_layer.messagebus import MessageBus
from groots.service_layer.unit_of_work import MongoUnitOfWork


class Container(containers.DeclarativeContainer):
    config = providers.Configuration()

    ipfs_client = providers.Singleton(
        IPFSClient,
        api_url=config.IPFS_API_URL,
        gateway_url=config.IPFS_GATEWAY_URL,
        kubo_url=config.IPFS_KUBO_URL,
    )

    fingerprinter = providers.Singleton(AudioFingerprinter)
    extractor = providers.Singleton(MetadataExtractor)

    discogs_client = providers.Singleton(
        DiscogsClient,
        user_agent=config.DISCOGS_APP_NAME,
        user_token=config.DISCOGS_USER_TOKEN,
    )

    uow = providers.Factory(
        MongoUnitOfWork,
        db_uri=config.MONGO_DB_URI,
        db_name=config.MONGO_DB,
        ipfs_client=ipfs_client,
        fingerprinter=fingerprinter,
        extractor=extractor,
    )

    messagebus = providers.Factory(
        MessageBus,
        uow=uow,
        command_handlers=providers.Dict(
            {
                RegisterUser: user_handler.handle_register_user,
                LoginUser: user_handler.handle_login_user,
                AddTrack: library_handler.handle_add_track,
                RemoveTrack: library_handler.handle_remove_track,
                PinTrack: library_handler.handle_pin_track,
                UploadTrack: library_handler.handle_upload_track,
                ReplaceRecording: library_handler.handle_replace_recording,
                CreateAlbum: album_handler.handle_create_album,
                UpdateAlbum: album_handler.handle_update_album,
                DeleteAlbum: album_handler.handle_delete_album,
                UploadAlbumCover: album_handler.handle_upload_album_cover,
                AssignTrackToAlbum: album_handler.handle_assign_track_to_album,
                UnassignTrackFromAlbum: album_handler.handle_unassign_track_from_album,
                CreatePlaylist: playlist_handler.handle_create_playlist,
                RenamePlaylist: playlist_handler.handle_rename_playlist,
                DeletePlaylist: playlist_handler.handle_delete_playlist,
                AddTrackToPlaylist: playlist_handler.handle_add_track_to_playlist,
                RemoveTrackFromPlaylist: playlist_handler.handle_remove_track_from_playlist,
                IngestCentralTrack: admin_handler.handle_ingest_central_track,
            }
        ),
    )
