-- MapScanner Shared Configuration
-- All scanning parameters and map definitions

local ScanConfig = {}

-- ============================================================================
-- Map Definitions
-- Each map has: center (X,Z), width, and Y scan range
-- Derived from RealityMod minimap data
-- ============================================================================
ScanConfig.Maps = {
    ['MP_001']      = { name = 'Grand Bazaar',      center = {-133.80, -18.21},   width = 950,  yMin = 120,  yMax = 220 },
    ['MP_003']      = { name = 'Teheran Highway',    center = {-133.80, -18.21},   width = 950,  yMin = 120,  yMax = 220 },
    ['MP_007']      = { name = 'Caspian Border',     center = {-281.99, 59.13},    width = 850,  yMin = 50,   yMax = 150 },
    ['MP_012']      = { name = 'Firestorm',          center = {-24.51, -6.66},     width = 1450, yMin = 80,   yMax = 200 },
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
-- Scan Resolution Presets
-- ============================================================================
ScanConfig.Presets = {
    -- Ultra-high: ~1m grid for small maps, ~2m for medium
    ultra = {
        maxGridSpacing = 1.0,
        verticalStep = 2.0,       -- Y step for multi-layer interior scanning
        maxRaysPerTick = 50,      -- rays per engine update tick
        interiorPasses = true,    -- scan at multiple Y heights for buildings
        interiorStepY = 3.0,      -- vertical step between interior scan layers
    },
    -- High: ~2m for small, ~5m for medium, ~10m for large
    high = {
        maxGridSpacing = 2.0,
        verticalStep = 3.0,
        maxRaysPerTick = 100,
        interiorPasses = true,
        interiorStepY = 4.0,
    },
    -- Medium: ~5m for all maps (faster scanning)
    medium = {
        maxGridSpacing = 5.0,
        verticalStep = 5.0,
        maxRaysPerTick = 200,
        interiorPasses = true,
        interiorStepY = 5.0,
    },
    -- Low: quick preview scan
    low = {
        maxGridSpacing = 10.0,
        verticalStep = 10.0,
        maxRaysPerTick = 500,
        interiorPasses = false,
        interiorStepY = 0,
    },
}

-- ============================================================================
-- Active Configuration
-- ============================================================================

-- Which preset to use (can be overridden via RCON)
ScanConfig.activePreset = 'high'

-- Export endpoint (the collector or any HTTP endpoint)
ScanConfig.exportUrl = 'https://localhost:8443/api/v1/mapdata'

-- Export via HTTP POST? If false, uses SQL local storage
ScanConfig.useHttpExport = true

-- HTTP options
ScanConfig.httpTimeout = 60

-- TLS verification (disable for dev self-signed certs)
ScanConfig.tlsVerify = false

-- Auth token for export endpoint
ScanConfig.ingestToken = ''

-- Maximum number of vertices to batch before flushing
ScanConfig.exportBatchSize = 5000

-- Enable debug logging
ScanConfig.debugLogging = true

-- ============================================================================
-- Helper Functions
-- ============================================================================

--- Get the active preset configuration
function ScanConfig.GetPreset()
    return ScanConfig.Presets[ScanConfig.activePreset] or ScanConfig.Presets['high']
end

--- Get the map config for the current level
--- @param levelName string - e.g. "Levels/XP1_001/XP1_001"
--- @return table|nil - map config or nil
function ScanConfig.GetMapConfig(levelName)
    if levelName == nil then
        return nil
    end

    -- Extract map ID from level path (e.g. "Levels/XP1_001/XP1_001" -> "XP1_001")
    for mapId, config in pairs(ScanConfig.Maps) do
        if string.find(levelName, mapId) then
            config.id = mapId
            return config
        end
    end

    return nil
end

--- Calculate grid spacing for a given map width
--- Adjusts resolution based on map size to keep scan time reasonable
--- @param mapWidth number - map width in meters
--- @return number - grid spacing in meters
function ScanConfig.CalculateGridSpacing(mapWidth)
    local preset = ScanConfig.GetPreset()
    local baseSpacing = preset.maxGridSpacing

    -- Scale spacing by map size:
    -- Small maps (< 200m): use base spacing directly
    -- Medium maps (200-1200m): use base * 2
    -- Large maps (1200-3000m): use base * 4
    -- Huge maps (> 3000m): use base * 6
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

--- Calculate total estimated ray count for a map
--- @param mapConfig table
--- @return number
function ScanConfig.EstimateRayCount(mapConfig)
    local spacing = ScanConfig.CalculateGridSpacing(mapConfig.width)
    local gridSize = math.ceil(mapConfig.width / spacing)
    local totalRays = gridSize * gridSize -- top-down pass

    if ScanConfig.GetPreset().interiorPasses then
        local yRange = mapConfig.yMax - mapConfig.yMin
        local interiorLayers = math.ceil(yRange / ScanConfig.GetPreset().interiorStepY)
        -- Interior scan: for each layer, only rescan where previous pass hit something
        -- Estimate ~30% of grid points have structures above ground
        totalRays = totalRays + math.floor(gridSize * gridSize * interiorLayers * 0.3)
    end

    return totalRays
end

--- Estimate scan time in seconds
--- @param mapConfig table
--- @return number
function ScanConfig.EstimateScanTime(mapConfig)
    local totalRays = ScanConfig.EstimateRayCount(mapConfig)
    local preset = ScanConfig.GetPreset()
    -- Server runs at ~30Hz, each tick does maxRaysPerTick rays
    local ticksNeeded = math.ceil(totalRays / preset.maxRaysPerTick)
    return ticksNeeded / 30.0
end

return ScanConfig
