# Changelog

## 2.0.0 — S3 Direct Upload, Auto-Start & Auto-Rotate

### Added
- **S3 direct upload** — scan data uploaded directly to Hetzner/AWS/MinIO via AWS Signature V4 signed PUT requests
- `S3Signer.lua` — pure Lua SHA-256 + HMAC implementation for AWS Signature V4 (adapted from positionTracking mod)
- **Auto-start** — scanning begins automatically on map load after configurable delay (default 10s)
- **Auto-rotate** — after scan + upload completes, server switches to the next map via RCON (`mapList.clear` → `mapList.add` → `mapList.runNextRound`)
- Full 29-map rotation table in `ScanConfig.lua` with game modes
- Upload completion tracking with 120s timeout before map rotation
- Scanned-maps tracking to skip already-scanned maps within a session
- Manifest file uploaded per scan with full metadata (scan time, hit count, chunk count, grid spacing, bounds)
- S3 key pattern: `mapscans/<mapId>/<preset>/heightmap.json`, `chunk_NNN.json`, `manifest.json`
- RCON commands: `mapscan.s3`, `mapscan.autostart`, `mapscan.autorotate`
- Node.js ESM processing script (`UI_project/scripts/process-map-scans.mjs`) — downloads from S3, merges chunks, generates GLB files for Three.js

### Changed
- `DataExporter.lua` — completely rewritten for S3 (removed all SQL and HTTP POST code)
- `MapScanEngine.lua` — completely rewritten with auto-start countdown, auto-rotate logic, and S3 upload tracking
- `RCONBridge.lua` — completely rewritten with S3 config and toggle commands (removed all SQL retrieval commands)
- `ScanConfig.lua` — added S3 config, rotation table, auto-start/rotate settings; removed HTTP/SQL settings
- Map count expanded from 24 to 29 (all BF3 DLC maps)

### Removed
- SQLite storage (`SQL:Open`, `SQL:Query`, etc.) — too slow for large scan datasets
- HTTP POST export to collector endpoint
- RCON commands: `mapscan.export`, `mapscan.list`, `mapscan.retrieve`, `mapscan.fetch.*`, `mapscan.push`
- Configuration keys: `exportUrl`, `useHttpExport`, `httpTimeout`, `tlsVerify`, `ingestToken`, `exportBatchSize`

## 1.0.0 — Initial Release

### Added
- Server-side `MapScanEngine` with three-phase scanning (top-down, interior, export)
- Client-side `MapScanClient` with debug visualization and local area scanning
- `MeshBuilder` for converting raw ray hits into triangle meshes with chunks
- `DataExporter` with dual SQLite + HTTP POST export
- `RCONBridge` for remote control and data retrieval
- Four resolution presets: ultra, high, medium, low
- All 24 BF3 maps pre-configured with bounds and Y ranges
- Node.js converter tool for GLB / JSON / PGM output
- Full RCON command set for scan management
- Client hotkeys: F9 (debug vis), F10 (test ray), F11 (local scan), F12 (progress)
