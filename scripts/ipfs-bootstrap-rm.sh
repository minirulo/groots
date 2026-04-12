#!/bin/sh
# Runs inside the Kubo container via /container-init.d/ — executed after
# `ipfs init` but before the daemon starts.
set -ex

# Kubo ≥0.40 introduced AutoConf, which tries to reach the public mainnet
# config service and refuses to start when a swarm.key is detected.
# Disable it explicitly for private-network nodes.
ipfs config --json AutoConf.Enabled false

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
