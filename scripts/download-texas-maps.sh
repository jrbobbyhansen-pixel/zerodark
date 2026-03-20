#!/bin/bash
# download-texas-maps.sh — Download Texas offline maps for ZeroDark
# Run on Mac with internet, transfer to dark iPhone via USB

set -e

MAPS_DIR="$HOME/ZeroDarkMaps"
mkdir -p "$MAPS_DIR"
cd "$MAPS_DIR"

echo "========================================"
echo "ZeroDark Texas Offline Maps"
echo "========================================"
echo ""
echo "Downloading:"
echo "  - Texas vector tiles: ~8GB"
echo "  - Texas terrain DEMs: ~2GB (optional)"
echo ""
echo "Estimated time: 30-60 min"
echo ""

# Texas OSM PBF from Geofabrik
echo "[1/3] Downloading Texas OpenStreetMap data..."
if [ ! -f "texas-latest.osm.pbf" ]; then
    curl -L -C - -o texas-latest.osm.pbf \
      "https://download.geofabrik.de/north-america/us/texas-latest.osm.pbf"
    echo "✓ Downloaded texas-latest.osm.pbf"
else
    echo "✓ texas-latest.osm.pbf already exists"
fi

# Convert to MBTiles using tilemaker (if installed)
echo ""
echo "[2/3] Converting to MBTiles..."
if command -v tilemaker &> /dev/null; then
    if [ ! -f "texas.mbtiles" ]; then
        echo "Running tilemaker (this takes 20-30 min)..."
        tilemaker --input texas-latest.osm.pbf --output texas.mbtiles
        echo "✓ Created texas.mbtiles"
    else
        echo "✓ texas.mbtiles already exists"
    fi
else
    echo ""
    echo "⚠️  tilemaker not installed. Install with:"
    echo "    brew install tilemaker"
    echo ""
    echo "Or download pre-built Texas tiles from:"
    echo "    https://protomaps.com/downloads"
    echo "    https://openmaptiles.org/downloads/"
    echo ""
fi

# Texas terrain from USGS
echo ""
echo "[3/3] Texas terrain data..."
mkdir -p terrain
echo "Download Texas DEMs from USGS National Map:"
echo "https://apps.nationalmap.gov/downloader/"
echo ""
echo "Select:"
echo "  - Area: Draw box around Texas"
echo "  - Data: Elevation Products (3DEP)"
echo "  - Format: GeoTIFF"
echo ""
echo "Save .tif files to: $MAPS_DIR/terrain/"

# Create transfer guide
cat > TEXAS_TRANSFER.md << 'EOF'
# Transfer Texas Maps to Dark iPhone

## Files to Transfer

| File | Size | Destination |
|------|------|-------------|
| texas.mbtiles | ~8GB | ZeroDark/Maps/ |
| terrain/*.tif | ~2GB | ZeroDark/Terrain/ |

## Steps

1. Connect iPhone via USB-C
2. Open Finder → iPhone → Files tab
3. Expand "ZeroDark"
4. Drag `texas.mbtiles` into `Maps/` folder
5. Drag `terrain/*.tif` into `Terrain/` folder
6. Wait for transfer (~10-15 min)

## Verify

1. Open ZeroDark on iPhone
2. Profile → Offline Data
3. Pull to refresh
4. Should show "texas" under Maps

## Coverage

Texas MBTiles includes:
- All 254 counties
- Major cities (Houston, Dallas, SA, Austin)
- Rural roads and highways
- State/national parks
- Water features
- Building footprints (urban areas)
- Zoom levels 0-14
EOF

echo ""
echo "========================================"
echo "Texas download ready!"
echo "========================================"
echo ""
ls -lh "$MAPS_DIR"/*.mbtiles 2>/dev/null || echo "(MBTiles will be created after tilemaker runs)"
echo ""
echo "Read TEXAS_TRANSFER.md for USB transfer steps"
