-- MapScanner Shared Configuration
-- All scanning parameters, map definitions, S3 upload, and auto-rotation

local ScanConfig = {}

-- ============================================================================
-- Map Definitions
-- Each map has: center (X,Z), width, and Y scan range
-- Derived from RealityMod minimap data and UI mapConfig
-- ============================================================================
ScanConfig.Maps = {
    ['MP_001']      = { name = 'Grand Bazaar',      center = {-133.80, -18.21},   width = 950,  yMin = 120,  yMax = 220 },
    ['MP_003']      = { name = 'Teheran Highway',    center = {-133.80, -18.21},   width = 950,  yMin = 120,  yMax = 220 },
    ['MP_007']      = { name = 'Caspian Border',     center = {-281.99, 59.13},    width = 850,  yMin = 50,   yMax = 150 },
    ['MP_011']      = { name = 'Seine Crossing',     center = {-133.80, -18.21},   width = 950,  yMin = 120,  yMax = 220 },
    ['MP_012']      = { name = 'Firestorm',          center = {-24.51, -6.66},     width = 1450, yMin = 80,   yMax = 200 },
    ['MP_013']      = { name = 'Damavand Peak',      center = {-133.80, -18.21},   width = 950,  yMin = -50,  yMax = 300 },
    ['MP_017']      = { name = 'Noshahr Canals',     center = {-133.80, -18.21},   width = 950,  yMin = -10,  yMax = 150 },
    ['MP_018']      = { name = 'Kharg Island',       center = {-133.80, -18.21},   width = 950,  yMin = -10,  yMax = 200 },
    ['MP_Subway']   = { name = 'Operation Metro',    center = {-133.80, -18.21},   width = 950,  yMin = -20,  yMax = 200 },
    ['XP1_001']     = { name = 'Strike At Karkand',  center = {-48.69, -8.07},     width = 1000, yMin = 120,  yMax = 220 },
    ['XP1_002']     = { name = 'Gulf of Oman',       center = {-58.55, -139.08},   width = 2100, yMin = -10,  yMax = 150 },
    ['XP1_003']     = { name = 'Sharqi Peninsula',   center = {240.12, -168.37},   width = 2000, yMin = -10,  yMax = 150 },
    ['XP1_004']     = { name = 'Wake Island',        center = {-5.07, -71.82},     width = 1800, yMin = -10,  yMax = 100 },
    ['XP2_Factory'] = { name = 'Scrapmetal',         center = {0, 1},              width = 125,  yMin = -20,  yMax = 80 },
    ['XP2_Office']  = { name = 'Operation 925',      center = {-133.80, -18.21},   width = 950,  yMin = -20,  yMax = 100 },
    ['XP2_Palace']  = { name = 'Donya Fortress',     center = {10, 13},            width = 150,  yMin = -10,  yMax = 80 },
    ['XP2_Skybar']  = { name = 'Ziba Tower',         center = {-3.10, 1.77},       width = 125,  yMin = -10,  yMax = 100 },
    ['XP3_Alborz']  = { name = 'Alborz Mountains',   center = {1597.83, 759.77},   width = 2500, yMin = 250,  yMax = 550 },
    ['XP3_Desert']  = { name = 'Bandar Desert',      center = {-508, 0},           width = 5000, yMin = -10,  yMax = 200 },
    ['XP3_Shield']  = { name = 'Armored Shield',     center = {-51.71, -71.82},    width = 2200, yMin = -10,  yMax = 200 },
    ['XP3_Valley']  = { name = 'Death Valley',       center = {-137.22, 3.43},     width = 2560, yMin = -10,  yMax = 200 },
    ['XP4_FD']      = { name = 'Markaz Monolith',    center = {-281.99, 59.13},    width = 850,  yMin = 40,   yMax = 150 },
    ['XP4_Parl']    = { name = 'Azadi Palace',       center = {-281.99, 59.13},    width = 850,  yMin = 40,   yMax = 150 },
    ['XP4_Quake']   = { name = 'Epicenter',          center = {-281.99, 59.13},    width = 850,  yMin = 40,   yMax = 150 },
    ['XP4_Rubble']  = { name = 'Talah Market',       center = {-281.99, 59.13},    width = 850,  yMin = 40,   yMax = 150 },
    ['XP5_001']     = { name = 'Op. Riverside',      center = {96.42, -34.81},     width = 2560, yMin = -10,  yMax = 200 },
    ['XP5_002']     = { name = 'Kandahar',           center = {-1928.38, 283.85},  width = 3800, yMin = -10,  yMax = 250 },
    ['XP5_003']     = { name = 'Gdansk Bay',         center = {-21.92, -192.23},   width = 3000, yMin = -10,  yMax = 200 },
    ['XP5_004']     = { name = 'Sabalan Pipeline',   center = {-904.49, -911.13},  width = 2560, yMin = -10,  yMax = 200 },
}

-- ============================================================================
-- Map Rotation for Auto-Scan
-- Order of maps to scan through automatically. ConquestLarge0 for max area,
-- Domination0 for CQ maps that don't have ConquestLarge.
-- ============================================================================
ScanConfig.MapRotation = {
    { mapId = 'MP_001',      gameMode = 'ConquestLarge0' },
    { mapId = 'MP_003',      gameMode = 'ConquestLarge0' },
    { mapId = 'MP_007',      gameMode = 'ConquestLarge0' },
    { mapId = 'MP_011',      gameMode = 'ConquestLarge0' },
    { mapId = 'MP_012',      gameMode = 'ConquestLarge0' },
    { mapId = 'MP_013',      gameMode = 'ConquestLarge0' },
    { mapId = 'MP_017',      gameMode = 'ConquestLarge0' },
    { mapId = 'MP_018',      gameMode = 'ConquestLarge0' },
    { mapId = 'MP_Subway',   gameMode = 'ConquestLarge0' },
    { mapId = 'XP1_001',     gameMode = 'ConquestLarge0' },
    { mapId = 'XP1_002',     gameMode = 'ConquestLarge0' },
    { mapId = 'XP1_003',     gameMode = 'ConquestLarge0' },
    { mapId = 'XP1_004',     gameMode = 'ConquestLarge0' },
    { mapId = 'XP2_Factory', gameMode = 'Domination0' },
    { mapId = 'XP2_Office',  gameMode = 'Domination0' },
    { mapId = 'XP2_Palace',  gameMode = 'Domination0' },
    { mapId = 'XP2_Skybar',  gameMode = 'Domination0' },
    { mapId = 'XP3_Alborz',  gameMode = 'ConquestLarge0' },
    { mapId = 'XP3_Desert',  gameMode = 'ConquestLarge0' },
    { mapId = 'XP3_Shield',  gameMode = 'ConquestLarge0' },
    { mapId = 'XP3_Valley',  gameMode = 'ConquestLarge0' },
    { mapId = 'XP4_FD',      gameMode = 'ConquestLarge0' },
    { mapId = 'XP4_Parl',    gameMode = 'ConquestLarge0' },
    { mapId = 'XP4_Quake',   gameMode = 'ConquestLarge0' },
    { mapId = 'XP4_Rubble',  gameMode = 'ConquestLarge0' },
    { mapId = 'XP5_001',     gameMode = 'ConquestLarge0' },
    { mapId = 'XP5_002',     gameMode = 'ConquestLarge0' },
    { mapId = 'XP5_003',     gameMode = 'ConquestLarge0' },
    { mapId = 'XP5_004',     gameMode = 'ConquestLarge0' },
}

-- ============================================================================
-- Scan Resolution Presets
-- ============================================================================
ScanConfig.Presets = {
    -- Turbo: fastest possible for headless servers with no players
    -- Coarser grid but maxed-out rays per tick
    turbo = {
        maxGridSpacing = 4.0,
        verticalStep = 5.0,
        maxRaysPerTick = 2000,
        interiorPasses = true,
        interiorStepY = 5.0,
    },
    ultra = {
        maxGridSpacing = 1.0,
        verticalStep = 2.0,
        maxRaysPerTick = 500,
        interiorPasses = true,
        interiorStepY = 3.0,
    },
    high = {
        maxGridSpacing = 2.0,
        verticalStep = 3.0,
        maxRaysPerTick = 500,
        interiorPasses = true,
        interiorStepY = 4.0,
    },
    medium = {
        maxGridSpacing = 5.0,
        verticalStep = 5.0,
        maxRaysPerTick = 1000,
        interiorPasses = true,
        interiorStepY = 5.0,
    },
    low = {
        maxGridSpacing = 10.0,
        verticalStep = 10.0,
        maxRaysPerTick = 2000,
        interiorPasses = false,
        interiorStepY = 0,
    },
}

-- ============================================================================
-- Active Configuration
-- ============================================================================

ScanConfig.activePreset = 'high'

-- Auto-start scanning when map loads (no RCON trigger needed)
ScanConfig.autoStart = true

-- Auto-rotate to next map after scan + export completes
ScanConfig.autoRotate = true

-- Delay in seconds after level load before starting scan
-- (gives the engine time to fully stream in geometry)
ScanConfig.autoStartDelay = 10.0

-- ============================================================================
-- S3 Direct Upload Configuration
-- Same pattern as positionTracking mod (TelemetryS3Uploader)
-- ============================================================================
ScanConfig.s3Endpoint = 'nbg1.your-objectstorage.com'   -- Hetzner, AWS, MinIO
ScanConfig.s3Region = 'nbg1'                             -- Must match endpoint
ScanConfig.s3Bucket = 'vu-mapscanner'                    -- S3 bucket name
ScanConfig.s3AccessKey = ''                              -- Set in Startup.txt or here
ScanConfig.s3SecretKey = ''                              -- Set in Startup.txt or here
ScanConfig.s3PathStyle = true                            -- Required for Hetzner
ScanConfig.s3Timeout = 60                                -- Seconds per upload

-- S3 object path: <prefix>/<mapId>/<preset>/heightmap.json, chunk_001.json, ...
ScanConfig.s3Prefix = 'mapscans'

-- Enable debug logging
ScanConfig.debugLogging = true

-- ============================================================================
-- Helper Functions
-- ============================================================================

function ScanConfig.GetPreset()
    return ScanConfig.Presets[ScanConfig.activePreset] or ScanConfig.Presets['high']
end

function ScanConfig.GetMapConfig(levelName)
    if levelName == nil then return nil end
    for mapId, config in pairs(ScanConfig.Maps) do
        if string.find(levelName, mapId) then
            config.id = mapId
            return config
        end
    end
    return nil
end

function ScanConfig.CalculateGridSpacing(mapWidth)
    local preset = ScanConfig.GetPreset()
    local baseSpacing = preset.maxGridSpacing
    if mapWidth <= 200 then
        return baseSpacing
    elseif mapWidth <= 1200 then
        return baseSpacing * 2
    elseif mapWidth <= 3000 then
        return baseSpacing * 4
    else
        return baseSpacing * 6
    end
end

function ScanConfig.EstimateRayCount(mapConfig)
    local spacing = ScanConfig.CalculateGridSpacing(mapConfig.width)
    local gridSize = math.ceil(mapConfig.width / spacing)
    local totalRays = gridSize * gridSize
    if ScanConfig.GetPreset().interiorPasses then
        local yRange = mapConfig.yMax - mapConfig.yMin
        local interiorLayers = math.ceil(yRange / ScanConfig.GetPreset().interiorStepY)
        totalRays = totalRays + math.floor(gridSize * gridSize * interiorLayers * 0.3)
    end
    return totalRays
end

function ScanConfig.EstimateScanTime(mapConfig)
    local totalRays = ScanConfig.EstimateRayCount(mapConfig)
    local preset = ScanConfig.GetPreset()
    local ticksNeeded = math.ceil(totalRays / preset.maxRaysPerTick)
    return ticksNeeded / 30.0
end

--- Get the map rotation entry index for a given map ID
function ScanConfig.GetRotationIndex(mapId)
    for i, entry in ipairs(ScanConfig.MapRotation) do
        if entry.mapId == mapId then
            return i
        end
    end
    return nil
end

--- Get the next map in rotation after a given map ID (nil = rotation complete)
function ScanConfig.GetNextMap(currentMapId)
    local idx = ScanConfig.GetRotationIndex(currentMapId)
    if idx == nil then
        return ScanConfig.MapRotation[1]
    end
    local nextIdx = idx + 1
    if nextIdx > #ScanConfig.MapRotation then
        return nil  -- all maps scanned
    end
    return ScanConfig.MapRotation[nextIdx]
end

--- Sanitize string for S3 object keys
function ScanConfig.SanitizeKey(str)
    if str == nil then return 'unknown' end
    return str:gsub('[^A-Za-z0-9%-_/.]', '_')
end

return ScanConfig
