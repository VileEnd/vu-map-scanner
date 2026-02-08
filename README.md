# MapScanner — Venice Unleashed 3D Map Geometry Exporter

A Venice Unleashed mod that systematically raycasts every map surface to generate high-resolution 3D terrain and building geometry data. Scans automatically on map load, uploads to S3, and rotates through all maps unattended. A processing script converts the data into GLB files for the WebUI heatmap overlay.

## Features

- **Full map coverage** — systematic grid-based raycasting covers every square meter
- **Multi-layer interior scanning** — horizontal rays at multiple heights capture building interiors, walls, floors, and ceilings
- **Configurable resolution** — four presets (ultra/high/medium/low) with automatic scaling based on map size
- **Non-blocking scanning** — spreads ray processing across engine ticks to maintain server performance
- **S3 direct upload** — signed PUT requests (AWS Signature V4) to Hetzner/AWS/MinIO
- **Auto-start** — scanning begins automatically when a map loads (configurable delay)
- **Auto-rotate** — advances to the next map via RCON after scan + upload completes
- **RCON control** — start/stop/pause/configure scans and S3 settings remotely
- **Client-side debug visualization** — see scan results rendered in real-time during gameplay
- **GLB processing pipeline** — Node.js script downloads from S3 and produces Three.js-ready GLB files

## Architecture

```
MapScanner/
├── mod.json                        # VU mod manifest
├── ext/
│   ├── Shared/
│   │   ├── __init__.lua            # Shared module loader
│   │   ├── ScanConfig.lua          # Map definitions, presets, S3 config, rotation
│   │   ├── ScanLogger.lua          # Logging utility
│   │   ├── MeshBuilder.lua         # Converts raw hits → triangle mesh
│   │   ├── S3Signer.lua            # AWS Signature V4 (pure Lua SHA-256)
│   │   └── DataExporter.lua        # S3 upload logic
│   ├── Server/
│   │   ├── __init__.lua            # Server bootstrap
│   │   ├── StartupOverrides.lua    # Registers MapScanner.<key> commands for Startup.txt
│   │   ├── MapScanEngine.lua       # Core scanner: topdown → interior → S3 export → rotate
│   │   └── RCONBridge.lua          # RCON config commands
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

### 2. Configure S3

The recommended way is via `Admin/Startup.txt` (keeps secrets out of mod files):

```
MapScanner.s3Endpoint nbg1.your-objectstorage.com
MapScanner.s3Region nbg1
MapScanner.s3Bucket vu-mapscanner
MapScanner.s3AccessKey YOUR_ACCESS_KEY
MapScanner.s3SecretKey YOUR_SECRET_KEY
MapScanner.s3PathStyle true
MapScanner.activePreset turbo
```

> **Important:** `Startup.txt` runs RCON commands, not Lua.
> - No equals signs: `MapScanner.s3Bucket vu-mapscanner` (not `= 'vu-mapscanner'`)
> - No quotes: `MapScanner.s3Endpoint nbg1.your-objectstorage.com` (not `'nbg1...'`)
> - No Lua comments: `MapScanner.s3PathStyle true` (not `true  -- comment`)
> - Use `MapScanner.activePreset turbo` to set the preset (not `MapScanner.start turbo`)

Alternatively, edit `ext/Shared/ScanConfig.lua` directly:

```lua
ScanConfig.s3Endpoint = 'nbg1.your-objectstorage.com'
ScanConfig.s3Region = 'nbg1'
ScanConfig.s3Bucket = 'vu-mapscanner'
ScanConfig.s3AccessKey = 'YOUR_ACCESS_KEY'
ScanConfig.s3SecretKey = 'YOUR_SECRET_KEY'
ScanConfig.s3PathStyle = true
```

Or set at runtime via RCON:
```
mapscan.s3 accessKey YOUR_KEY
mapscan.s3 secretKey YOUR_SECRET
mapscan.s3 bucket vu-mapscanner
```

### 3. Start the server

With `autoStart = true` (default), scanning begins automatically 10 seconds after the map loads:

```
[MapScanner] Server initialized — S3 direct upload mode
[MapScanner:INFO] Map recognized: Strike At Karkand (XP1_001)
[MapScanner:INFO]   Grid spacing: 4.0m | Est. rays: 62500 | Est. time: 125s (2.1 min)
[MapScanner:INFO]   Auto-start in 10 seconds...
```

With `autoRotate = true` (default), after scan + S3 upload completes, the server automatically advances to the next map in the rotation list.

### 4. Process scan data for WebUI

```bash
cd UI_project
S3_ACCESS_KEY=xxx S3_SECRET_KEY=yyy node scripts/process-map-scans.mjs
```

This downloads all scan data from S3 and produces GLB files in `public/assets/maps/`.

## Scanning Process

### Phase 1: Top-Down Scan
Casts rays straight down from above the map (`yMax + 100`) to below (`yMin - 50`). Each ray uses `DetailedRaycast` with up to 10 hits.

### Phase 2: Interior Scan
For cells that had hits, casts horizontal rays in 8 directions at multiple vertical layers to capture walls, doorways, and multi-story interiors.

### Phase 3: S3 Export
Uploads heightmap JSON, mesh chunks, and a manifest to S3:
```
mapscans/<mapId>/<preset>/
  ├── manifest.json     # scan metadata
  ├── heightmap.json    # 2D height grid
  ├── chunk_001.json    # triangulated mesh data
  ├── chunk_002.json
  └── ...
```

### Phase 4: Auto-Rotate
Uses RCON commands to switch to the next map in the rotation list.

## Resolution Presets

| Preset | Grid Spacing (small/med/large) | Interior Scan | Rays/Tick | Use Case |
|--------|-------------------------------|---------------|-----------|----------|
| `turbo`  | 4m / 8m / 16m | Yes (5m layers) | 2000 | Headless, no players |
| `ultra`  | 1m / 2m / 4m | Yes (3m layers) | 500 | Highest detail |
| `high`   | 2m / 4m / 8m | Yes (4m layers) | 500 | Good detail |
| `medium` | 5m / 10m / 20m | Yes (5m layers) | 1000 | Balanced |
| `low`    | 10m / 20m / 40m | No | 2000 | Quick overview |

## RCON Commands

| Command | Description |
|---------|-------------|
| `mapscan.start [preset]` | Start scanning (with optional preset override) |
| `mapscan.stop` | Stop current scan |
| `mapscan.pause` / `mapscan.resume` | Pause/resume scan |
| `mapscan.status` | Show progress, S3 upload stats |
| `mapscan.preset [name]` | Get/set active preset |
| `mapscan.config [key] [value]` | View/set general config (preset, debug, delay) |
| `mapscan.s3 [key] [value]` | View/set S3 config (endpoint, region, bucket, keys) |
| `mapscan.autostart [on\|off]` | Toggle auto-start on map load |
| `mapscan.autorotate [on\|off]` | Toggle auto-rotate after scan |

## Client Controls

| Key | Action |
|-----|--------|
| `F9` | Toggle debug visualization |
| `F10` | Single test raycast from camera |
| `F11` | High-detail local area scan (50m radius) |
| `F12` | Toggle progress HUD |

## WebUI Integration

### Processing Pipeline

```bash
# Process all maps from S3
node scripts/process-map-scans.mjs

# Process a single map
node scripts/process-map-scans.mjs --map XP1_004

# Use local files instead of S3
node scripts/process-map-scans.mjs --local ./scan-data
```

### Loading in Three.js

```typescript
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader';

const loader = new GLTFLoader();
loader.load(`/assets/maps/${mapId}_terrain.glb`, (gltf) => {
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

### Via Startup.txt (recommended for secrets)

Add to `Admin/Startup.txt` — these are RCON commands, not Lua:

```
MapScanner.s3AccessKey YOUR_KEY
MapScanner.s3SecretKey YOUR_SECRET
MapScanner.s3Endpoint nbg1.your-objectstorage.com
MapScanner.s3Region nbg1
MapScanner.s3Bucket vu-mapscanner
MapScanner.s3PathStyle true
MapScanner.activePreset turbo
MapScanner.autoStart true
MapScanner.autoRotate true
MapScanner.autoStartDelay 10
MapScanner.debugLogging false
```

Any `ScanConfig` key can be set this way: `MapScanner.<key> <value>`

> **Do not** use Lua syntax (`= 'value'`), quotes, or inline comments (`-- comment`) in Startup.txt — these are RCON commands, not Lua.

### Via ScanConfig.lua

Alternatively, edit `ext/Shared/ScanConfig.lua` directly:

```lua
-- Scanning
ScanConfig.activePreset = 'high'
ScanConfig.autoStart = true
ScanConfig.autoRotate = true
ScanConfig.autoStartDelay = 10.0

-- S3
ScanConfig.s3Endpoint = 'nbg1.your-objectstorage.com'
ScanConfig.s3Region = 'nbg1'
ScanConfig.s3Bucket = 'vu-mapscanner'
ScanConfig.s3AccessKey = ''
ScanConfig.s3SecretKey = ''
ScanConfig.s3PathStyle = true

-- Debug
ScanConfig.debugLogging = true
```

## Development

```cmd
cd /d %LOCALAPPDATA%\VeniceUnleashed\client
vu.exe -server -headless -dedicated -high60 -skipChecksum
```

Watch for `[MapScanner]` log lines. The mod will auto-scan and rotate through all 29 maps.

## License

MIT
