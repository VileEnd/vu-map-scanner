# MapScanner — Venice Unleashed 3D Map Geometry Exporter

A Venice Unleashed mod that systematically raycasts every map surface to generate high-resolution 3D terrain and building geometry data. The output can be used as map underlays in WebUI heatmap visualizations.

## Features

- **Full map coverage** — systematic grid-based raycasting covers every square meter of the map
- **Multi-layer interior scanning** — horizontal rays at multiple heights capture building interiors, floors, ceilings, and walls
- **Configurable resolution** — four presets (ultra/high/medium/low) with automatic scaling based on map size
- **Non-blocking scanning** — spreads ray processing across engine ticks to maintain server performance
- **Dual export** — data stored locally via SQLite and optionally pushed via HTTP
- **RCON control** — start/stop/pause/configure scans remotely
- **Client-side debug visualization** — see scan results rendered in real-time during gameplay
- **WebUI integration** — converter tool generates GLB (glTF binary) or optimized JSON for Three.js

## Architecture

```
MapScanner/
├── mod.json                        # VU mod manifest
├── ext/
│   ├── Shared/
│   │   ├── __init__.lua            # Shared module loader
│   │   ├── ScanConfig.lua          # Map definitions, presets, configuration
│   │   ├── ScanLogger.lua          # Logging utility
│   │   ├── MeshBuilder.lua         # Converts raw hits → triangle mesh
│   │   └── DataExporter.lua        # SQL + HTTP export logic
│   ├── Server/
│   │   ├── __init__.lua            # Server bootstrap
│   │   ├── MapScanEngine.lua       # Core raycast scanner (phases: topdown → interior → export)
│   │   └── RCONBridge.lua          # RCON commands for data retrieval
│   └── Client/
│       ├── __init__.lua            # Client bootstrap
│       └── MapScanClient.lua       # Debug visualization + local area scanning
└── tools/
    └── convert-scan.js             # Node.js converter: JSON → GLB / PNG / optimized JSON
```

## Quick Start

### 1. Install the mod

Copy or symlink the `MapScanner` folder into your VU server's `Admin/Mods/` directory.

Add to `Admin/ModList.txt`:
```
MapScanner
```

### 2. Start the server and load a map

The mod auto-detects which map is loaded. Check the console for:
```
[MapScanner] Server initialized — use RCON "mapscan.start" to begin
[MapScanner:INFO] Map recognized: Strike At Karkand (XP1_001)
[MapScanner:INFO]   Grid spacing: 4.0m | Est. rays: 62500 | Est. time: 125s (2.1 min)
```

### 3. Start scanning via RCON

```
mapscan.start                    # Start with default preset (high)
mapscan.start ultra              # Start with ultra preset
mapscan.status                   # Check progress
mapscan.pause / mapscan.resume   # Pause/resume
mapscan.stop                     # Abort scan
```

### 4. Export and convert

After scanning completes, data is auto-saved to the mod's SQLite database. To convert:

```bash
# List completed scans
mapscan.list

# Push to HTTP endpoint
mapscan.push 1 https://your-server/api/v1/mapdata

# Or retrieve via RCON for external processing
mapscan.fetch.heightmap 1
```

Convert to WebUI format:
```bash
cd MapScanner/tools
node convert-scan.js ../output/ --format all --output ./converted/
```

## Scanning Process

### Phase 1: Top-Down Scan
Casts rays straight down from above the map (`yMax + 100`) to below (`yMin - 50`) on a regular grid. Each ray uses `DetailedRaycast` with up to 10 hits to capture rooftops, ground, and any layered geometry.

```
         ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓    (rays from above)
    ═══════════════════════════    (roof)
    ║     building interior   ║
    ═══════════════════════════    (floor / ground)
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~    (terrain)
```

### Phase 2: Interior Scan
For every grid cell that had a hit in Phase 1, casts horizontal rays in 8 directions (N/S/E/W + diagonals) at multiple vertical layers. This captures walls, doorways, corridors, and multi-story building interiors.

```
    ←──→  ←──→  ←──→              (horizontal rays at each layer)
    ║  ║  ║  ║  ║  ║
    ║  ║  ║  ║  ║  ║   Layer 3
    ════════════════
    ║  ║  ║  ║  ║  ║
    ║  ║  ║  ║  ║  ║   Layer 2
    ════════════════
    ║  ║  ║  ║  ║  ║
    ║  ║  ║  ║  ║  ║   Layer 1
    ════════════════
```

### Phase 3: Export
Collected hit points are triangulated into chunks, then exported as JSON (heightmap + mesh chunks) via HTTP and/or stored in SQLite.

## Resolution Presets

| Preset | Grid Spacing (small/med/large maps) | Interior Scan | Rays/Tick |
|--------|--------------------------------------|---------------|-----------|
| `ultra`  | 1m / 2m / 4m | Yes (3m layers) | 50 |
| `high`   | 2m / 4m / 8m | Yes (4m layers) | 100 |
| `medium` | 5m / 10m / 20m | Yes (5m layers) | 200 |
| `low`    | 10m / 20m / 40m | No | 500 |

Estimated scan times (high preset) for representative maps:

| Map | Size | Est. Time |
|-----|------|-----------|
| Donya Fortress (XP2) | 150m | ~5 sec |
| Grand Bazaar (MP_001) | 950m | ~3 min |
| Strike At Karkand (XP1_001) | 1000m | ~4 min |
| Wake Island (XP1_004) | 1800m | ~8 min |
| Bandar Desert (XP3_Desert) | 5000m | ~30 min |

## RCON Commands

| Command | Description |
|---------|-------------|
| `mapscan.start [preset]` | Start scanning with optional preset override |
| `mapscan.stop` | Stop current scan |
| `mapscan.pause` | Pause current scan |
| `mapscan.resume` | Resume paused scan |
| `mapscan.status` | Show current scan progress |
| `mapscan.preset [name]` | Get/set active preset |
| `mapscan.export` | Manually trigger data export |
| `mapscan.list` | List stored scan records |
| `mapscan.retrieve <id> [heightmap\|chunks]` | Send stored data to clients |
| `mapscan.fetch.heightmap <id>` | Retrieve heightmap JSON via RCON |
| `mapscan.fetch.chunk <id> <idx>` | Retrieve mesh chunk via RCON |
| `mapscan.fetch.meta` | List all scan metadata |
| `mapscan.push <id> <url>` | Push scan data to HTTP endpoint |
| `mapscan.config [key] [value]` | View/set configuration |

## Client Controls

| Key | Action |
|-----|--------|
| `F9` | Toggle debug visualization (colored hit points) |
| `F10` | Single test raycast from camera |
| `F11` | Start high-detail local area scan (50m radius) |
| `F12` | Toggle progress HUD |

## Output Format

### Heightmap JSON
```json
{
  "type": "heightmap",
  "mapId": "XP1_001",
  "mapName": "Strike At Karkand",
  "gridSpacing": 4.0,
  "originX": -548.69,
  "originZ": -508.07,
  "gridW": 250,
  "gridH": 250,
  "heights": [[150.2, 150.5, ...], ...]
}
```

### Mesh Chunk JSON
```json
{
  "mapId": "XP1_001",
  "chunkIndex": 1,
  "gridSpacing": 4.0,
  "vertexCount": 4096,
  "indexCount": 12288,
  "vertices": [x,y,z, nx,ny,nz, ...],
  "indices": [0, 1, 2, ...]
}
```

### WebUI Integration

The converter tool (`tools/convert-scan.js`) produces:

1. **GLB file** — drop into `public/maps/` for Three.js `GLTFLoader`
2. **Optimized JSON** — base64-encoded vertex buffers for `THREE.BufferGeometry`
3. **Heightmap PGM** — 16-bit grayscale for `THREE.PlaneGeometry` displacement

Example Three.js loading:
```javascript
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader';

const loader = new GLTFLoader();
loader.load(`/maps/${mapId}.glb`, (gltf) => {
    const terrain = gltf.scene;
    terrain.traverse((child) => {
        if (child.isMesh) {
            child.material = new THREE.MeshStandardMaterial({
                color: 0x444444,
                wireframe: false,
                transparent: true,
                opacity: 0.6,
            });
        }
    });
    scene.add(terrain);
});
```

## Configuration

Edit `ext/Shared/ScanConfig.lua` to change defaults:

```lua
ScanConfig.activePreset = 'high'           -- ultra, high, medium, low
ScanConfig.exportUrl = 'https://...'       -- HTTP endpoint
ScanConfig.useHttpExport = true            -- true=HTTP, false=SQL only
ScanConfig.debugLogging = true             -- verbose console output
ScanConfig.exportBatchSize = 5000          -- vertices per export batch
ScanConfig.tlsVerify = false               -- TLS cert verification
ScanConfig.ingestToken = ''                -- Bearer token for HTTP
```

Or change at runtime via RCON:
```
mapscan.config preset ultra
mapscan.config exportUrl https://my-server/api
mapscan.config debug false
```

## Development

### Testing locally
```cmd
cd /d %LOCALAPPDATA%\VeniceUnleashed\client
vu.exe -server -headless -dedicated -high60 -skipChecksum
```

Watch for `[MapScanner]` log lines. Use RCON to control scanning.

### Client-side testing
Join the server, press F10 to test a single raycast, F11 to scan 50m around you with debug visualization.

## License

MIT
