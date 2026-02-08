# Changelog

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
