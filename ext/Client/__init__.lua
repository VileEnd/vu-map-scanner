-- MapScanner Client Initialization

require '__shared/ScanConfig'
require '__shared/ScanLogger'

local MapScanClient = require 'MapScanClient'

-- Create the singleton client
g_MapScanClient = MapScanClient()

print('[MapScanner] Client initialized — F9: debug vis | F10: test ray | F11: local scan | F12: progress HUD')

return g_MapScanClient
