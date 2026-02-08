-- MapScanner Server Initialization
-- Bootstraps the server-side scanning engine and RCON bridge

require '__shared/ScanConfig'
require '__shared/ScanLogger'
require '__shared/MeshBuilder'
require '__shared/DataExporter'

local MapScanEngine = require '__server/MapScanEngine'
local RCONBridge = require '__server/RCONBridge'

-- Create singletons
g_MapScanEngine = MapScanEngine()
g_RCONBridge = RCONBridge()

print('[MapScanner] Server initialized — use RCON "mapscan.start" to begin')
print('[MapScanner] RCON commands: mapscan.start/stop/pause/resume/status/preset/export/list/retrieve')
print('[MapScanner] RCON data:     mapscan.fetch.heightmap/chunk/meta | mapscan.push | mapscan.config')
