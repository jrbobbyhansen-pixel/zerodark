# ZeroDark App – Full Operational Reference

**Core functions:** Map – offline OSM (Documents/OfflineMaps/), TAK overlay, team, threats, rings, MGRS. LiDAR – 5 modes (tactical, structural, route, threat, scene), AR mesh, history. Coordination – incidents, LandSAR Bayesian, SOS. Comms – PTT voice, HAMMER acoustic, Meshtastic, TAK/CoT. Settings – device, TAK server, tiles, AI URLs. Knowledge – BM25 + BitNet-2B 115-file base. Vision – moondream2 (plant, wound, terrain, map).

**Offline:** All core offline. Maps cached tiles. GPS no cell/WiFi. Mesh requires other ZeroDark/Meshtastic nearby. Knowledge bundled.

**Server setup:** BitNet-2B – ~/Desktop/start-bitnet-server.sh (port 8080). moondream2 – ~/Desktop/moondream-server.py (port 8081). FreeTAK – TCP 8087, TLS 8089.

**Team:** Same Meshtastic PSK all. Same TAK IP:port. Same MGRS datum (WGS84).

**Dark phone:** No SIM. WiFi only. Airplane mode WiFi on. Maps pre-cached. Knowledge bundled. No cloud.