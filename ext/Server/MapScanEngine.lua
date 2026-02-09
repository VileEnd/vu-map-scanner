-- MapScanner Server-Side Raycast Engine
-- Performs systematic grid-based raycasting to scan entire map geometry
-- Supports multi-layer scanning for building interiors
-- v2: S3 direct upload, auto-start on map load, auto-rotate maps

local ScanConfig = require '__shared/ScanConfig'
local Logger = require '__shared/ScanLogger'
local MeshBuilder = require '__shared/MeshBuilder'
local DataExporter = require '__shared/DataExporter'

local log = Logger:New('MapScanEngine')

class 'MapScanEngine'

function MapScanEngine:__init()
    log:Info('MapScanEngine initializing...')

    -- State
    self.m_IsScanning = false
    self.m_IsPaused = false
    self.m_ScanPhase = 'idle'        -- 'idle', 'topdown', 'interior', 'exporting', 'complete'
    self.m_CurrentMapConfig = nil
    self.m_GridSpacing = 1.0

    -- Scan grid state
    self.m_ScanMinX = 0
    self.m_ScanMaxX = 0
    self.m_ScanMinZ = 0
    self.m_ScanMaxZ = 0
    self.m_CurrentX = 0
    self.m_CurrentZ = 0
    self.m_ScanHeight = 500
    self.m_ScanDepth = -50

    -- Interior scan state
    self.m_InteriorLayers = {}
    self.m_CurrentInteriorLayer = 0
    self.m_InteriorCells = {}
    self.m_CurrentInteriorIdx = 0

    -- Progress tracking
    self.m_TotalGridCells = 0
    self.m_CompletedCells = 0
    self.m_TotalRaysCast = 0
    self.m_StartTime = 0
    self.m_LastProgressReport = 0

    -- Data storage
    self.m_MeshBuilder = MeshBuilder:New()
    self.m_DataExporter = nil  -- created in StartScan() after Startup.txt overrides have applied

    -- Export state
    self.m_ExportChunks = {}
    self.m_CurrentExportChunk = 0

    -- Auto-start timer
    self.m_AutoStartTimer = 0
    self.m_AutoStartPending = false

    -- Auto-rotate: track scanned maps this session
    self.m_ScannedMaps = {}
    self.m_CurrentGameMode = 'ConquestLarge0'  -- updated in OnLevelLoaded

    -- Upload completion check
    self.m_WaitingForUploads = false
    self.m_UploadWaitStart = 0

    -- Material name lookup table: materialIndex → name
    self.m_MaterialNames = {}   -- populated at level load from MaterialContainerAsset
    self.m_MaterialIndexSet = {} -- track unique indices seen during scan

    -- Streaming export: scan and upload one chunk at a time to bound memory
    -- Enabled via preset.streamingExport (e.g. insane preset)
    self.m_StreamingEnabled = false
    self.m_StreamChunks = {}         -- precomputed chunk grid regions
    self.m_CurrentStreamChunk = 0    -- 1-based index into m_StreamChunks
    self.m_ChunkPhase = 'idle'       -- 'topdown' or 'interior' within current chunk
    self.m_ChunkGX = 0               -- current grid X within chunk scan
    self.m_ChunkGZ = 0               -- current grid Z within chunk scan
    self.m_ChunkInteriorCells = {}   -- cells with hits in current chunk (for interior scan)
    self.m_ChunkInteriorIdx = 0
    self.m_ChunkInteriorLayer = 0
    self.m_StreamedChunkCount = 0    -- chunks successfully uploaded so far

    -- Event subscriptions
    Events:Subscribe('Level:Loaded', self, self.OnLevelLoaded)
    Events:Subscribe('Level:Destroy', self, self.OnLevelDestroy)
    Events:Subscribe('Engine:Update', self, self.OnEngineUpdate)
    Events:Subscribe('Partition:Loaded', self, self.OnPartitionLoaded)

    -- RCON commands
    self.m_RconScan = RCON:RegisterCommand('mapscan.start', RemoteCommandFlag.RequiresLogin, self, self.OnRconStart)
    self.m_RconStop = RCON:RegisterCommand('mapscan.stop', RemoteCommandFlag.RequiresLogin, self, self.OnRconStop)
    self.m_RconPause = RCON:RegisterCommand('mapscan.pause', RemoteCommandFlag.RequiresLogin, self, self.OnRconPause)
    self.m_RconResume = RCON:RegisterCommand('mapscan.resume', RemoteCommandFlag.RequiresLogin, self, self.OnRconResume)
    self.m_RconStatus = RCON:RegisterCommand('mapscan.status', RemoteCommandFlag.RequiresLogin, self, self.OnRconStatus)
    self.m_RconPreset = RCON:RegisterCommand('mapscan.preset', RemoteCommandFlag.RequiresLogin, self, self.OnRconPreset)

    -- NetEvent from client
    NetEvents:Subscribe('MapScanner:ClientReady', self, self.OnClientReady)

    log:Info('MapScanEngine initialized.')
    if ScanConfig.autoStart then
        log:Info('  Auto-start enabled (delay: %.0fs)', ScanConfig.autoStartDelay)
    end
    if ScanConfig.autoRotate then
        log:Info('  Auto-rotate enabled (%d maps in rotation)', #ScanConfig.MapRotation)
    end
end

-- ============================================================================
-- Level Events
-- ============================================================================

function MapScanEngine:OnLevelLoaded(levelName, gameMode)
    log:Info('Level loaded: %s (mode: %s)', tostring(levelName), tostring(gameMode))

    self.m_CurrentGameMode = gameMode or 'ConquestLarge0'
    self.m_CurrentMapConfig = ScanConfig.GetMapConfig(levelName)
    self.m_MaterialIndexSet = {}

    if #self.m_MaterialNames > 0 then
        log:Info('Material dictionary: %d material names loaded', #self.m_MaterialNames)
    else
        log:Warn('No material names loaded — material indices will be numeric only')
    end
    if self.m_CurrentMapConfig then
        log:Info('Map recognized: %s (%s)', self.m_CurrentMapConfig.name, self.m_CurrentMapConfig.id)
        local spacing = ScanConfig.CalculateGridSpacing(self.m_CurrentMapConfig.width)
        local estRays = ScanConfig.EstimateRayCount(self.m_CurrentMapConfig)
        local estTime = ScanConfig.EstimateScanTime(self.m_CurrentMapConfig)
        log:Info('  Grid spacing: %.1fm | Est. rays: %d | Est. time: %.0fs (%.1f min)',
            spacing, estRays, estTime, estTime / 60)

        -- Auto-start if enabled
        if ScanConfig.autoStart then
            -- Check if already scanned this session
            if self.m_ScannedMaps[self.m_CurrentMapConfig.id] then
                log:Info('  Map already scanned this session — skipping auto-start')
            else
                log:Info('  Auto-start in %.0f seconds...', ScanConfig.autoStartDelay)
                self.m_AutoStartPending = true
                self.m_AutoStartTimer = ScanConfig.autoStartDelay
            end
        end
    else
        log:Warn('Unknown map: %s — scanning unavailable', tostring(levelName))
    end
end

function MapScanEngine:OnLevelDestroy()
    if self.m_IsScanning then
        log:Warn('Level destroying while scan in progress — aborting')
        self:StopScan('level_destroy')
    end
    self.m_AutoStartPending = false
    self.m_CurrentMapConfig = nil
end

-- ============================================================================
-- Material Name Registry — capture from MaterialContainerAsset partitions
-- ============================================================================

function MapScanEngine:OnPartitionLoaded(partition)
    if partition == nil then return end
    local instances = partition.instances
    if instances == nil then return end

    for _, instance in ipairs(instances) do
        if instance:Is('MaterialContainerAsset') then
            local asset = MaterialContainerAsset(instance)
            if asset.materialNames ~= nil and #asset.materialNames > 0 then
                for i, name in ipairs(asset.materialNames) do
                    -- materialNames is 1-indexed in Lua, physicsMaterialIndex is 0-indexed
                    self.m_MaterialNames[i - 1] = name
                end
                log:Info('Loaded %d material names from MaterialContainerAsset', #asset.materialNames)
            end
        end
    end
end

--- Extract a physics material index from a RayCastHit
--- Returns an integer index or -1 if unavailable
function MapScanEngine:GetMaterialIndex(hit)
    if hit.material == nil then
        return -1
    end

    -- hit.material is a DataContainer, try casting to MaterialContainerPair
    local ok, pair = pcall(function()
        return MaterialContainerPair(hit.material)
    end)
    if ok and pair ~= nil then
        local idx = pair.physicsMaterialIndex or -1
        self.m_MaterialIndexSet[idx] = true
        return idx
    end

    return -1
end

-- ============================================================================
-- RCON Command Handlers
-- ============================================================================

function MapScanEngine:OnRconStart(command, args, loggedIn)
    if self.m_IsScanning then
        return { 'ERR', 'Scan already in progress. Use mapscan.stop first.' }
    end
    if self.m_CurrentMapConfig == nil then
        return { 'ERR', 'No recognized map loaded.' }
    end

    if args and #args > 0 then
        local preset = args[1]
        if ScanConfig.Presets[preset] then
            ScanConfig.activePreset = preset
            log:Info('Preset overridden to: %s', preset)
        else
            return { 'ERR', 'Unknown preset: ' .. preset .. '. Available: insane, turbo, ultra, high, medium, low' }
        end
    end

    self:StartScan()
    return { 'OK', 'Scan started for ' .. self.m_CurrentMapConfig.name .. ' (' .. ScanConfig.activePreset .. ')' }
end

function MapScanEngine:OnRconStop(command, args, loggedIn)
    if not self.m_IsScanning and not self.m_AutoStartPending then
        return { 'ERR', 'No scan in progress.' }
    end
    self.m_AutoStartPending = false
    if self.m_IsScanning then
        self:StopScan('rcon_stop')
    end
    return { 'OK', 'Scan stopped.' }
end

function MapScanEngine:OnRconPause(command, args, loggedIn)
    if not self.m_IsScanning then
        return { 'ERR', 'No scan in progress.' }
    end
    self.m_IsPaused = true
    log:Info('Scan paused')
    return { 'OK', 'Scan paused.' }
end

function MapScanEngine:OnRconResume(command, args, loggedIn)
    if not self.m_IsScanning then
        return { 'ERR', 'No scan in progress.' }
    end
    self.m_IsPaused = false
    log:Info('Scan resumed')
    return { 'OK', 'Scan resumed.' }
end

function MapScanEngine:OnRconStatus(command, args, loggedIn)
    if not self.m_IsScanning then
        local msg = 'Phase: ' .. self.m_ScanPhase
        if self.m_AutoStartPending then
            msg = msg .. string.format(' | Auto-start in %.0fs', self.m_AutoStartTimer)
        end
        local scanned = {}
        for mapId, _ in pairs(self.m_ScannedMaps) do
            table.insert(scanned, mapId)
        end
        if #scanned > 0 then
            msg = msg .. ' | Scanned: ' .. table.concat(scanned, ', ')
        end
        return { 'OK', msg }
    end

    local pct = 0
    if self.m_TotalGridCells > 0 then
        pct = math.floor((self.m_CompletedCells / self.m_TotalGridCells) * 100)
    end

    local elapsed = SharedUtils:GetTimeMS() / 1000 - self.m_StartTime
    local stats = self.m_MeshBuilder:GetStats()
    local exportStats = self.m_DataExporter and self.m_DataExporter:GetStats()
        or { exportedChunks = 0, failedExports = 0, pendingUploads = 0 }

    return {
        'OK',
        string.format('Phase: %s | Progress: %d%% (%d/%d cells)',
            self.m_ScanPhase, pct, self.m_CompletedCells, self.m_TotalGridCells),
        string.format('Rays: %d | Hits: %d | Multi-layer: %d',
            self.m_TotalRaysCast, stats.totalHits, stats.multiLayerCells),
        string.format('Elapsed: %.0fs | S3 uploads: %d ok / %d fail / %d pending',
            elapsed, exportStats.exportedChunks, exportStats.failedExports, exportStats.pendingUploads),
    }
end

function MapScanEngine:OnRconPreset(command, args, loggedIn)
    if args and #args > 0 then
        local preset = args[1]
        if ScanConfig.Presets[preset] then
            ScanConfig.activePreset = preset
            return { 'OK', 'Preset set to: ' .. preset }
        else
            return { 'ERR', 'Unknown preset. Available: insane, turbo, ultra, high, medium, low' }
        end
    end
    return { 'OK', 'Current preset: ' .. ScanConfig.activePreset }
end

-- ============================================================================
-- Client Events
-- ============================================================================

function MapScanEngine:OnClientReady(player)
    if player == nil then return end
    log:Info('Client %s ready for map scanning', player.name)

    NetEvents:SendTo('MapScanner:Status', player, {
        isScanning = self.m_IsScanning,
        phase = self.m_ScanPhase,
        mapId = self.m_CurrentMapConfig and self.m_CurrentMapConfig.id or nil,
    })
end

-- ============================================================================
-- Scan Control
-- ============================================================================

function MapScanEngine:StartScan()
    local mapCfg = self.m_CurrentMapConfig
    if mapCfg == nil then
        log:Error('Cannot start scan: no map config')
        return
    end

    self.m_AutoStartPending = false

    -- Create exporter early so we can probe the bucket
    self.m_DataExporter = DataExporter:New()

    if not self.m_DataExporter.enabled then
        log:Error('S3 exporter not ready — scan aborted')
        return
    end

    -- Probe bucket before beginning the scan (async)
    log:Info('Checking S3 bucket before scan...')
    local engine = self
    self.m_DataExporter:ProbeBucket(function(bucketReady)
        if not bucketReady then
            log:Error('S3 bucket not available — scan aborted. Create the bucket manually or check credentials.')
            return
        end
        engine:BeginScanAfterProbe()
    end)
end

--- Actually begin the scan after bucket probe succeeds
function MapScanEngine:BeginScanAfterProbe()
    local mapCfg = self.m_CurrentMapConfig
    if mapCfg == nil then
        log:Error('Map config lost during probe — scan aborted')
        return
    end

    -- Calculate grid parameters
    self.m_GridSpacing = ScanConfig.CalculateGridSpacing(mapCfg.width)
    local halfWidth = mapCfg.width / 2

    self.m_ScanMinX = mapCfg.center[1] - halfWidth
    self.m_ScanMaxX = mapCfg.center[1] + halfWidth
    self.m_ScanMinZ = mapCfg.center[2] - halfWidth
    self.m_ScanMaxZ = mapCfg.center[2] + halfWidth

    self.m_CurrentX = self.m_ScanMinX
    self.m_CurrentZ = self.m_ScanMinZ

    self.m_ScanHeight = mapCfg.yMax + 100
    self.m_ScanDepth = mapCfg.yMin - 50

    local gridW = math.ceil((self.m_ScanMaxX - self.m_ScanMinX) / self.m_GridSpacing)
    local gridH = math.ceil((self.m_ScanMaxZ - self.m_ScanMinZ) / self.m_GridSpacing)
    self.m_TotalGridCells = gridW * gridH

    -- Interior scan setup
    self.m_InteriorCells = {}
    self.m_CurrentInteriorIdx = 0
    self.m_CurrentInteriorLayer = 0

    local preset = ScanConfig.GetPreset()
    if preset.interiorPasses then
        self.m_InteriorLayers = {}
        local y = mapCfg.yMin
        while y <= mapCfg.yMax do
            table.insert(self.m_InteriorLayers, y)
            y = y + preset.interiorStepY
        end
        log:Info('Interior scan: %d vertical layers from Y=%.0f to Y=%.0f',
            #self.m_InteriorLayers, mapCfg.yMin, mapCfg.yMax)
    end

    -- Initialize mesh builder
    self.m_MeshBuilder:Init(mapCfg.id, mapCfg.name, self.m_GridSpacing)

    -- DataExporter already created in StartScan() before probe

    -- Check if streaming export is enabled for this preset
    self.m_StreamingEnabled = preset.streamingExport == true
    if self.m_StreamingEnabled then
        self:InitStreamingChunks()
    end

    -- Start!
    self.m_IsScanning = true
    self.m_IsPaused = false
    self.m_ScanPhase = self.m_StreamingEnabled and 'streaming' or 'topdown'
    self.m_CompletedCells = 0
    self.m_TotalRaysCast = 0
    self.m_StartTime = SharedUtils:GetTimeMS() / 1000
    self.m_LastProgressReport = self.m_StartTime
    self.m_WaitingForUploads = false

    log:Info('========================================')
    log:Info('SCAN STARTED: %s (%s)', mapCfg.name, mapCfg.id)
    log:Info('  Preset: %s | Grid: %.1fm | Dimensions: %d x %d = %d cells',
        ScanConfig.activePreset, self.m_GridSpacing, gridW, gridH, self.m_TotalGridCells)
    if self.m_StreamingEnabled then
        log:Info('  STREAMING MODE: %d chunks (only 1 chunk in memory at a time)', #self.m_StreamChunks)
    end
    log:Info('  Area: X[%.0f..%.0f] Z[%.0f..%.0f]',
        self.m_ScanMinX, self.m_ScanMaxX, self.m_ScanMinZ, self.m_ScanMaxZ)
    log:Info('  Height: Y=%.0f down to Y=%.0f', self.m_ScanHeight, self.m_ScanDepth)
    log:Info('  Export: S3 → %s/%s', ScanConfig.s3Bucket, self.m_DataExporter:BuildKeyPrefix(mapCfg.id))
    log:Info('========================================')

    NetEvents:BroadcastLocal('MapScanner:ScanStarted', {
        mapId = mapCfg.id,
        mapName = mapCfg.name,
        gridSpacing = self.m_GridSpacing,
        totalCells = self.m_TotalGridCells,
    })
end

function MapScanEngine:StopScan(reason)
    reason = reason or 'manual'
    log:Info('Scan stopped: %s (phase: %s, completed: %d/%d)',
        reason, self.m_ScanPhase, self.m_CompletedCells, self.m_TotalGridCells)

    self.m_IsScanning = false
    self.m_IsPaused = false
    self.m_ScanPhase = 'idle'
    self.m_WaitingForUploads = false

    local stats = self.m_MeshBuilder:GetStats()
    log:Info('Final stats: %d hits, %d cells, %d multi-layer, max %d layers',
        stats.totalHits, stats.cellCount, stats.multiLayerCells, stats.maxLayers)

    NetEvents:BroadcastLocal('MapScanner:ScanStopped', { reason = reason })
end

-- ============================================================================
-- Engine Update - Main Scan Loop
-- ============================================================================

function MapScanEngine:OnEngineUpdate(dt)
    -- Handle auto-start countdown
    if self.m_AutoStartPending then
        self.m_AutoStartTimer = self.m_AutoStartTimer - dt
        if self.m_AutoStartTimer <= 0 then
            self.m_AutoStartPending = false
            log:Info('Auto-start triggering...')
            self:StartScan()
        end
        return
    end

    -- Handle waiting for S3 uploads to complete before rotating map
    if self.m_WaitingForUploads then
        if self.m_DataExporter == nil or self.m_DataExporter:IsUploadComplete() then
            log:Info('All S3 uploads complete.')
            self.m_WaitingForUploads = false
            self:OnScanAndUploadComplete()
        else
            -- Timeout after 120 seconds
            local elapsed = SharedUtils:GetTimeMS() / 1000 - self.m_UploadWaitStart
            if elapsed > 120 then
                log:Warn('Upload wait timeout (120s) — proceeding anyway')
                self.m_WaitingForUploads = false
                self:OnScanAndUploadComplete()
            end
        end
        return
    end

    if not self.m_IsScanning or self.m_IsPaused then
        return
    end

    local preset = ScanConfig.GetPreset()
    local raysThisTick = 0
    local maxRays = preset.maxRaysPerTick

    if self.m_StreamingEnabled then
        raysThisTick = self:DoStreamingTick(maxRays)
    elseif self.m_ScanPhase == 'topdown' then
        raysThisTick = self:DoTopDownScan(maxRays)
    elseif self.m_ScanPhase == 'interior' then
        raysThisTick = self:DoInteriorScan(maxRays)
    end

    self.m_TotalRaysCast = self.m_TotalRaysCast + raysThisTick

    -- Progress reporting every 5 seconds
    local now = SharedUtils:GetTimeMS() / 1000
    if now - self.m_LastProgressReport >= 5.0 then
        self.m_LastProgressReport = now
        if self.m_StreamingEnabled then
            local activeHits = self.m_MeshBuilder.totalHits - (self.m_MeshBuilder.freedHits or 0)
            log:Progress(self.m_CompletedCells, self.m_TotalGridCells,
                string.format('[streaming chunk %d/%d %s] rays=%d hits=%d active\xe2\x89\x88%.1fMB',
                    self.m_CurrentStreamChunk, #self.m_StreamChunks, self.m_ChunkPhase,
                    self.m_TotalRaysCast, self.m_MeshBuilder.totalHits,
                    (activeHits * 150) / (1024 * 1024)))
        else
            log:Progress(self.m_CompletedCells, self.m_TotalGridCells,
                string.format('[%s] rays=%d hits=%d', self.m_ScanPhase, self.m_TotalRaysCast, self.m_MeshBuilder.totalHits))
        end
    end
end

-- ============================================================================
-- Phase 1: Top-Down Scan
-- ============================================================================

function MapScanEngine:DoTopDownScan(maxRays)
    local raysCast = 0

    while raysCast < maxRays do
        if self.m_CurrentX > self.m_ScanMaxX then
            self.m_CurrentX = self.m_ScanMinX
            self.m_CurrentZ = self.m_CurrentZ + self.m_GridSpacing
        end

        if self.m_CurrentZ > self.m_ScanMaxZ then
            log:Info('Top-down scan complete. %d hits found.', self.m_MeshBuilder.totalHits)

            local preset = ScanConfig.GetPreset()
            if preset.interiorPasses and #self.m_InteriorCells > 0 then
                self.m_ScanPhase = 'interior'
                self.m_CurrentInteriorIdx = 1
                self.m_CurrentInteriorLayer = 1
                self.m_TotalGridCells = self.m_TotalGridCells + (#self.m_InteriorCells * #self.m_InteriorLayers)
                log:Info('Starting interior scan: %d cells x %d layers = %d additional scans',
                    #self.m_InteriorCells, #self.m_InteriorLayers,
                    #self.m_InteriorCells * #self.m_InteriorLayers)
            else
                self:FinishScan()
            end
            return raysCast
        end

        local from = Vec3(self.m_CurrentX, self.m_ScanHeight, self.m_CurrentZ)
        local to = Vec3(self.m_CurrentX, self.m_ScanDepth, self.m_CurrentZ)

        -- RayCastFlags: 0 = check everything (water, vehicles, ragdolls, characters, groups)
        local flags = 0
        local preset = ScanConfig.GetPreset()
        local maxHits = preset.topdownMaxHits or 10
        local hits = RaycastManager:DetailedRaycast(from, to, maxHits, 0, flags)

        if hits ~= nil and #hits > 0 then
            -- Track Y bounds for interior scanning
            local minHitY = math.huge
            local maxHitY = -math.huge

            for _, hit in ipairs(hits) do
                if hit.position ~= nil and hit.normal ~= nil then
                    local matIdx = self:GetMaterialIndex(hit)
                    self.m_MeshBuilder:AddHit(
                        hit.position.x, hit.position.y, hit.position.z,
                        hit.normal.x, hit.normal.y, hit.normal.z,
                        matIdx
                    )
                    if hit.position.y < minHitY then minHitY = hit.position.y end
                    if hit.position.y > maxHitY then maxHitY = hit.position.y end
                end
            end

            -- Only queue for interior scan if multi-layer (>=2 hits means
            -- there's geometry above the ground: roof, bridge, overhang).
            -- Single-hit cells are open terrain — no walls to capture.
            if #hits >= 2 then
                table.insert(self.m_InteriorCells, {
                    x = self.m_CurrentX,
                    z = self.m_CurrentZ,
                    yMin = minHitY,
                    yMax = maxHitY
                })
            end
        end

        raysCast = raysCast + 1
        self.m_CompletedCells = self.m_CompletedCells + 1
        self.m_CurrentX = self.m_CurrentX + self.m_GridSpacing
    end

    return raysCast
end

-- ============================================================================
-- Phase 2: Interior Scan
-- ============================================================================

function MapScanEngine:DoInteriorScan(maxRays)
    local raysCast = 0

    while raysCast < maxRays do
        if self.m_CurrentInteriorIdx > #self.m_InteriorCells then
            self.m_CurrentInteriorLayer = self.m_CurrentInteriorLayer + 1
            self.m_CurrentInteriorIdx = 1

            if self.m_CurrentInteriorLayer > #self.m_InteriorLayers then
                log:Info('Interior scan complete. Total hits: %d', self.m_MeshBuilder.totalHits)
                self:FinishScan()
                return raysCast
            end

            log:Debug('Interior layer %d/%d (Y=%.0f)',
                self.m_CurrentInteriorLayer, #self.m_InteriorLayers,
                self.m_InteriorLayers[self.m_CurrentInteriorLayer])
        end

        local cell = self.m_InteriorCells[self.m_CurrentInteriorIdx]
        local scanY = self.m_InteriorLayers[self.m_CurrentInteriorLayer]

        if cell and scanY then
            -- Skip layers outside this cell's actual geometry Y bounds
            -- (a building at Y=130-145 doesn't need scanning at Y=200)
            local pad = self.m_GridSpacing * 2
            if cell.yMin and cell.yMax and (scanY < cell.yMin - pad or scanY > cell.yMax + pad) then
                -- Skip this layer entirely for this cell — no geometry here
                self.m_CompletedCells = self.m_CompletedCells + 1
                self.m_CurrentInteriorIdx = self.m_CurrentInteriorIdx + 1
                -- Don't count as rays cast — free skip
                return raysCast
            end

            local rayLength = self.m_GridSpacing * 3
            local directions = {
                { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
                { 0.707, 0.707 }, { -0.707, 0.707 },
                { 0.707, -0.707 }, { -0.707, -0.707 },
            }

            local origin = Vec3(cell.x, scanY, cell.z)
            local flags = 0  -- check everything (water, vehicles, ragdolls, characters, groups)

            for _, dir in ipairs(directions) do
                local target = Vec3(
                    cell.x + dir[1] * rayLength,
                    scanY,
                    cell.z + dir[2] * rayLength
                )

                local hits = RaycastManager:DetailedRaycast(origin, target, 5, 0, flags)
                if hits ~= nil then
                    for _, hit in ipairs(hits) do
                        if hit.position ~= nil and hit.normal ~= nil then
                            local matIdx = self:GetMaterialIndex(hit)
                            self.m_MeshBuilder:AddHit(
                                hit.position.x, hit.position.y, hit.position.z,
                                hit.normal.x, hit.normal.y, hit.normal.z,
                                matIdx
                            )
                        end
                    end
                end

                raysCast = raysCast + 1
            end
        end

        self.m_CompletedCells = self.m_CompletedCells + 1
        self.m_CurrentInteriorIdx = self.m_CurrentInteriorIdx + 1
    end

    return raysCast
end

-- ============================================================================
-- Streaming Mode: Scan and upload one chunk at a time.
-- Only one chunk's worth of hit data is in memory at any time.
-- Enabled via preset.streamingExport = true (e.g. insane preset).
-- ============================================================================

--- Pre-compute chunk boundaries from scan area grid indices
function MapScanEngine:InitStreamingChunks()
    local spacing = self.m_GridSpacing
    local gridMinGX = math.floor(self.m_ScanMinX / spacing + 0.5)
    local gridMaxGX = math.floor(self.m_ScanMaxX / spacing + 0.5)
    local gridMinGZ = math.floor(self.m_ScanMinZ / spacing + 0.5)
    local gridMaxGZ = math.floor(self.m_ScanMaxZ / spacing + 0.5)

    local chunkSize = 64
    self.m_StreamChunks = {}

    for gx = gridMinGX, gridMaxGX, chunkSize do
        for gz = gridMinGZ, gridMaxGZ, chunkSize do
            table.insert(self.m_StreamChunks, {
                startGX = gx,
                startGZ = gz,
                chunkSize = chunkSize,
                endGX = math.min(gx + chunkSize - 1, gridMaxGX),
                endGZ = math.min(gz + chunkSize - 1, gridMaxGZ),
            })
        end
    end

    -- Recompute total cells for accurate progress tracking
    local totalCells = 0
    for _, chunk in ipairs(self.m_StreamChunks) do
        totalCells = totalCells + (chunk.endGX - chunk.startGX + 1) * (chunk.endGZ - chunk.startGZ + 1)
    end
    self.m_TotalGridCells = totalCells

    self.m_CurrentStreamChunk = 1
    self.m_StreamedChunkCount = 0
    self:InitNextStreamChunk()

    log:Info('Streaming mode: %d chunks (chunk size %d, grid GX[%d..%d] GZ[%d..%d], total cells %d)',
        #self.m_StreamChunks, chunkSize, gridMinGX, gridMaxGX, gridMinGZ, gridMaxGZ, totalCells)
end

--- Reset state for scanning the next chunk
function MapScanEngine:InitNextStreamChunk()
    if self.m_CurrentStreamChunk > #self.m_StreamChunks then
        return
    end

    local chunk = self.m_StreamChunks[self.m_CurrentStreamChunk]
    self.m_ChunkPhase = 'topdown'
    self.m_ChunkGX = chunk.startGX
    self.m_ChunkGZ = chunk.startGZ
    self.m_ChunkInteriorCells = {}
    self.m_ChunkInteriorIdx = 0
    self.m_ChunkInteriorLayer = 0

    if ScanConfig.debugLogging then
        log:Debug('Starting chunk %d/%d: GX[%d..%d] GZ[%d..%d]',
            self.m_CurrentStreamChunk, #self.m_StreamChunks,
            chunk.startGX, chunk.endGX, chunk.startGZ, chunk.endGZ)
    end
end

--- Main streaming tick dispatcher
function MapScanEngine:DoStreamingTick(maxRays)
    if self.m_CurrentStreamChunk > #self.m_StreamChunks then
        self:FinishStreamingScan()
        return 0
    end

    if self.m_ChunkPhase == 'topdown' then
        return self:DoChunkTopDown(maxRays)
    elseif self.m_ChunkPhase == 'interior' then
        return self:DoChunkInterior(maxRays)
    end

    return 0
end

--- Top-down scan within the current chunk's grid bounds
function MapScanEngine:DoChunkTopDown(maxRays)
    local chunk = self.m_StreamChunks[self.m_CurrentStreamChunk]
    local preset = ScanConfig.GetPreset()
    local maxHits = preset.topdownMaxHits or 10
    local raysCast = 0

    while raysCast < maxRays do
        if self.m_ChunkGX > chunk.endGX then
            self.m_ChunkGX = chunk.startGX
            self.m_ChunkGZ = self.m_ChunkGZ + 1
        end

        if self.m_ChunkGZ > chunk.endGZ then
            -- Chunk top-down complete
            if preset.interiorPasses and #self.m_ChunkInteriorCells > 0 then
                self.m_ChunkPhase = 'interior'
                self.m_ChunkInteriorIdx = 1
                self.m_ChunkInteriorLayer = 1
                -- Add interior cells to total for progress tracking
                self.m_TotalGridCells = self.m_TotalGridCells
                    + (#self.m_ChunkInteriorCells * #self.m_InteriorLayers)
                log:Debug('Chunk %d: top-down done (%d interior cells), starting interior',
                    self.m_CurrentStreamChunk, #self.m_ChunkInteriorCells)
            else
                self:ExportAndAdvanceChunk()
            end
            return raysCast
        end

        local worldX = self.m_ChunkGX * self.m_GridSpacing
        local worldZ = self.m_ChunkGZ * self.m_GridSpacing

        local from = Vec3(worldX, self.m_ScanHeight, worldZ)
        local to = Vec3(worldX, self.m_ScanDepth, worldZ)

        local flags = 0
        local hits = RaycastManager:DetailedRaycast(from, to, maxHits, 0, flags)

        if hits ~= nil and #hits > 0 then
            local minHitY = math.huge
            local maxHitY = -math.huge

            for _, hit in ipairs(hits) do
                if hit.position ~= nil and hit.normal ~= nil then
                    local matIdx = self:GetMaterialIndex(hit)
                    self.m_MeshBuilder:AddHit(
                        hit.position.x, hit.position.y, hit.position.z,
                        hit.normal.x, hit.normal.y, hit.normal.z,
                        matIdx
                    )
                    if hit.position.y < minHitY then minHitY = hit.position.y end
                    if hit.position.y > maxHitY then maxHitY = hit.position.y end
                end
            end

            -- Only queue for interior scan if multi-layer (>=2 vertical
            -- hits indicate roofs/bridges/overhangs with walls to capture)
            if #hits >= 2 then
                table.insert(self.m_ChunkInteriorCells, {
                    x = worldX, z = worldZ,
                    yMin = minHitY, yMax = maxHitY
                })
            end
        end

        raysCast = raysCast + 1
        self.m_CompletedCells = self.m_CompletedCells + 1
        self.m_ChunkGX = self.m_ChunkGX + 1
    end

    return raysCast
end

--- Interior scan within the current chunk's cells
function MapScanEngine:DoChunkInterior(maxRays)
    local raysCast = 0

    while raysCast < maxRays do
        if self.m_ChunkInteriorIdx > #self.m_ChunkInteriorCells then
            self.m_ChunkInteriorLayer = self.m_ChunkInteriorLayer + 1
            self.m_ChunkInteriorIdx = 1

            if self.m_ChunkInteriorLayer > #self.m_InteriorLayers then
                log:Debug('Chunk %d: interior scan complete', self.m_CurrentStreamChunk)
                self:ExportAndAdvanceChunk()
                return raysCast
            end
        end

        local cell = self.m_ChunkInteriorCells[self.m_ChunkInteriorIdx]
        local scanY = self.m_InteriorLayers[self.m_ChunkInteriorLayer]

        if cell and scanY then
            -- Skip layers outside this cell's actual geometry Y bounds
            local pad = self.m_GridSpacing * 2
            if cell.yMin and cell.yMax and (scanY < cell.yMin - pad or scanY > cell.yMax + pad) then
                self.m_CompletedCells = self.m_CompletedCells + 1
                self.m_ChunkInteriorIdx = self.m_ChunkInteriorIdx + 1
                return raysCast
            end

            local rayLength = self.m_GridSpacing * 3
            local directions = {
                { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
                { 0.707, 0.707 }, { -0.707, 0.707 },
                { 0.707, -0.707 }, { -0.707, -0.707 },
            }

            local origin = Vec3(cell.x, scanY, cell.z)
            local flags = 0

            for _, dir in ipairs(directions) do
                local target = Vec3(
                    cell.x + dir[1] * rayLength,
                    scanY,
                    cell.z + dir[2] * rayLength
                )

                local hits = RaycastManager:DetailedRaycast(origin, target, 5, 0, flags)
                if hits ~= nil then
                    for _, hit in ipairs(hits) do
                        if hit.position ~= nil and hit.normal ~= nil then
                            local matIdx = self:GetMaterialIndex(hit)
                            self.m_MeshBuilder:AddHit(
                                hit.position.x, hit.position.y, hit.position.z,
                                hit.normal.x, hit.normal.y, hit.normal.z,
                                matIdx
                            )
                        end
                    end
                end

                raysCast = raysCast + 1
            end
        end

        self.m_CompletedCells = self.m_CompletedCells + 1
        self.m_ChunkInteriorIdx = self.m_ChunkInteriorIdx + 1
    end

    return raysCast
end

--- Build mesh for current chunk, upload to S3, free memory, advance to next chunk
function MapScanEngine:ExportAndAdvanceChunk()
    local chunk = self.m_StreamChunks[self.m_CurrentStreamChunk]
    local mapId = self.m_CurrentMapConfig.id

    -- Build mesh for this chunk's grid region
    local chunkData = self.m_MeshBuilder:BuildChunk(chunk.startGX, chunk.startGZ, chunk.chunkSize)

    if chunkData.vertexCount > 0 then
        self.m_StreamedChunkCount = self.m_StreamedChunkCount + 1
        local chunkJSON = self.m_MeshBuilder:ChunkToJSON(chunkData, self.m_StreamedChunkCount)
        self.m_DataExporter:ExportChunk(mapId, self.m_StreamedChunkCount, chunkJSON)

        if ScanConfig.debugLogging then
            log:Debug('Chunk %d/%d uploaded: %d verts, %d bytes -> chunk_%03d.json',
                self.m_CurrentStreamChunk, #self.m_StreamChunks,
                chunkData.vertexCount, #chunkJSON, self.m_StreamedChunkCount)
        end
    end

    -- Free grid data for this chunk to reclaim memory immediately
    local freed = self.m_MeshBuilder:FreeChunkData(chunk.startGX, chunk.startGZ, chunk.chunkSize)
    if freed > 0 and ScanConfig.debugLogging then
        log:Debug('Freed %d hits from chunk %d', freed, self.m_CurrentStreamChunk)
    end

    -- Clear interior cells for this chunk
    self.m_ChunkInteriorCells = {}

    -- Advance to next chunk
    self.m_CurrentStreamChunk = self.m_CurrentStreamChunk + 1
    if self.m_CurrentStreamChunk <= #self.m_StreamChunks then
        self:InitNextStreamChunk()
    end
    -- If no more chunks, DoStreamingTick will call FinishStreamingScan on next tick
end

--- Final export after all streaming chunks are done: heightmap + manifest
function MapScanEngine:FinishStreamingScan()
    local elapsed = SharedUtils:GetTimeMS() / 1000 - self.m_StartTime
    local stats = self.m_MeshBuilder:GetStats()
    local mapId = self.m_CurrentMapConfig.id

    log:Info('========================================')
    log:Info('STREAMING SCAN COMPLETE: %s', self.m_CurrentMapConfig.name)
    log:Info('  Total rays: %d', self.m_TotalRaysCast)
    log:Info('  Total hits: %d (dropped: %d, freed: %d)', stats.totalHits, stats.droppedHits, stats.freedHits)
    log:Info('  Cumulative cells: %d (multi-layer: %d, peak layers: %d)',
        stats.cumulativeCells, stats.cumulativeMultiLayer, stats.peakMaxLayers)
    log:Info('  Chunks uploaded: %d / %d regions', self.m_StreamedChunkCount, #self.m_StreamChunks)
    log:Info('  Elapsed: %.1fs (%.1f min)', elapsed, elapsed / 60)
    log:Info('========================================')

    self.m_ScanPhase = 'exporting'

    -- Upload heightmap (built from accumulated heightGrid — compact, never freed)
    local heightmapJSON = self.m_MeshBuilder:HeightmapToJSON()
    log:Info('Heightmap JSON: %d bytes', #heightmapJSON)
    self.m_DataExporter:ExportHeightmap(mapId, heightmapJSON)

    -- Build material map
    local matMapParts = {}
    for idx, _ in pairs(self.m_MaterialIndexSet) do
        local name = self.m_MaterialNames[idx] or ('mat_' .. tostring(idx))
        table.insert(matMapParts, string.format('"%d":"%s"', idx, name))
    end
    local matMapJSON = '{' .. table.concat(matMapParts, ',') .. '}'

    -- Upload manifest
    local manifestData = string.format(
        '{"mapId":"%s","mapName":"%s","preset":"%s","gridSpacing":%.2f,' ..
        '"totalHits":%d,"droppedHits":%d,' ..
        '"cellCount":%d,"multiLayerCells":%d,"maxLayers":%d,' ..
        '"totalRays":%d,"elapsedSeconds":%.1f,' ..
        '"chunkCount":%d,"center":[%.2f,%.2f],"width":%d,' ..
        '"yMin":%d,"yMax":%d,"scanTimestamp":%d,' ..
        '"streamingMode":true,"materialMap":%s}',
        mapId, self.m_CurrentMapConfig.name, ScanConfig.activePreset, self.m_GridSpacing,
        stats.totalHits, stats.droppedHits,
        stats.cumulativeCells, stats.cumulativeMultiLayer, stats.peakMaxLayers,
        self.m_TotalRaysCast, elapsed,
        self.m_StreamedChunkCount,
        self.m_CurrentMapConfig.center[1], self.m_CurrentMapConfig.center[2],
        self.m_CurrentMapConfig.width,
        self.m_CurrentMapConfig.yMin, self.m_CurrentMapConfig.yMax,
        os.time(),
        matMapJSON
    )
    self.m_DataExporter:ExportManifest(mapId, manifestData)

    -- Send heightmap to clients
    NetEvents:BroadcastLocal('MapScanner:HeightmapData', heightmapJSON)

    log:Info('Export: 1 heightmap + %d chunks + 1 manifest -> S3', self.m_StreamedChunkCount)

    -- Mark map as scanned
    self.m_ScannedMaps[mapId] = true

    self.m_ScanPhase = 'complete'
    self.m_IsScanning = false

    NetEvents:BroadcastLocal('MapScanner:ScanComplete', {
        mapId = mapId,
        totalHits = stats.totalHits,
        elapsed = elapsed,
    })

    -- Wait for uploads before rotating
    if ScanConfig.autoRotate then
        self.m_WaitingForUploads = true
        self.m_UploadWaitStart = SharedUtils:GetTimeMS() / 1000
        log:Info('Waiting for S3 uploads to complete before map rotation...')
    end
end

-- ============================================================================
-- Phase 3: Finish & Export to S3
-- ============================================================================

function MapScanEngine:FinishScan()
    local elapsed = SharedUtils:GetTimeMS() / 1000 - self.m_StartTime
    local stats = self.m_MeshBuilder:GetStats()

    log:Info('========================================')
    log:Info('SCAN COMPLETE: %s', self.m_CurrentMapConfig.name)
    log:Info('  Total rays: %d', self.m_TotalRaysCast)
    log:Info('  Total hits: %d (dropped: %d due to cell cap)', stats.totalHits, stats.droppedHits)
    log:Info('  Grid cells with data: %d', stats.cellCount)
    log:Info('  Multi-layer cells: %d (max %d layers)', stats.multiLayerCells, stats.maxLayers)
    log:Info('  Est. memory: %.1f MB', stats.estMemoryMB)
    log:Info('  Elapsed time: %.1fs (%.1f min)', elapsed, elapsed / 60)
    log:Info('========================================')

    self.m_ScanPhase = 'exporting'
    self:ExportData()
end

function MapScanEngine:ExportData()
    log:Info('Starting S3 export...')

    local mapId = self.m_CurrentMapConfig.id
    local stats = self.m_MeshBuilder:GetStats()

    log:Info('Pre-export stats: %d hits (est. %.1f MB), %d dropped (cell cap)',
        stats.totalHits, stats.estMemoryMB, stats.droppedHits)

    -- 1. Export heightmap FIRST (uses compact heightGrid, not the full grid)
    local heightmapJSON = self.m_MeshBuilder:HeightmapToJSON()
    log:Info('Heightmap JSON: %d bytes', #heightmapJSON)
    self.m_DataExporter:ExportHeightmap(mapId, heightmapJSON)

    -- 2. Export mesh chunks incrementally — build, upload, FREE each chunk's data
    local chunks = self.m_MeshBuilder:GetChunks(64)
    log:Info('Exporting %d mesh chunks to S3 (streaming — freeing memory per chunk)...', #chunks)

    local uploadedChunks = 0
    local totalFreed = 0
    for i, chunk in ipairs(chunks) do
        local chunkData = self.m_MeshBuilder:BuildChunk(chunk.startGX, chunk.startGZ, chunk.chunkSize)
        if chunkData.vertexCount > 0 then
            local chunkJSON = self.m_MeshBuilder:ChunkToJSON(chunkData, i)
            self.m_DataExporter:ExportChunk(mapId, i, chunkJSON)
            uploadedChunks = uploadedChunks + 1
        end
        -- Free this chunk's grid data to reclaim memory immediately
        local freed = self.m_MeshBuilder:FreeChunkData(chunk.startGX, chunk.startGZ, chunk.chunkSize)
        totalFreed = totalFreed + freed
    end

    log:Info('Freed %d hits from grid after chunk export (grid should be ~empty)', totalFreed)

    -- 3. Export manifest with scan metadata
    local elapsed = SharedUtils:GetTimeMS() / 1000 - self.m_StartTime

    -- Build material map JSON: { "0": "Concrete", "1": "Metal", ... }
    local matMapParts = {}
    for idx, _ in pairs(self.m_MaterialIndexSet) do
        local name = self.m_MaterialNames[idx] or ('mat_' .. tostring(idx))
        table.insert(matMapParts, string.format('"%d":"%s"', idx, name))
    end
    local matMapJSON = '{' .. table.concat(matMapParts, ',') .. '}'
    log:Info('Material map: %d unique materials captured', #matMapParts)

    local manifestData = string.format(
        '{"mapId":"%s","mapName":"%s","preset":"%s","gridSpacing":%.2f,' ..
        '"totalHits":%d,"droppedHits":%d,"cellCount":%d,"multiLayerCells":%d,"maxLayers":%d,' ..
        '"totalRays":%d,"elapsedSeconds":%.1f,' ..
        '"chunkCount":%d,"center":[%.2f,%.2f],"width":%d,' ..
        '"yMin":%d,"yMax":%d,"scanTimestamp":%d,' ..
        '"materialMap":%s}',
        mapId, self.m_CurrentMapConfig.name, ScanConfig.activePreset, self.m_GridSpacing,
        stats.totalHits, stats.droppedHits, stats.cellCount, stats.multiLayerCells, stats.maxLayers,
        self.m_TotalRaysCast, elapsed,
        uploadedChunks,
        self.m_CurrentMapConfig.center[1], self.m_CurrentMapConfig.center[2],
        self.m_CurrentMapConfig.width,
        self.m_CurrentMapConfig.yMin, self.m_CurrentMapConfig.yMax,
        os.time()
    )
    self.m_DataExporter:ExportManifest(mapId, manifestData)

    -- 4. Send heightmap to clients for debug visualization
    NetEvents:BroadcastLocal('MapScanner:HeightmapData', heightmapJSON)

    log:Info('Export queued: 1 heightmap + %d chunks + 1 manifest → S3', uploadedChunks)

    -- Mark this map as scanned
    self.m_ScannedMaps[mapId] = true

    -- Mark scanning complete but wait for S3 uploads
    self.m_ScanPhase = 'complete'
    self.m_IsScanning = false

    NetEvents:BroadcastLocal('MapScanner:ScanComplete', {
        mapId = mapId,
        totalHits = stats.totalHits,
        elapsed = elapsed,
    })

    -- Wait for uploads to finish before rotating
    if ScanConfig.autoRotate then
        self.m_WaitingForUploads = true
        self.m_UploadWaitStart = SharedUtils:GetTimeMS() / 1000
        log:Info('Waiting for S3 uploads to complete before map rotation...')
    end
end

-- ============================================================================
-- Auto-Rotate: advance to next map after scan + upload
-- ============================================================================

function MapScanEngine:OnScanAndUploadComplete()
    if not ScanConfig.autoRotate then return end
    if self.m_CurrentMapConfig == nil then return end

    local currentMapId = self.m_CurrentMapConfig.id
    local nextMap = ScanConfig.GetNextMap(currentMapId)

    if nextMap == nil then
        log:Info('========================================')
        log:Info('ALL MAPS SCANNED — rotation complete!')
        log:Info('Scanned %d maps this session:', 0)
        local count = 0
        for mapId, _ in pairs(self.m_ScannedMaps) do
            count = count + 1
            log:Info('  %d. %s', count, mapId)
        end
        log:Info('========================================')
        return
    end

    log:Info('Rotating to next map: %s (gameMode: %s)', nextMap.mapId, self.m_CurrentGameMode)

    -- Use RCON to switch map
    -- Use the currently detected game mode (from Level:Loaded) rather than the
    -- hardcoded mode in MapRotation, since modded servers (e.g. RealityMod) use
    -- custom game modes like AdvanceAndSecureStd instead of ConquestLarge0.
    -- The layer (rounds param) comes from the rotation entry for maps with specific layers.
    local gameMode = self.m_CurrentGameMode or nextMap.gameMode or 'AdvanceAndSecureStd'
    local layer = tostring(nextMap.layer or 1)
    RCON:SendCommand('mapList.clear')
    RCON:SendCommand('mapList.add', { nextMap.mapId, gameMode, layer })
    RCON:SendCommand('mapList.setNextMapIndex', { '0' })
    RCON:SendCommand('mapList.runNextRound')

    log:Info('RCON commands sent — map should switch shortly')
end

return MapScanEngine
