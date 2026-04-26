#!/bin/sh
# Runs inside the Kubo container via /container-init.d/ — executed after
# `ipfs init` but before the daemon starts.
set -ex

# ── Private-network compatibility (Kubo ≥0.34) ───────────────────────────────
# AutoConf: reaches public mainnet config service, incompatible with swarm.key.
ipfs config --json AutoConf.Enabled false
# Migration to repo v18 writes 'auto' placeholders that require AutoConf.
ipfs config --json Bootstrap '[]'
ipfs config --json Routing.DelegatedRouters '[]'
ipfs config --json Ipns.DelegatedPublishers '[]'
ipfs config --json DNS.Resolvers '{}'
# AutoTLS: connection-gates peers without ACME certs, blocks private peers.
ipfs config --json AutoTLS.Enabled false
# Websocket transport incompatible with PNET (swarm.key).
ipfs config --json Swarm.Transports.Network.Websocket false
# Routing.Type=auto conflicts with private networks; use dht explicitly.
ipfs config Routing.Type dht
# server profile blocks all RFC-1918 ranges — our peers are on 10.x / 172.x.
ipfs config --json Swarm.AddrFilters '[]'

# Remove all public bootstrap peers so this node stays on the private swarm only.
ipfs bootstrap rm --all

# The server profile disables mDNS. Re-enable it so cluster peers and the
# Mac client node can discover this node on the local network.
ipfs config --json Discovery.MDNS.Enabled true

# The `server` profile sets Gateway.NoFetch=true (blocks fetching from the network).
# Re-enable it so the Web UI and gateway work — the swarm key already restricts
# which peers can connect, so this is safe on a private node.
ipfs config --json Gateway.NoFetch false

# CORS for the ipfs-webui dev server (localhost:3000) — mirrors the origins
# from ipfs-webui/cors-config.sh, plus streaming response headers that the
# browser must see exposed for list/status API calls to work correctly.
ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin \
  '["http://localhost:3000","http://127.0.0.1:3000","https://webui.ipfs.io","https://dev.webui.ipfs.io"]'
ipfs config --json API.HTTPHeaders.Access-Control-Allow-Methods \
  '["PUT","POST","GET","DELETE","OPTIONS"]'
# X-Stream-Output / X-Chunked-Output / X-Content-Length are set by Kubo on
# streaming responses; without them exposed, the browser drops the body and
# the Web UI shows empty peers / files panels.
ipfs config --json API.HTTPHeaders.Access-Control-Expose-Headers \
  '["X-Stream-Output","X-Chunked-Output","X-Content-Length","Location","Trailer","Transfer-Encoding"]'
