-- MapScanner Client-Side Visual Feedback & Enhanced Scanning
-- Provides real-time visualization of scan progress using DebugRenderer
-- Also supports client-side DetailedRaycast for higher-fidelity geometry
-- (Client has access to detail meshes that server collision doesn't)

local ScanConfig = require '__shared/ScanConfig'
local Logger = require '__shared/ScanLogger'

local log = Logger:New('MapScanClient')

class 'MapScanClient'

function MapScanClient:__init()
    log:Info('MapScanClient initializing...')

    -- State
    self.m_IsScanning = false
    self.m_ScanPhase = 'idle'
    self.m_MapId = nil
    self.m_ShowDebug = true
    self.m_ShowProgress = true

    -- Scan progress from server
    self.m_Progress = {
        totalCells = 0,
        completedCells = 0,
        totalHits = 0,
        phase = 'idle',
    }

    -- Client-side enhanced scan state
    self.m_ClientScanEnabled = false
    self.m_ClientScanQueue = {}         -- queue of {x, z} positions to scan
    self.m_ClientScanIdx = 0
    self.m_ClientHits = {}              -- collected hit points for visualization
    self.m_MaxVisualizationHits = 5000  -- limit rendered points

    -- Heightmap data received from server
    self.m_HeightmapData = nil

    -- Event subscriptions
    Events:Subscribe('Engine:Update', self, self.OnUpdate)
    Events:Subscribe('UI:DrawHud', self, self.OnDrawHud)
    Events:Subscribe('Client:UpdateInput', self, self.OnUpdateInput)
    Events:Subscribe('Level:Loaded', self, self.OnLevelLoaded)
    Events:Subscribe('Level:Destroy', self, self.OnLevelDestroy)

    -- NetEvents from server
    NetEvents:Subscribe('MapScanner:Status', self, self.OnServerStatus)
    NetEvents:Subscribe('MapScanner:ScanStarted', self, self.OnScanStarted)
    NetEvents:Subscribe('MapScanner:ScanStopped', self, self.OnScanStopped)
    NetEvents:Subscribe('MapScanner:ScanComplete', self, self.OnScanComplete)
    NetEvents:Subscribe('MapScanner:HeightmapData', self, self.OnHeightmapData)

    log:Info('MapScanClient initialized. Press F9 to toggle debug visualization.')
end

-- ============================================================================
-- Level Events
-- ============================================================================

function MapScanClient:OnLevelLoaded(levelName, gameMode)
    log:Info('Level loaded: %s', tostring(levelName))
    -- Notify server we're ready
    NetEvents:SendLocal('MapScanner:ClientReady')
end

function MapScanClient:OnLevelDestroy()
    self.m_IsScanning = false
    self.m_ClientScanEnabled = false
    self.m_ClientHits = {}
    self.m_HeightmapData = nil
end

-- ============================================================================
-- Server Event Handlers
-- ============================================================================

function MapScanClient:OnServerStatus(data)
    if data then
        self.m_IsScanning = data.isScanning or false
        self.m_ScanPhase = data.phase or 'idle'
        self.m_MapId = data.mapId
    end
end

function MapScanClient:OnScanStarted(data)
    if data then
        self.m_IsScanning = true
        self.m_ScanPhase = 'scanning'
        self.m_MapId = data.mapId
        self.m_Progress.totalCells = data.totalCells or 0
        self.m_Progress.completedCells = 0
        self.m_ClientHits = {}
        log:Info('Server scan started: %s (%d cells)', data.mapName or '?', data.totalCells or 0)
    end
end

function MapScanClient:OnScanStopped(data)
    self.m_IsScanning = false
    self.m_ScanPhase = 'idle'
    log:Info('Server scan stopped: %s', data and data.reason or '?')
end

function MapScanClient:OnScanComplete(data)
    self.m_IsScanning = false
    self.m_ScanPhase = 'complete'
    if data then
        log:Info('Scan complete! %d hits in %.1fs', data.totalHits or 0, data.elapsed or 0)
    end
end

function MapScanClient:OnHeightmapData(jsonData)
    if jsonData then
        self.m_HeightmapData = jsonData
        log:Info('Received heightmap data: %d bytes', #jsonData)
    end
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function MapScanClient:OnUpdateInput(dt)
    -- F9: Toggle debug visualization
    if InputManager:WentKeyDown(InputDeviceKeys.IDK_F9) then
        self.m_ShowDebug = not self.m_ShowDebug
        log:Info('Debug visualization: %s', self.m_ShowDebug and 'ON' or 'OFF')
    end

    -- F10: Perform a single client-side raycast at crosshair for testing
    if InputManager:WentKeyDown(InputDeviceKeys.IDK_F10) then
        self:DoTestRaycast()
    end

    -- F11: Start client-side enhanced local area scan
    if InputManager:WentKeyDown(InputDeviceKeys.IDK_F11) then
        self:StartClientLocalScan()
    end

    -- F12: Toggle progress HUD
    if InputManager:WentKeyDown(InputDeviceKeys.IDK_F12) then
        self.m_ShowProgress = not self.m_ShowProgress
        log:Info('Progress HUD: %s', self.m_ShowProgress and 'ON' or 'OFF')
    end
end

-- ============================================================================
-- Test Raycast (F10)
-- Single detailed raycast from camera to show what the scanner would capture
-- ============================================================================

function MapScanClient:DoTestRaycast()
    local camTransform = ClientUtils:GetCameraTransform()
    if camTransform == nil then
        log:Warn('No camera transform available')
        return
    end

    -- Look direction is negative forward in Frostbite
    local lookDir = Vec3(
        camTransform.forward.x * -1,
        camTransform.forward.y * -1,
        camTransform.forward.z * -1
    )

    local from = camTransform.trans:Clone()
    local to = Vec3(
        from.x + lookDir.x * 500,
        from.y + lookDir.y * 500,
        from.z + lookDir.z * 500
    )

    -- DetailedRaycast with CheckDetailMesh for highest fidelity
    local flags = 4 + 32 + 16  -- DontCheckWater + DontCheckCharacter + DontCheckRagdoll
    local hits = RaycastManager:DetailedRaycast(from, to, 10, 0, flags)

    if hits ~= nil and #hits > 0 then
        log:Info('Test raycast: %d hits', #hits)
        for i, hit in ipairs(hits) do
            if hit.position then
                log:Info('  Hit %d: pos=(%.1f, %.1f, %.1f) normal=(%.2f, %.2f, %.2f)',
                    i, hit.position.x, hit.position.y, hit.position.z,
                    hit.normal and hit.normal.x or 0,
                    hit.normal and hit.normal.y or 0,
                    hit.normal and hit.normal.z or 0)

                -- Store for visualization
                if #self.m_ClientHits < self.m_MaxVisualizationHits then
                    table.insert(self.m_ClientHits, {
                        x = hit.position.x, y = hit.position.y, z = hit.position.z,
                        nx = hit.normal and hit.normal.x or 0,
                        ny = hit.normal and hit.normal.y or 0,
                        nz = hit.normal and hit.normal.z or 0,
                    })
                end
            end
        end
    else
        log:Info('Test raycast: no hits')
    end
end

-- ============================================================================
-- Client-Side Local Area Scan (F11)
-- Scans a detailed area around the player position
-- ============================================================================

function MapScanClient:StartClientLocalScan()
    local player = PlayerManager:GetLocalPlayer()
    if player == nil or player.soldier == nil then
        log:Warn('No local soldier for local scan')
        return
    end

    local pos = player.soldier.transform.trans
    local scanRadius = 50  -- 50m radius around player
    local spacing = 1.0    -- 1m grid for very high detail

    self.m_ClientScanQueue = {}
    self.m_ClientScanIdx = 1
    self.m_ClientHits = {}

    -- Build grid of scan points around player
    for x = pos.x - scanRadius, pos.x + scanRadius, spacing do
        for z = pos.z - scanRadius, pos.z + scanRadius, spacing do
            table.insert(self.m_ClientScanQueue, { x = x, z = z })
        end
    end

    self.m_ClientScanEnabled = true
    log:Info('Client local scan started: %d points in %.0fm radius', #self.m_ClientScanQueue, scanRadius)
end

-- ============================================================================
-- Engine Update
-- ============================================================================

function MapScanClient:OnUpdate(dt)
    -- Process client-side scan queue
    if self.m_ClientScanEnabled and #self.m_ClientScanQueue > 0 then
        local raysPerFrame = 20  -- keep it reasonable to avoid FPS drops
        local processed = 0

        while processed < raysPerFrame and self.m_ClientScanIdx <= #self.m_ClientScanQueue do
            local point = self.m_ClientScanQueue[self.m_ClientScanIdx]

            -- Cast detailed ray from high up straight down
            local from = Vec3(point.x, 500, point.z)
            local to = Vec3(point.x, -50, point.z)
            local flags = 4 + 16 + 32 -- DontCheckWater + DontCheckRagdoll + DontCheckCharacter

            local hits = RaycastManager:DetailedRaycast(from, to, 10, 0, flags)

            if hits ~= nil then
                for _, hit in ipairs(hits) do
                    if hit.position ~= nil and #self.m_ClientHits < self.m_MaxVisualizationHits * 4 then
                        table.insert(self.m_ClientHits, {
                            x = hit.position.x, y = hit.position.y, z = hit.position.z,
                            nx = hit.normal and hit.normal.x or 0,
                            ny = hit.normal and hit.normal.y or 0,
                            nz = hit.normal and hit.normal.z or 0,
                        })
                    end
                end
            end

            -- Also cast horizontal rays at this point for walls/interiors
            local scanY = from.y  -- will be dynamically set based on ground hit
            if hits and #hits > 0 and hits[1].position then
                scanY = hits[1].position.y + 1.5 -- eye height above ground
            end

            -- 8-direction horizontal scan for walls
            local wallDist = 30
            local dirs = {
                {1,0}, {-1,0}, {0,1}, {0,-1},
                {0.707,0.707}, {-0.707,0.707}, {0.707,-0.707}, {-0.707,-0.707}
            }

            for _, dir in ipairs(dirs) do
                local wallFrom = Vec3(point.x, scanY, point.z)
                local wallTo = Vec3(point.x + dir[1] * wallDist, scanY, point.z + dir[2] * wallDist)
                local wallHits = RaycastManager:DetailedRaycast(wallFrom, wallTo, 3, 0, flags)

                if wallHits ~= nil then
                    for _, wh in ipairs(wallHits) do
                        if wh.position ~= nil and #self.m_ClientHits < self.m_MaxVisualizationHits * 4 then
                            table.insert(self.m_ClientHits, {
                                x = wh.position.x, y = wh.position.y, z = wh.position.z,
                                nx = wh.normal and wh.normal.x or 0,
                                ny = wh.normal and wh.normal.y or 0,
                                nz = wh.normal and wh.normal.z or 0,
                            })
                        end
                    end
                end
            end

            self.m_ClientScanIdx = self.m_ClientScanIdx + 1
            processed = processed + 1
        end

        -- Check if done
        if self.m_ClientScanIdx > #self.m_ClientScanQueue then
            self.m_ClientScanEnabled = false
            log:Info('Client local scan complete: %d hit points collected', #self.m_ClientHits)
        end
    end
end

-- ============================================================================
-- Debug Visualization (UI:DrawHud)
-- ============================================================================

function MapScanClient:OnDrawHud(pass, delta)
    if not self.m_ShowDebug then
        return
    end

    -- Draw collected hit points as small debug crosses
    local player = PlayerManager:GetLocalPlayer()
    if player == nil or player.soldier == nil then
        return
    end

    local playerPos = player.soldier.transform.trans
    local viewRange = 100  -- only render points within 100m of player

    local rendered = 0
    local maxRender = 2000  -- limit to avoid FPS tank

    for _, hit in ipairs(self.m_ClientHits) do
        if rendered >= maxRender then break end

        local dx = hit.x - playerPos.x
        local dz = hit.z - playerPos.z
        local distSq = dx * dx + dz * dz

        if distSq < viewRange * viewRange then
            local hitPos = Vec3(hit.x, hit.y, hit.z)
            local normalEnd = Vec3(
                hit.x + hit.nx * 0.3,
                hit.y + hit.ny * 0.3,
                hit.z + hit.nz * 0.3
            )

            -- Color based on normal direction (green = flat ground, red = walls, blue = ceilings)
            local color
            if hit.ny > 0.7 then
                color = Vec4(0.2, 0.9, 0.2, 0.5)  -- green for ground
            elseif hit.ny < -0.7 then
                color = Vec4(0.2, 0.2, 0.9, 0.5)  -- blue for ceilings
            else
                color = Vec4(0.9, 0.5, 0.1, 0.5)  -- orange for walls
            end

            -- Draw small cross at hit point
            local size = 0.15
            DebugRenderer:DrawLine(
                Vec3(hit.x - size, hit.y, hit.z),
                Vec3(hit.x + size, hit.y, hit.z),
                color, color
            )
            DebugRenderer:DrawLine(
                Vec3(hit.x, hit.y - size, hit.z),
                Vec3(hit.x, hit.y + size, hit.z),
                color, color
            )
            DebugRenderer:DrawLine(
                Vec3(hit.x, hit.y, hit.z - size),
                Vec3(hit.x, hit.y, hit.z + size),
                color, color
            )

            -- Draw normal line
            DebugRenderer:DrawLine(hitPos, normalEnd, Vec4(1, 1, 0, 0.3), Vec4(1, 1, 0, 0.3))

            rendered = rendered + 1
        end
    end

    -- Draw scan progress text
    if self.m_ShowProgress and self.m_IsScanning then
        -- Note: VU doesn't have DebugRenderer:DrawText2D in all versions
        -- Progress is shown in console output instead
    end
end

return MapScanClient
