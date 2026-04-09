<p align="center">
  <img src="assets/logo-banner.svg" alt="Groots" width="480" />
</p>

<p align="center">
  <strong>Decentralized personal music streaming — own your library, stream anywhere.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/FastAPI-0.100+-009688?logo=fastapi&logoColor=white" alt="FastAPI" />
  <img src="https://img.shields.io/badge/MongoDB-7.0-47A248?logo=mongodb&logoColor=white" alt="MongoDB" />
  <img src="https://img.shields.io/badge/IPFS-Kubo-65C2CB?logo=ipfs&logoColor=white" alt="IPFS" />
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20iOS-lightgrey?logo=apple" alt="Platform" />
</p>

---

## What is Groots?

Groots is a **self-hosted, decentralized music platform**. You sync your local music library to an IPFS-backed backend, and stream it from a native macOS/iOS app. Your files live on IPFS — content-addressed, portable, and under your control.

```
Local files  →  IPFS (Kubo)  →  FastAPI backend  →  Flutter app
                   ↑                   ↑
              Content IDs (CIDs)    MongoDB (metadata)
```

**Key ideas:**
- Files are stored by their IPFS content identifier (CID) — not by path or server location
- Metadata (tracks, albums, playlists) lives in MongoDB and is served through a REST API
- Acoustic fingerprinting detects duplicates across uploads
- The Flutter app handles playback, library browsing, and syncing via the macOS/iOS native stack

---

## Architecture

```
groots/
├── backend/                  # Python / FastAPI service
│   └── src/groots/
│       ├── domain/           # Core models: Track, Album, Playlist, User
│       ├── service_layer/    # Application logic & message bus
│       ├── adapters/         # MongoDB & IPFS adapters
│       └── entrypoints/api/  # REST routes (auth, library, albums, playlists…)
│
├── groots_app/               # Flutter app (macOS + iOS)
│   └── lib/src/
│       ├── domain/           # Client-side models
│       ├── service_layer/    # BLoC state management
│       ├── adapters/         # API client
│       └── ui/               # Screens and widgets
│
├── docker-compose.dev.yml    # api + MongoDB + IPFS (dev)
├── docker-compose.yml        # Production compose
└── Makefile                  # Developer shortcuts
```

### Stack

| Layer | Technology |
|---|---|
| Mobile / Desktop app | Flutter (Dart) |
| State management | flutter_bloc |
| Audio playback | just_audio + audio_service |
| API | FastAPI (Python) |
| Database | MongoDB 7 |
| File storage | IPFS / Kubo |
| Fingerprinting | Acoustic fingerprint matching |

---

## Getting Started

### Prerequisites

- [Docker](https://www.docker.com/) & Docker Compose
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (≥ 3.x)
- macOS (for the native app target)

### 1 — Start the backend

```bash
# First run: copies .env.example and builds images
make start-dev

# Subsequent runs (no rebuild)
make dev
```

Services started:

| Service | Port | Description |
|---|---|---|
| FastAPI API | `8001` | REST backend |
| MongoDB | `27017` | Metadata store |
| IPFS gateway | `8080` | File retrieval |
| IPFS API | `5001` | Kubo RPC |
| IPFS swarm | `4001` | P2P traffic |

### 2 — Configure environment

```bash
cp .config/.env.example .config/.env.dev
# Edit .config/.env.dev with your settings
```

### 3 — Run the Flutter app

```bash
# Install dependencies
make app-get

# Run on macOS (dev)
make app-dev

# Run on a connected iOS device (dev)
make ios-dev
```

---

## Development Commands

```bash
make help          # Show all available commands

# Backend
make logs          # Tail all service logs
make shell-api     # Shell into the API container
make shell-db      # Open mongosh
make unit-tests    # Run pytest with coverage
make lint          # ruff check
make fmt           # black formatter

# Flutter
make app-dev       # Run macOS app (dev target)
make app-prod      # Run macOS app (release)
make ios-sim       # Run on iOS Simulator
make ios-prod      # Run on iOS device (release)
```

---

## API Overview

The REST API is served at `http://localhost:8001`. Core route groups:

| Route | Description |
|---|---|
| `POST /auth/...` | Register, login, token refresh |
| `GET/POST /library/...` | Upload tracks, browse your library |
| `GET/POST /albums/...` | Album management |
| `GET/POST /playlists/...` | Playlist management |
| `GET /genres/` | Browse by genre |
| `GET /users/me` | Current user profile |
| `GET /health` | Health check |

Interactive docs: `http://localhost:8001/docs`

---

## How it works

1. **Upload** — you pick a local audio file; the backend pins it to IPFS and stores its CID + metadata in MongoDB.
2. **Fingerprint** — on upload, an acoustic fingerprint is generated and checked against existing tracks to detect duplicates.
3. **Stream** — the Flutter app fetches track metadata from the API and streams audio directly from the IPFS gateway using the CID.
4. **Sync** — the directory picker lets you bulk-sync a local folder; new files are uploaded automatically.

---

## Running Tests

```bash
# Unit tests (inside Docker)
make unit-tests

# Flutter tests
cd groots_app && flutter test
```

---

## License

Private — all rights reserved.
