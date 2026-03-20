# Meshtastic Mesh Network Operations

Meshtastic uses LoRa radio to create multi-hop mesh networks. No internet. No cell service. Range: 3–10km per hop. Unlimited hops within range.

**ZeroDark integration:**
ZeroDark bridges Meshtastic BLE to the app. Meshtastic node appears in team overlay when GPS position packet received. Text messages routed through MeshService.

**Channel setup:**
All devices on same channel name AND same pre-shared key = same mesh.
Default channel "LongFast" is public. Create encrypted channel for operational use.
Channel PSK: 256-bit pre-shared key. Must be identical on all nodes.

**Frequency regions:**
US: 915MHz. EU: 868MHz. Do NOT operate wrong frequency for your region.
Long-range preset: low bandwidth, very long range (good for GPS position pings).
Fast preset: higher bandwidth, shorter range (good for text messaging).

**GPS tracking:**
Meshtastic nodes broadcast position every X minutes (configurable). All nodes in mesh see all positions. ZeroDark plots these as team positions on map.

**Battery management:**
GPS is largest power draw. Reduce GPS broadcast interval for battery conservation. 10-minute intervals vs 1-minute: 5× battery improvement with minimal tactical impact.

**Limitations:**
No voice. No images. Text and GPS position only. Packet size: 256 bytes max per message. Longer messages fragmented and may have higher loss rate.

**Security:**
Channel PSK encrypts content. Node IDs are visible to any Meshtastic device. Do not use default channel for operational traffic.
