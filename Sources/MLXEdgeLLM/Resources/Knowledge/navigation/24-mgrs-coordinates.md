# MGRS Grid Coordinates

Military Grid Reference System – standard coordinate format for US military maps and TAK.

**Structure:** Grid Zone Designator (2 digits + letter) + 100km Square ID (2 letters) + Grid (4, 6, 8, or 10 digits)

**Example:** 14SNA0645028563
- 14S = Grid zone (zone 14, row S)
- NA = 100km square
- 06450 28563 = 10-digit grid (1-meter accuracy)

**Grid precision:**
- 4-digit (1000m square): "grid square" – MGRS 1450
- 6-digit (100m accuracy): standard military – 064285
- 8-digit (10m accuracy): most practical tactical use
- 10-digit (1m accuracy): precise targeting

**Reading a grid:**
Read RIGHT then UP. (Easting then Northing – "Right and Up" or "Reads Right, Up Right")
Grid 064285: go to easting 064, northing 285 on map.

**TAK and ZeroDark MGRS:**
ZeroDark app converts GPS coordinates to MGRS automatically. When sharing positions over TAK/CoT, MGRS 10-digit is standard for tactical accuracy.

**Practical application:**
6-digit MGRS sufficient for most coordination (100m accuracy). 10-digit for precise rendezvous or targeting. Always state grid zone when operating near zone boundaries.
