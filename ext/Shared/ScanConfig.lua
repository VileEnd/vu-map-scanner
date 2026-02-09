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
    ['MP_007']      = { name = 'Caspian Border',     center = {-362.50, 65.50},    width = 950,  yMin = 50,   yMax = 150 },
    ['MP_011']      = { name = 'Seine Crossing',     center = {-133.80, -18.21},   width = 950,  yMin = 120,  yMax = 220 },
    ['MP_012']      = { name = 'Firestorm',          center = {-24.50, -6.70},     width = 1650, yMin = 80,   yMax = 200 },
    ['MP_013']      = { name = 'Damavand Peak',      center = {-133.80, -18.21},   width = 950,  yMin = -50,  yMax = 300 },
    ['MP_017']      = { name = 'Noshahr Canals',     center = {-133.80, -18.21},   width = 950,  yMin = -10,  yMax = 150 },
    ['MP_018']      = { name = 'Kharg Island',       center = {-133.80, -18.21},   width = 950,  yMin = -10,  yMax = 200 },
    ['MP_Subway']   = { name = 'Operation Metro',    center = {-133.80, -18.21},   width = 950,  yMin = -20,  yMax = 200 },
    ['XP1_001']     = { name = 'Strike At Karkand',  center = {13.35, -40.30},     width = 1150, yMin = 120,  yMax = 220 },
    ['XP1_002']     = { name = 'Gulf of Oman',       center = {24.55, -244.85},    width = 2150, yMin = -10,  yMax = 150 },
    ['XP1_003']     = { name = 'Sharqi Peninsula',   center = {292.85, -155.00},   width = 2000, yMin = -10,  yMax = 150 },
    ['XP1_004']     = { name = 'Wake Island',        center = {215.79, 167.27},    width = 2500, yMin = -10,  yMax = 130 },
    ['XP2_Factory'] = { name = 'Scrapmetal',         center = {0, 1},              width = 125,  yMin = -20,  yMax = 80 },
    ['XP2_Office']  = { name = 'Operation 925',      center = {-133.80, -18.21},   width = 950,  yMin = -20,  yMax = 100 },
    ['XP2_Palace']  = { name = 'Donya Fortress',     center = {10, 13},            width = 150,  yMin = -10,  yMax = 80 },
    ['XP2_Skybar']  = { name = 'Ziba Tower',         center = {-3.10, 1.77},       width = 125,  yMin = -10,  yMax = 100 },
    ['XP3_Alborz']  = { name = 'Alborz Mountains',   center = {1598.40, 758.25},   width = 2700, yMin = 250,  yMax = 550 },
    ['XP3_Desert']  = { name = 'Bandar Desert',      center = {-507.70, 0.45},     width = 5200, yMin = -10,  yMax = 200 },
    ['XP3_Shield']  = { name = 'Armored Shield',     center = {3.20, -168.90},     width = 2200, yMin = -10,  yMax = 200 },
    ['XP3_Valley']  = { name = 'Death Valley',       center = {-136.75, 3.60},     width = 2760, yMin = -10,  yMax = 200 },
    ['XP4_FD']      = { name = 'Markaz Monolith',    center = {-281.99, 59.13},    width = 850,  yMin = 40,   yMax = 150 },
    ['XP4_Parl']    = { name = 'Azadi Palace',       center = {-354.20, 27.70},    width = 900,  yMin = 40,   yMax = 150 },
    ['XP4_Quake']   = { name = 'Epicenter',          center = {-281.99, 59.13},    width = 850,  yMin = 40,   yMax = 150 },
    ['XP4_Rubble']  = { name = 'Talah Market',       center = {-281.99, 59.13},    width = 850,  yMin = 40,   yMax = 150 },
    ['XP5_001']     = { name = 'Op. Riverside',      center = {96.40, -34.80},     width = 2760, yMin = -10,  yMax = 200 },
    ['XP5_002']     = { name = 'Kandahar',           center = {-1928.45, 283.85},  width = 4000, yMin = -10,  yMax = 250 },
    ['XP5_003']     = { name = 'Gdansk Bay',         center = {-21.90, -192.20},   width = 3200, yMin = -10,  yMax = 200 },
    ['XP5_004']     = { name = 'Sabalan Pipeline',   center = {-904.45, -911.10},  width = 2760, yMin = -10,  yMax = 200 },
}

-- ============================================================================
-- Map Rotation for Auto-Scan
-- Order of maps to scan through automatically.
-- Uses RealityMod AdvanceAndSecureStd mode. Layer = rounds param in mapList.add.
-- At runtime, the actual game mode is detected from Level:Loaded and reused.
-- ============================================================================
ScanConfig.MapRotation = {
    { mapId = 'XP1_001',     gameMode = 'AdvanceAndSecureStd', layer = 1 },  -- Strike at Karkand
    { mapId = 'XP1_002',     gameMode = 'AdvanceAndSecureStd', layer = 1 },  -- Gulf of Oman
    { mapId = 'XP1_003',     gameMode = 'AdvanceAndSecureStd', layer = 1 },  -- Sharqi Peninsula
    { mapId = 'XP1_004',     gameMode = 'AdvanceAndSecureStd', layer = 1 },  -- Wake Island
    { mapId = 'XP3_Desert',  gameMode = 'AdvanceAndSecureStd', layer = 1 },  -- Bandar Desert
    { mapId = 'XP3_Shield',  gameMode = 'AdvanceAndSecureStd', layer = 6 },  -- Armored Shield (Issue 226)
    { mapId = 'XP4_Parl',    gameMode = 'AdvanceAndSecureStd', layer = 1 },  -- Azadi Palace
    { mapId = 'XP5_001',     gameMode = 'AdvanceAndSecureStd', layer = 1 },  -- Operation Riverside
    { mapId = 'XP5_002',     gameMode = 'AdvanceAndSecureStd', layer = 1 },  -- Kandahar
    { mapId = 'XP5_003',     gameMode = 'AdvanceAndSecureStd', layer = 1 },  -- Bay of Gdansk
    { mapId = 'XP5_004',     gameMode = 'AdvanceAndSecureStd', layer = 1 },  -- Sabalan Pipeline
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
        maxRaysPerTick = 5000,
        interiorPasses = true,
        interiorStepY = 5.0,
        topdownMaxHits = 5,
    },
    -- Insane: 30cm resolution everywhere (base + interior)
    -- WARNING: extremely slow on large maps (many hours). Best for small/medium maps.
    -- Grid scaling is disabled for this preset — always uses 0.3m regardless of map size.
    insane = {
        maxGridSpacing = 0.3,
        verticalStep = 0.3,
        maxRaysPerTick = 50000,
        interiorPasses = true,
        interiorStepY = 0.3,
        noScaling = true,  -- bypass CalculateGridSpacing map-size multiplier
        topdownMaxHits = 15,  -- fewer hits in top-down pass (faster); interior uses 5
        streamingExport = true,  -- scan+upload one chunk at a time to bound memory
    },
    -- Ultra: 2x better resolution per axis vs high, scales with map size
    -- ~6 hours total for full 11-map rotation. Browser-friendly vertex counts.
    ultra = {
        maxGridSpacing = 0.7,       -- base 1.0m → 2.0m on 1000m maps, 4.0m on 2000m, 6.0m on 5000m
        verticalStep = 0.7,
        maxRaysPerTick = 42000,
        interiorPasses = true,
        interiorStepY = 0.7,
        topdownMaxHits = 15,
        streamingExport = true,     -- keeps memory safe on all map sizes
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

ScanConfig.activePreset = 'insane'

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
    -- Insane preset: fixed spacing, no map-size scaling
    if preset.noScaling then
        return baseSpacing
    end
    -- Smooth continuous scaling: avoids cliff-edges at threshold boundaries.
    -- Maps <=200m use base spacing, then spacing scales smoothly with map width.
    -- Reference points (ultra base=0.7m):
    --   950m  → 1.4m   (was 1.4m with old 2x tier)
    --   1200m → 1.7m   (was 1.4m, then jumped to 2.8m at 1201m)
    --   2000m → 2.7m   (was 2.8m with old 4x tier)
    --   5000m → 6.3m   (was 4.2m — slightly coarser but still fine for huge maps)
    if mapWidth <= 200 then
        return baseSpacing
    end
    local scale = 1 + (mapWidth - 200) / 600
    return baseSpacing * math.min(scale, 10)
end

function ScanConfig.EstimateRayCount(mapConfig)
    local spacing = ScanConfig.CalculateGridSpacing(mapConfig.width)
    local gridSize = math.ceil(mapConfig.width / spacing)
    local totalRays = gridSize * gridSize
    if ScanConfig.GetPreset().interiorPasses then
        local yRange = mapConfig.yMax - mapConfig.yMin
        local interiorLayers = math.ceil(yRange / ScanConfig.GetPreset().interiorStepY)
        -- Only multi-layer cells get interior scanned (~5-15% of cells on most maps).
        -- 8 horizontal rays per cell per layer within the cell's Y bounds.
        -- Estimate: ~10% of cells are multi-layer, average 30% of layers relevant.
        totalRays = totalRays + math.floor(gridSize * gridSize * interiorLayers * 0.03 * 8)
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
