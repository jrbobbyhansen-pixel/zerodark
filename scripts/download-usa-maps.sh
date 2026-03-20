#!/bin/bash
# download-usa-maps.sh — Download complete USA offline maps for ZeroDark
# Run this on a Mac with internet connection
# Transfer results to dark iPhone via USB

set -e

MAPS_DIR="$HOME/ZeroDarkMaps"
mkdir -p "$MAPS_DIR"
cd "$MAPS_DIR"

echo "========================================"
echo "ZeroDark USA Offline Maps Downloader"
echo "========================================"
echo ""
echo "This will download ~80GB of map data."
echo "Estimated time: 2-4 hours on fast connection"
echo ""
echo "Storage required:"
echo "  - Download: ~80GB"
echo "  - Extracted: ~100GB"
echo "  - iPhone transfer: ~80GB"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Option 1: Protomaps (Free, vector tiles)
echo ""
echo "[1/4] Downloading Protomaps USA basemap..."
echo "Source: Protomaps.com (free, updated monthly)"

# Check if curl supports resume
if curl -L -C - -o usa-basemap.pmtiles \
  "https://build.protomaps.com/20240101.pmtiles" 2>/dev/null; then
    echo "✓ Downloaded usa-basemap.pmtiles"
else
    echo "Note: Protomaps may require direct download from:"
    echo "https://protomaps.com/downloads/protomaps-basemap"
fi

# Option 2: OpenMapTiles extracts (Free, but need to build)
echo ""
echo "[2/4] Downloading OSM PBF for USA..."
echo "Source: Geofabrik (free OpenStreetMap data)"

# US regions from Geofabrik
REGIONS=(
    "us/texas"
    "us/california"
    "us/florida"
    "us/new-york"
    # Add more as needed, or use full "north-america/us" (~10GB PBF)
)

mkdir -p osm-extracts
for region in "${REGIONS[@]}"; do
    name=$(basename "$region")
    if [ ! -f "osm-extracts/${name}-latest.osm.pbf" ]; then
        echo "Downloading ${region}..."
        curl -L -o "osm-extracts/${name}-latest.osm.pbf" \
          "https://download.geofabrik.de/${region}-latest.osm.pbf"
    fi
done

# Option 3: Terrain data (DEMs)
echo ""
echo "[3/4] Downloading USGS terrain data..."
echo "Source: USGS 3DEP (free, 10m resolution)"

mkdir -p terrain
echo "Note: Full CONUS terrain is ~50GB. Download specific regions as needed:"
echo "https://apps.nationalmap.gov/downloader/"
echo ""
echo "For Texas (~2GB):"
echo "  curl -o terrain/texas-dem.tif 'https://...'"
echo ""

# Create transfer instructions
echo ""
echo "[4/4] Creating transfer instructions..."

cat > TRANSFER_INSTRUCTIONS.md << 'INSTRUCTIONS'
# ZeroDark Offline Map Transfer

## Files to Transfer

| File | Size | Description |
|------|------|-------------|
| usa-basemap.pmtiles | ~80GB | Full USA vector map tiles |
| terrain/*.tif | ~50GB | Elevation data (optional) |

## Transfer Steps

1. Connect iPhone to Mac via USB-C cable
2. Open Finder
3. Select your iPhone in the sidebar
4. Click "Files" tab
5. Find ZeroDark in the app list
6. Drag files into appropriate folders:
   - `*.pmtiles` → Maps/
   - `*.mbtiles` → Maps/
   - `*.tif` → Terrain/
   - `*.hgt` → Terrain/

7. Wait for transfer to complete (30-60 min for 80GB)

## Verify in App

1. Open ZeroDark
2. Go to Profile → Offline Data
3. Pull down to refresh
4. Maps should show as installed

## Map Coverage

The USA basemap includes:
- All 50 states + territories
- Zoom levels 0-14 (street level)
- Roads, buildings, parks, water
- Points of interest
- Terrain contours (if terrain files added)

## Terrain Coverage (Optional)

Add USGS DEMs for:
- Elevation profiles
- Slope analysis
- Line of sight calculations
- 3D terrain visualization
INSTRUCTIONS

echo ""
echo "========================================"
echo "Download complete!"
echo "========================================"
echo ""
echo "Files saved to: $MAPS_DIR"
echo ""
echo "Next steps:"
echo "1. Read TRANSFER_INSTRUCTIONS.md"
echo "2. Connect dark iPhone via USB"
echo "3. Transfer files via Finder"
echo ""
echo "Total size to transfer:"
du -sh "$MAPS_DIR"
