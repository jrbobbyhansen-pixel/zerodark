# TAK and Cursor-on-Target (CoT)

TAK (Team Awareness Kit) is the US military's situational awareness platform, now open-sourced.

**CoT message structure:**
XML-based. Required fields: UID (unique ID), type (what it is), time (timestamp), stale (when to remove), how (source), point (lat/lon/elevation).

**Type codes (most common):**
a-f-G-U-C: Friendly ground unit
a-h-G: Hostile ground unit
a-n-G: Neutral/unknown ground
b-m-p: Position report
b-t-f: Friendly track
a-f-A: Friendly air

**ZeroDark integration:**
ZeroDark sends CoT position packets to FreeTAK Server (TCP 8087 or TLS 8089). Friendly positions appear on all connected TAK devices. Incidents and intel broadcast as CoT events.

**MGRS in TAK:**
CoT internally uses WGS84 lat/lon. ZeroDark converts to/from MGRS for display. When sharing grids verbally, use MGRS. When app is sharing to TAK, conversion is automatic.

**FreeTAK setup:**
Server runs on any networked machine. All clients connect to server IP:port. Dark phone scenario: all devices on same WiFi or hotspot, connect to Mac running FreeTAK.

**ATAK (Android TAK) compatibility:**
ZeroDark CoT messages compatible with ATAK and WinTAK. Can share map with Android/Windows TAK users on same server.
