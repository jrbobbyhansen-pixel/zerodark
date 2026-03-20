# EMCON – Emissions Control

**Definition:** Selective and controlled use of electromagnetic, acoustic, or other emitters to prevent adversary detection, exploitation, or attack.

**EMCON levels:**
EMCON 1 (full): No emissions of any kind. Complete electronic silence. Full blackout.
EMCON 2: Essential emissions only. Receive only on most systems. Transmit only with specific authorization.
EMCON 3: Normal restricted emissions. Follow standard COMSEC, minimize non-essential transmissions.
EMCON 4: Normal operations. No restrictions beyond standard security.

**Electronic devices that emit passively:**
Cell phone: broadcasts every 0.3–10 seconds to cell towers, BT scanning, WiFi scanning
Laptop: WiFi and BT scanning even in airplane mode (OS-dependent)
GPS: Receive only, does NOT emit – no EMCON concern
Fitness trackers: Bluetooth broadcast every 2–5 seconds
Smart watches: BT, WiFi, cellular

**EMCON implementation:**
Physical removal of batteries where possible. Faraday bags: block all wireless emissions. Airplane mode + WiFi off + BT off: reduces but does not eliminate all emissions (varies by device).
Test: Faraday bag effectiveness can be tested by attempting to call or track device.

**During sensitive movement:**
All non-essential devices in Faraday bags or off. No cell phones on person (in bag 100m away minimum). GPS tracking acceptable (receive only). HAMMER and Meshtastic acceptable when necessary.
