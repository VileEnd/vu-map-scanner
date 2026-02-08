-- MapScanner Server Initialization
-- Bootstraps the server-side scanning engine and RCON bridge
-- v2: S3 direct upload, auto-start, auto-rotate

require '__shared/ScanConfig'
require '__shared/ScanLogger'
require '__shared/MeshBuilder'
require '__shared/S3Signer'
require '__shared/DataExporter'

local MapScanEngine = require '__server/MapScanEngine'
local RCONBridge = require '__server/RCONBridge'

-- Create singletons
g_MapScanEngine = MapScanEngine()
g_RCONBridge = RCONBridge()

print('[MapScanner] Server initialized — S3 direct upload mode')
print('[MapScanner] RCON: mapscan.start/stop/pause/resume/status/preset')
print('[MapScanner] RCON: mapscan.config/s3/autostart/autorotate')
