-- MapScanner Server-Side Raycast Engine
-- Performs systematic grid-based raycasting to scan entire map geometry
-- Supports multi-layer scanning for building interiors

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
    self.m_ScanHeight = 500          -- Y position to cast FROM (above map)
    self.m_ScanDepth = -50           -- Y position to cast TO (below map)

    -- Interior scan state
    self.m_InteriorLayers = {}
    self.m_CurrentInteriorLayer = 0
    self.m_InteriorCells = {}        -- cells that need interior scanning (had hits)
    self.m_CurrentInteriorIdx = 0

    -- Progress tracking
    self.m_TotalGridCells = 0
    self.m_CompletedCells = 0
    self.m_TotalRaysCast = 0
    self.m_StartTime = 0
    self.m_LastProgressReport = 0

    -- Data storage
    self.m_MeshBuilder = MeshBuilder:New()
    self.m_DataExporter = DataExporter:New()
    self.m_ScanId = nil

    -- Export state
    self.m_ExportChunks = {}
    self.m_CurrentExportChunk = 0

    -- Event subscriptions
    Events:Subscribe('Level:Loaded', self, self.OnLevelLoaded)
    Events:Subscribe('Level:Destroy', self, self.OnLevelDestroy)
    Events:Subscribe('Engine:Update', self, self.OnEngineUpdate)

    -- RCON commands
    self.m_RconScan = RCON:RegisterCommand('mapscan.start', RemoteCommandFlag.RequiresLogin, self, self.OnRconStart)
    self.m_RconStop = RCON:RegisterCommand('mapscan.stop', RemoteCommandFlag.RequiresLogin, self, self.OnRconStop)
    self.m_RconPause = RCON:RegisterCommand('mapscan.pause', RemoteCommandFlag.RequiresLogin, self, self.OnRconPause)
    self.m_RconResume = RCON:RegisterCommand('mapscan.resume', RemoteCommandFlag.RequiresLogin, self, self.OnRconResume)
    self.m_RconStatus = RCON:RegisterCommand('mapscan.status', RemoteCommandFlag.RequiresLogin, self, self.OnRconStatus)
    self.m_RconPreset = RCON:RegisterCommand('mapscan.preset', RemoteCommandFlag.RequiresLogin, self, self.OnRconPreset)
    self.m_RconExport = RCON:RegisterCommand('mapscan.export', RemoteCommandFlag.RequiresLogin, self, self.OnRconExport)
    self.m_RconScans = RCON:RegisterCommand('mapscan.list', RemoteCommandFlag.RequiresLogin, self, self.OnRconListScans)
    self.m_RconRetrieve = RCON:RegisterCommand('mapscan.retrieve', RemoteCommandFlag.RequiresLogin, self, self.OnRconRetrieve)

    -- NetEvent from client
    NetEvents:Subscribe('MapScanner:ClientReady', self, self.OnClientReady)

    log:Info('MapScanEngine initialized. Use RCON "mapscan.start" to begin scanning.')
end

-- ============================================================================
-- Level Events
-- ============================================================================

function MapScanEngine:OnLevelLoaded(levelName, gameMode)
    log:Info('Level loaded: %s (mode: %s)', tostring(levelName), tostring(gameMode))

    self.m_CurrentMapConfig = ScanConfig.GetMapConfig(levelName)
    if self.m_CurrentMapConfig then
        log:Info('Map recognized: %s (%s)', self.m_CurrentMapConfig.name, self.m_CurrentMapConfig.id)
        local spacing = ScanConfig.CalculateGridSpacing(self.m_CurrentMapConfig.width)
        local estRays = ScanConfig.EstimateRayCount(self.m_CurrentMapConfig)
        local estTime = ScanConfig.EstimateScanTime(self.m_CurrentMapConfig)
        log:Info('  Grid spacing: %.1fm | Est. rays: %d | Est. time: %.0fs (%.1f min)',
            spacing, estRays, estTime, estTime / 60)
    else
        log:Warn('Unknown map: %s — scanning unavailable', tostring(levelName))
    end
end

function MapScanEngine:OnLevelDestroy()
    if self.m_IsScanning then
        log:Warn('Level destroying while scan in progress — aborting')
        self:StopScan('level_destroy')
    end
    self.m_CurrentMapConfig = nil
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

    -- Optional: override preset via args
    if args and #args > 0 then
        local preset = args[1]
        if ScanConfig.Presets[preset] then
            ScanConfig.activePreset = preset
            log:Info('Preset overridden to: %s', preset)
        else
            return { 'ERR', 'Unknown preset: ' .. preset .. '. Available: ultra, high, medium, low' }
        end
    end

    self:StartScan()
    return { 'OK', 'Scan started for ' .. self.m_CurrentMapConfig.name .. ' (' .. ScanConfig.activePreset .. ')' }
end

function MapScanEngine:OnRconStop(command, args, loggedIn)
    if not self.m_IsScanning then
        return { 'ERR', 'No scan in progress.' }
    end
    self:StopScan('rcon_stop')
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
        return { 'OK', 'No scan in progress.', 'Phase: ' .. self.m_ScanPhase }
    end

    local pct = 0
    if self.m_TotalGridCells > 0 then
        pct = math.floor((self.m_CompletedCells / self.m_TotalGridCells) * 100)
    end

    local elapsed = SharedUtils:GetTimeMS() / 1000 - self.m_StartTime
    local stats = self.m_MeshBuilder:GetStats()

    return {
        'OK',
        string.format('Phase: %s | Progress: %d%% (%d/%d cells)',
            self.m_ScanPhase, pct, self.m_CompletedCells, self.m_TotalGridCells),
        string.format('Rays cast: %d | Hits: %d | Multi-layer cells: %d',
            self.m_TotalRaysCast, stats.totalHits, stats.multiLayerCells),
        string.format('Elapsed: %.0fs | Paused: %s',
            elapsed, tostring(self.m_IsPaused)),
    }
end

function MapScanEngine:OnRconPreset(command, args, loggedIn)
    if args and #args > 0 then
        local preset = args[1]
        if ScanConfig.Presets[preset] then
            ScanConfig.activePreset = preset
            return { 'OK', 'Preset set to: ' .. preset }
        else
            return { 'ERR', 'Unknown preset. Available: ultra, high, medium, low' }
        end
    end
    return { 'OK', 'Current preset: ' .. ScanConfig.activePreset }
end

function MapScanEngine:OnRconExport(command, args, loggedIn)
    if self.m_IsScanning and self.m_ScanPhase ~= 'complete' then
        return { 'ERR', 'Scan not complete. Wait for completion or stop first.' }
    end

    if self.m_MeshBuilder.totalHits == 0 then
        return { 'ERR', 'No scan data available.' }
    end

    self:ExportData()
    return { 'OK', 'Export started.' }
end

function MapScanEngine:OnRconListScans(command, args, loggedIn)
    local scans = self.m_DataExporter:GetStoredScans()
    local results = { 'OK', 'Stored scans:' }
    for _, scan in ipairs(scans) do
        table.insert(results, string.format('#%d %s (%s) - %s - %d hits',
            scan['id'], scan['map_id'], scan['scan_preset'],
            scan['status'], scan['total_hits'] or 0))
    end
    if #scans == 0 then
        table.insert(results, '(none)')
    end
    return results
end

function MapScanEngine:OnRconRetrieve(command, args, loggedIn)
    if not args or #args < 1 then
        return { 'ERR', 'Usage: mapscan.retrieve <scanId> [heightmap|chunks]' }
    end

    local scanId = tonumber(args[1])
    local dataType = args[2] or 'heightmap'

    if dataType == 'heightmap' then
        local data = self.m_DataExporter:GetStoredHeightmap(scanId)
        if data then
            -- Send via NetEvent to connected clients for download
            NetEvents:BroadcastLocal('MapScanner:HeightmapData', data)
            return { 'OK', 'Heightmap data broadcast to clients (' .. #data .. ' bytes)' }
        else
            return { 'ERR', 'No heightmap found for scan #' .. scanId }
        end
    elseif dataType == 'chunks' then
        local chunks = self.m_DataExporter:GetStoredChunks(scanId)
        return { 'OK', string.format('Scan #%d has %d chunks stored', scanId, #chunks) }
    end

    return { 'ERR', 'Unknown data type: ' .. dataType }
end

-- ============================================================================
-- Client Events
-- ============================================================================

function MapScanEngine:OnClientReady(player)
    if player == nil then return end
    log:Info('Client %s ready for map scanning', player.name)

    -- Send current status to client
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

    -- Calculate grid parameters
    self.m_GridSpacing = ScanConfig.CalculateGridSpacing(mapCfg.width)
    local halfWidth = mapCfg.width / 2

    self.m_ScanMinX = mapCfg.center[1] - halfWidth
    self.m_ScanMaxX = mapCfg.center[1] + halfWidth
    self.m_ScanMinZ = mapCfg.center[2] - halfWidth
    self.m_ScanMaxZ = mapCfg.center[2] + halfWidth

    -- Start from top-left corner
    self.m_CurrentX = self.m_ScanMinX
    self.m_CurrentZ = self.m_ScanMinZ

    -- Set scan height well above the highest point
    self.m_ScanHeight = mapCfg.yMax + 100
    self.m_ScanDepth = mapCfg.yMin - 50

    -- Calculate total cells
    local gridW = math.ceil((self.m_ScanMaxX - self.m_ScanMinX) / self.m_GridSpacing)
    local gridH = math.ceil((self.m_ScanMaxZ - self.m_ScanMinZ) / self.m_GridSpacing)
    self.m_TotalGridCells = gridW * gridH

    -- Interior scan setup
    self.m_InteriorCells = {}
    self.m_CurrentInteriorIdx = 0
    self.m_CurrentInteriorLayer = 0

    local preset = ScanConfig.GetPreset()
    if preset.interiorPasses then
        local yRange = mapCfg.yMax - mapCfg.yMin
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

    -- Initialize data exporter and create scan record
    self.m_ScanId = self.m_DataExporter:StartScanRecord(mapCfg.id, mapCfg.name, self.m_GridSpacing)

    -- Start!
    self.m_IsScanning = true
    self.m_IsPaused = false
    self.m_ScanPhase = 'topdown'
    self.m_CompletedCells = 0
    self.m_TotalRaysCast = 0
    self.m_StartTime = SharedUtils:GetTimeMS() / 1000
    self.m_LastProgressReport = self.m_StartTime

    log:Info('========================================')
    log:Info('SCAN STARTED: %s (%s)', mapCfg.name, mapCfg.id)
    log:Info('  Preset: %s | Grid: %.1fm | Dimensions: %d x %d = %d cells',
        ScanConfig.activePreset, self.m_GridSpacing, gridW, gridH, self.m_TotalGridCells)
    log:Info('  Area: X[%.0f..%.0f] Z[%.0f..%.0f]',
        self.m_ScanMinX, self.m_ScanMaxX, self.m_ScanMinZ, self.m_ScanMaxZ)
    log:Info('  Height: Y=%.0f down to Y=%.0f', self.m_ScanHeight, self.m_ScanDepth)
    log:Info('========================================')

    -- Notify clients
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

    -- Print final stats
    local stats = self.m_MeshBuilder:GetStats()
    log:Info('Final stats: %d hits, %d cells, %d multi-layer, max %d layers',
        stats.totalHits, stats.cellCount, stats.multiLayerCells, stats.maxLayers)

    NetEvents:BroadcastLocal('MapScanner:ScanStopped', { reason = reason })
end

-- ============================================================================
-- Engine Update - Main Scan Loop
-- ============================================================================

function MapScanEngine:OnEngineUpdate(dt)
    if not self.m_IsScanning or self.m_IsPaused then
        return
    end

    local preset = ScanConfig.GetPreset()
    local raysThisTick = 0
    local maxRays = preset.maxRaysPerTick

    -- Dispatch based on current phase
    if self.m_ScanPhase == 'topdown' then
        raysThisTick = self:DoTopDownScan(maxRays)
    elseif self.m_ScanPhase == 'interior' then
        raysThisTick = self:DoInteriorScan(maxRays)
    elseif self.m_ScanPhase == 'exporting' then
        self:DoExport()
    end

    self.m_TotalRaysCast = self.m_TotalRaysCast + raysThisTick

    -- Progress reporting every 5 seconds
    local now = SharedUtils:GetTimeMS() / 1000
    if now - self.m_LastProgressReport >= 5.0 then
        self.m_LastProgressReport = now
        local pct = 0
        if self.m_TotalGridCells > 0 then
            pct = math.floor((self.m_CompletedCells / self.m_TotalGridCells) * 100)
        end
        log:Progress(self.m_CompletedCells, self.m_TotalGridCells,
            string.format('[%s] rays=%d hits=%d', self.m_ScanPhase, self.m_TotalRaysCast, self.m_MeshBuilder.totalHits))
    end
end

-- ============================================================================
-- Phase 1: Top-Down Scan
-- Cast rays straight down from above to find ground/roof surfaces
-- ============================================================================

function MapScanEngine:DoTopDownScan(maxRays)
    local raysCast = 0

    while raysCast < maxRays do
        -- Check if we've finished the grid
        if self.m_CurrentX > self.m_ScanMaxX then
            self.m_CurrentX = self.m_ScanMinX
            self.m_CurrentZ = self.m_CurrentZ + self.m_GridSpacing
        end

        if self.m_CurrentZ > self.m_ScanMaxZ then
            -- Phase 1 complete!
            log:Info('Top-down scan complete. %d hits found.', self.m_MeshBuilder.totalHits)

            -- Move to interior phase if enabled
            local preset = ScanConfig.GetPreset()
            if preset.interiorPasses and #self.m_InteriorCells > 0 then
                self.m_ScanPhase = 'interior'
                self.m_CurrentInteriorIdx = 1
                self.m_CurrentInteriorLayer = 1

                -- Add interior cells to total count
                self.m_TotalGridCells = self.m_TotalGridCells + (#self.m_InteriorCells * #self.m_InteriorLayers)
                log:Info('Starting interior scan: %d cells x %d layers = %d additional scans',
                    #self.m_InteriorCells, #self.m_InteriorLayers,
                    #self.m_InteriorCells * #self.m_InteriorLayers)
            else
                self:FinishScan()
            end
            return raysCast
        end

        -- Cast a ray straight down at this grid point
        local from = Vec3(self.m_CurrentX, self.m_ScanHeight, self.m_CurrentZ)
        local to = Vec3(self.m_CurrentX, self.m_ScanDepth, self.m_CurrentZ)

        -- Use DetailedRaycast for maximum geometry fidelity
        -- RayCastFlags: DontCheckWater(4) + DontCheckCharacter(32) + DontCheckRagdoll(16) = 52
        local flags = 52
        local hits = RaycastManager:DetailedRaycast(from, to, 10, 0, flags)

        if hits ~= nil and #hits > 0 then
            -- Record this cell as needing interior scanning
            table.insert(self.m_InteriorCells, { x = self.m_CurrentX, z = self.m_CurrentZ })

            for _, hit in ipairs(hits) do
                if hit.position ~= nil and hit.normal ~= nil then
                    -- Clone position and normal to avoid engine memory reuse
                    local px = hit.position.x
                    local py = hit.position.y
                    local pz = hit.position.z
                    local nx = hit.normal.x
                    local ny = hit.normal.y
                    local nz = hit.normal.z

                    self.m_MeshBuilder:AddHit(px, py, pz, nx, ny, nz)
                end
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
-- Cast horizontal rays at multiple heights to capture building interiors
-- Rays are cast in 4 cardinal directions from each cell center
-- ============================================================================

function MapScanEngine:DoInteriorScan(maxRays)
    local raysCast = 0
    local preset = ScanConfig.GetPreset()

    while raysCast < maxRays do
        -- Check bounds
        if self.m_CurrentInteriorIdx > #self.m_InteriorCells then
            -- Move to next layer
            self.m_CurrentInteriorLayer = self.m_CurrentInteriorLayer + 1
            self.m_CurrentInteriorIdx = 1

            if self.m_CurrentInteriorLayer > #self.m_InteriorLayers then
                -- All interior layers done
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
            -- Cast rays in 4 cardinal directions + 4 diagonals at this height
            local rayLength = self.m_GridSpacing * 3  -- scan 3 cells out
            local directions = {
                { 1, 0 },     -- East
                { -1, 0 },    -- West
                { 0, 1 },     -- North
                { 0, -1 },    -- South
                { 0.707, 0.707 },   -- NE
                { -0.707, 0.707 },  -- NW
                { 0.707, -0.707 },  -- SE
                { -0.707, -0.707 }, -- SW
            }

            local origin = Vec3(cell.x, scanY, cell.z)
            local flags = 52 -- DontCheckWater + DontCheckCharacter + DontCheckRagdoll

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
                            local px = hit.position.x
                            local py = hit.position.y
                            local pz = hit.position.z
                            local nx = hit.normal.x
                            local ny = hit.normal.y
                            local nz = hit.normal.z

                            self.m_MeshBuilder:AddHit(px, py, pz, nx, ny, nz)
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
-- Phase 3: Finish & Export
-- ============================================================================

function MapScanEngine:FinishScan()
    local elapsed = SharedUtils:GetTimeMS() / 1000 - self.m_StartTime
    local stats = self.m_MeshBuilder:GetStats()

    log:Info('========================================')
    log:Info('SCAN COMPLETE: %s', self.m_CurrentMapConfig.name)
    log:Info('  Total rays: %d', self.m_TotalRaysCast)
    log:Info('  Total hits: %d', stats.totalHits)
    log:Info('  Grid cells with data: %d', stats.cellCount)
    log:Info('  Multi-layer cells: %d (max %d layers)', stats.multiLayerCells, stats.maxLayers)
    log:Info('  Elapsed time: %.1fs (%.1f min)', elapsed, elapsed / 60)
    log:Info('========================================')

    -- Auto-export
    self:ExportData()

    self.m_ScanPhase = 'complete'

    NetEvents:BroadcastLocal('MapScanner:ScanComplete', {
        mapId = self.m_CurrentMapConfig.id,
        totalHits = stats.totalHits,
        elapsed = elapsed,
    })
end

function MapScanEngine:ExportData()
    self.m_ScanPhase = 'exporting'
    log:Info('Starting data export...')

    -- 1. Export heightmap
    local heightmapJSON = self.m_MeshBuilder:HeightmapToJSON()
    log:Info('Heightmap JSON: %d bytes', #heightmapJSON)

    if ScanConfig.useHttpExport then
        self.m_DataExporter:ExportHeightmapHTTP(heightmapJSON, function(success)
            if success then
                log:Info('Heightmap exported via HTTP')
            else
                log:Warn('Heightmap HTTP export failed, saving to SQL')
                if self.m_ScanId then
                    self.m_DataExporter:SaveHeightmapSQL(self.m_ScanId, heightmapJSON)
                end
            end
        end)
    else
        if self.m_ScanId then
            self.m_DataExporter:SaveHeightmapSQL(self.m_ScanId, heightmapJSON)
            log:Info('Heightmap saved to SQL')
        end
    end

    -- 2. Export mesh chunks
    local chunks = self.m_MeshBuilder:GetChunks(64)
    log:Info('Exporting %d mesh chunks...', #chunks)

    for i, chunk in ipairs(chunks) do
        local chunkData = self.m_MeshBuilder:BuildChunk(chunk.startGX, chunk.startGZ, chunk.chunkSize)

        if chunkData.vertexCount > 0 then
            local chunkJSON = self.m_MeshBuilder:ChunkToJSON(chunkData, i)

            if ScanConfig.useHttpExport then
                self.m_DataExporter:ExportChunkHTTP(chunkJSON, i, function(success)
                    if not success and self.m_ScanId then
                        self.m_DataExporter:SaveChunkSQL(self.m_ScanId, i, chunkJSON,
                            chunkData.vertexCount, chunkData.indexCount)
                    end
                end)
            else
                if self.m_ScanId then
                    self.m_DataExporter:SaveChunkSQL(self.m_ScanId, i, chunkJSON,
                        chunkData.vertexCount, chunkData.indexCount)
                end
            end
        end
    end

    -- 3. Complete the scan record
    if self.m_ScanId then
        self.m_DataExporter:CompleteScanRecord(self.m_ScanId, self.m_MeshBuilder.totalHits)
    end

    -- 4. Send full heightmap to clients for immediate visualization
    NetEvents:BroadcastLocal('MapScanner:HeightmapData', heightmapJSON)

    local exportStats = self.m_DataExporter:GetStats()
    log:Info('Export complete: %d chunks exported, %d failed',
        exportStats.exportedChunks, exportStats.failedExports)

    self.m_ScanPhase = 'complete'
    self.m_IsScanning = false
end

return MapScanEngine
