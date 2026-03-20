# PACE Planning – Communications Architecture

PACE = Primary, Alternate, Contingency, Emergency.

Every communication requirement should have all four methods established BEFORE the operation begins. Single point of failure = silence when you need it most.

**Example PACE for a two-person team:**
Primary: Meshtastic BLE mesh on Channel A, frequency 915MHz
Alternate: TAK/CoT over WiFi to Mac server
Contingency: Visual signals – pre-agreed hand signals at rendezvous
Emergency: Whistle – 3 blasts = distress, 1 = I see you, 2 = move now

**Building a PACE plan:**
1. Identify all communication requirements (reporting, coordination, emergency)
2. For each, identify 4 methods in order of preference
3. Assign triggers for switching (Primary fails after X attempts – switch to Alternate)
4. Brief all parties on complete PACE before departure
5. Test all methods before departure

**Failure modes to plan for:**
Battery death. Jamming/electronic interference. Physical device loss. Team separation beyond range. Network congestion or server failure.

**TAK PACE:**
P: TAK server CoT via WiFi
A: Direct TAK mesh (no server, ad-hoc)
C: Meshtastic LoRa mesh
E: HAMMER acoustic or visual signals
