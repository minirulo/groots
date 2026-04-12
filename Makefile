# Device IDs — update if simulators are recreated
IOS_SIM     = 353D2240-AB0E-4675-AA44-B9B07C93A35D
IOS_DEVICE  = 00008110-0010299801E3801E

.PHONY: help start-dev dev stop logs shell-api shell-db unit-tests lint fmt \
        ipfs-peer-id cluster-peer-id \
        app-get app-dev app-prod app-build-dev app-build-prod \
        ios-sim ios-dev ios-prod

COMPOSE = docker compose -f docker-compose.dev.yml --env-file .config/.env.dev
FLUTTER = $(HOME)/Applications/flutter/bin/flutter
APP_DIR = groots_app

help:
	@echo "Groots dev commands"
	@echo "  make start-dev   — build images and start all services"
	@echo "  make dev         — start services (no rebuild)"
	@echo "  make down        — stop all services"
	@echo "  make logs        — tail logs for all services"
	@echo "  make shell-api   — open a shell inside the api container"
	@echo "  make shell-db    — open mongosh inside the db container"
	@echo "  make unit-tests  — run unit tests"
	@echo "  make lint        — run ruff linter"
	@echo "  make fmt         — run black formatter"

start-dev:
	cp -n .config/.env.example .config/.env.dev || true
	$(COMPOSE) up --build

dev:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down --remove-orphans

logs:
	$(COMPOSE) logs -f

shell-api:
	$(COMPOSE) exec api bash

shell-db:
	$(COMPOSE) exec db mongosh \
		-u "$$(grep MONGO_INITDB_ROOT_USERNAME .config/.env.dev | cut -d= -f2)" \
		-p "$$(grep MONGO_INITDB_ROOT_PASSWORD .config/.env.dev | cut -d= -f2)" \
		--authenticationDatabase admin groots

unit-tests:
	$(COMPOSE) exec api pytest tests/unit -v --cov=groots --cov-report=term-missing

lint:
	$(COMPOSE) exec api ruff check groots

fmt:
	$(COMPOSE) exec api black groots

# Print the Kubo peer multiaddr — use this to manually connect the Mac node:
#   Get.find<IpfsLocalNode>().connectToPeer('<output>')
ipfs-peer-id:
	$(COMPOSE) exec ipfs ipfs id --format='<addrs>' | tr ',' '\n' | grep tcp/4001

# Print the cluster peer ID for debugging
cluster-peer-id:
	$(COMPOSE) exec ipfs-cluster ipfs-cluster-ctl id

# Start the ipfs-webui dev server (http://localhost:3000)
# CORS is pre-configured via scripts/ipfs-bootstrap-rm.sh for this origin.
webui:
	cd ipfs-webui && npm start

# ── Flutter macOS app ─────────────────────────────────────────────────────────
app-get:
	cd $(APP_DIR) && $(FLUTTER) pub get

app-dev:
	cd $(APP_DIR) && $(FLUTTER) run \
		--target lib/development.dart \
		-d macos

app-prod:
	cd $(APP_DIR) && $(FLUTTER) run \
		--target lib/production.dart \
		-d macos --release

app-build-dev:
	cd $(APP_DIR) && $(FLUTTER) build macos \
		--target lib/development.dart \
		--debug

app-build-prod:
	cd $(APP_DIR) && $(FLUTTER) build macos \
		--target lib/production.dart \
		--release

# ── Flutter iOS ───────────────────────────────────────────────────────────────
ios-sim:
	cd $(APP_DIR) && $(FLUTTER) run \
		--target lib/development.dart \
		-d $(IOS_SIM)

ios-dev:
	cd $(APP_DIR) && $(FLUTTER) run \
		--target lib/development.dart \
		-d $(IOS_DEVICE)

ios-prod:
	cd $(APP_DIR) && $(FLUTTER) run \
		--target lib/production.dart \
		-d $(IOS_DEVICE) --release
