-- MapScanner Shared Mesh Builder
-- Converts raw raycast hit points into an optimized triangle mesh
-- Outputs glTF 2.0 compatible vertex/index data as JSON

local Logger = require '__shared/ScanLogger'
local log = Logger:New('MeshBuilder')

local MeshBuilder = {}
MeshBuilder.__index = MeshBuilder

function MeshBuilder:New()
    local instance = {
        -- Raw heightmap data: [gridX][gridZ] = { hits = { {x,y,z,nx,ny,nz}, ... } }
        grid = {},
        gridMinX = math.huge,
        gridMaxX = -math.huge,
        gridMinZ = math.huge,
        gridMaxZ = -math.huge,
        spacing = 1.0,
        totalHits = 0,
        droppedHits = 0,  -- hits discarded due to per-cell cap
        freedHits = 0,    -- hits freed after chunk export (streaming mode)
        cumulativeCells = 0,      -- total unique cells with hits (survives chunk flush)
        cumulativeMultiLayer = 0, -- total multi-layer cells (survives chunk flush)
        peakMaxLayers = 0,        -- maximum layers seen in any cell ever
        mapId = '',
        mapName = '',
        -- Per-cell hit cap to prevent unbounded memory growth
        -- 32-bit process has ~2GB limit; each hit ≈ 150 bytes in Lua tables
        maxHitsPerCell = 20,
        -- Lightweight heightmap (min Y per cell) — survives chunk flushing
        heightGrid = {},  -- [gx][gz] = minY
    }
    setmetatable(instance, MeshBuilder)
    return instance
end

--- Initialize with map parameters
function MeshBuilder:Init(mapId, mapName, spacing)
    self.mapId = mapId
    self.mapName = mapName
    self.spacing = spacing
    self.grid = {}
    self.heightGrid = {}
    self.gridMinX = math.huge
    self.gridMaxX = -math.huge
    self.gridMinZ = math.huge
    self.gridMaxZ = -math.huge
    self.totalHits = 0
    self.droppedHits = 0
    self.freedHits = 0
    self.cumulativeCells = 0
    self.cumulativeMultiLayer = 0
    self.peakMaxLayers = 0
    log:Info('MeshBuilder initialized for %s (%s) with spacing %.1fm (max %d hits/cell)',
        mapId, mapName, spacing, self.maxHitsPerCell)
end

--- Quantize a world coordinate to grid index
function MeshBuilder:WorldToGrid(worldX, worldZ)
    local gx = math.floor(worldX / self.spacing + 0.5)
    local gz = math.floor(worldZ / self.spacing + 0.5)
    return gx, gz
end

--- Add a raycast hit point
--- @param x number world X
--- @param y number world Y (height)
--- @param z number world Z
--- @param nx number normal X
--- @param ny number normal Y
--- @param nz number normal Z
--- @param matIdx number|nil physics material index (-1 if unavailable)
function MeshBuilder:AddHit(x, y, z, nx, ny, nz, matIdx)
    local gx, gz = self:WorldToGrid(x, z)

    if not self.grid[gx] then
        self.grid[gx] = {}
    end
    if not self.grid[gx][gz] then
        self.grid[gx][gz] = { hits = {} }
    end

    -- Enforce per-cell hit cap to bound memory usage
    if #self.grid[gx][gz].hits >= self.maxHitsPerCell then
        self.droppedHits = self.droppedHits + 1
        -- Still update heightmap even for dropped hits
        if not self.heightGrid[gx] then self.heightGrid[gx] = {} end
        local prevY = self.heightGrid[gx][gz]
        if prevY == nil or y < prevY then
            self.heightGrid[gx][gz] = y
        end
        return
    end

    -- Deduplicate: skip if a hit already exists at nearly the same Y in this cell.
    -- Interior horizontal rays often re-hit the same floor/ceiling surface that
    -- the top-down pass already captured. Epsilon = half the grid spacing.
    local dedupEps = self.spacing * 0.5
    local existingHits = self.grid[gx][gz].hits
    for i = 1, #existingHits do
        if math.abs(existingHits[i].y - y) < dedupEps then
            -- Already have a hit at this height — skip
            -- Still update heightmap
            if not self.heightGrid[gx] then self.heightGrid[gx] = {} end
            local prevY2 = self.heightGrid[gx][gz]
            if prevY2 == nil or y < prevY2 then
                self.heightGrid[gx][gz] = y
            end
            return
        end
    end

    -- Store the hit (multiple hits per cell = multi-layer for interiors)
    table.insert(self.grid[gx][gz].hits, {
        x = x, y = y, z = z,
        nx = nx or 0, ny = ny or 1, nz = nz or 0,
        mat = matIdx or -1
    })

    self.totalHits = self.totalHits + 1

    -- Track cumulative cell stats (these survive streaming chunk flushes)
    local hitCount = #self.grid[gx][gz].hits
    if hitCount == 1 then
        self.cumulativeCells = self.cumulativeCells + 1
    elseif hitCount == 2 then
        self.cumulativeMultiLayer = self.cumulativeMultiLayer + 1
    end
    if hitCount > self.peakMaxLayers then
        self.peakMaxLayers = hitCount
    end

    -- Maintain lightweight heightmap (min Y = ground)
    if not self.heightGrid[gx] then self.heightGrid[gx] = {} end
    local prevY = self.heightGrid[gx][gz]
    if prevY == nil or y < prevY then
        self.heightGrid[gx][gz] = y
    end

    -- Track grid bounds
    if gx < self.gridMinX then self.gridMinX = gx end
    if gx > self.gridMaxX then self.gridMaxX = gx end
    if gz < self.gridMinZ then self.gridMinZ = gz end
    if gz > self.gridMaxZ then self.gridMaxZ = gz end
end

--- Build a chunk of vertex/index data for export
--- Generates triangle strips connecting adjacent grid cells
--- @param chunkStartGX number grid X start
--- @param chunkStartGZ number grid Z start
--- @param chunkSize number grid cells per chunk side
--- @return table { vertices = {}, indices = {}, vertexCount, indexCount }
function MeshBuilder:BuildChunk(chunkStartGX, chunkStartGZ, chunkSize)
    local vertices = {}  -- flat array: x,y,z, nx,ny,nz, mat per vertex
    local indices = {}   -- triangle indices (0-based)
    local vertexMap = {} -- gridKey -> vertexIndex

    local vertIdx = 0

    -- First pass: collect vertices for this chunk
    for gx = chunkStartGX, chunkStartGX + chunkSize - 1 do
        for gz = chunkStartGZ, chunkStartGZ + chunkSize - 1 do
            if self.grid[gx] and self.grid[gx][gz] then
                local cell = self.grid[gx][gz]
                -- For each layer/hit in this cell
                for layerIdx, hit in ipairs(cell.hits) do
                    local key = gx .. '_' .. gz .. '_' .. layerIdx
                    vertexMap[key] = vertIdx

                    -- Add vertex: position + normal + material index
                    table.insert(vertices, hit.x)
                    table.insert(vertices, hit.y)
                    table.insert(vertices, hit.z)
                    table.insert(vertices, hit.nx)
                    table.insert(vertices, hit.ny)
                    table.insert(vertices, hit.nz)
                    table.insert(vertices, hit.mat or -1)

                    vertIdx = vertIdx + 1
                end
            end
        end
    end

    -- Second pass: build triangles connecting adjacent ground-layer vertices
    -- For the primary (lowest) hit in each cell, create quads (2 triangles) with neighbors
    for gx = chunkStartGX, chunkStartGX + chunkSize - 2 do
        for gz = chunkStartGZ, chunkStartGZ + chunkSize - 2 do
            local k00 = gx .. '_' .. gz .. '_1'
            local k10 = (gx + 1) .. '_' .. gz .. '_1'
            local k01 = gx .. '_' .. (gz + 1) .. '_1'
            local k11 = (gx + 1) .. '_' .. (gz + 1) .. '_1'

            local v00 = vertexMap[k00]
            local v10 = vertexMap[k10]
            local v01 = vertexMap[k01]
            local v11 = vertexMap[k11]

            -- Only create triangles where all 4 corners exist
            if v00 and v10 and v01 and v11 then
                -- Triangle 1: v00, v10, v01
                table.insert(indices, v00)
                table.insert(indices, v10)
                table.insert(indices, v01)
                -- Triangle 2: v10, v11, v01
                table.insert(indices, v10)
                table.insert(indices, v11)
                table.insert(indices, v01)
            -- Partial quads with 3 vertices: single triangle
            elseif v00 and v10 and v01 then
                table.insert(indices, v00)
                table.insert(indices, v10)
                table.insert(indices, v01)
            elseif v00 and v10 and v11 then
                table.insert(indices, v00)
                table.insert(indices, v10)
                table.insert(indices, v11)
            elseif v00 and v01 and v11 then
                table.insert(indices, v00)
                table.insert(indices, v01)
                table.insert(indices, v11)
            elseif v10 and v01 and v11 then
                table.insert(indices, v10)
                table.insert(indices, v01)
                table.insert(indices, v11)
            end

            -- Connect interior layers vertically where they exist
            -- This creates "walls" between floor and ceiling hits
            local maxLayers = 0
            if self.grid[gx] and self.grid[gx][gz] then
                maxLayers = #self.grid[gx][gz].hits
            end
            for layer = 1, maxLayers - 1 do
                local kCurr = gx .. '_' .. gz .. '_' .. layer
                local kNext = gx .. '_' .. gz .. '_' .. (layer + 1)
                local kRight = (gx + 1) .. '_' .. gz .. '_' .. layer
                local kRightNext = (gx + 1) .. '_' .. gz .. '_' .. (layer + 1)

                local vc = vertexMap[kCurr]
                local vn = vertexMap[kNext]
                local vr = vertexMap[kRight]
                local vrn = vertexMap[kRightNext]

                -- Vertical face between layers at same column
                if vc and vn and vr and vrn then
                    table.insert(indices, vc)
                    table.insert(indices, vn)
                    table.insert(indices, vr)
                    table.insert(indices, vn)
                    table.insert(indices, vrn)
                    table.insert(indices, vr)
                end
            end
        end
    end

    return {
        vertices = vertices,
        indices = indices,
        vertexCount = vertIdx,
        indexCount = #indices
    }
end

--- Get all chunks as a list of chunk descriptors for iteration
--- @param chunkSize number grid cells per chunk side (default 64)
--- @return table list of { startGX, startGZ, chunkSize }
function MeshBuilder:GetChunks(chunkSize)
    chunkSize = chunkSize or 64
    local chunks = {}

    if self.gridMinX > self.gridMaxX then
        return chunks
    end

    for gx = self.gridMinX, self.gridMaxX, chunkSize do
        for gz = self.gridMinZ, self.gridMaxZ, chunkSize do
            table.insert(chunks, {
                startGX = gx,
                startGZ = gz,
                chunkSize = chunkSize
            })
        end
    end

    log:Info('Generated %d chunks (chunk size %d)', #chunks, chunkSize)
    return chunks
end

--- Build a simple heightmap-only export (for lightweight 2D maps)
--- Uses the compact heightGrid (min Y per cell) which is maintained
--- independently of the full grid data and survives chunk flushing
--- @return table { gridSpacing, originX, originZ, gridW, gridH, heights = {row={...}} }
function MeshBuilder:BuildHeightmap()
    if self.gridMinX > self.gridMaxX then
        return nil
    end

    local gridW = self.gridMaxX - self.gridMinX + 1
    local gridH = self.gridMaxZ - self.gridMinZ + 1
    local heights = {}

    for gz = self.gridMinZ, self.gridMaxZ do
        local row = {}
        for gx = self.gridMinX, self.gridMaxX do
            local y = self.heightGrid[gx] and self.heightGrid[gx][gz]
            if y ~= nil then
                table.insert(row, math.floor(y * 100 + 0.5) / 100)
            else
                table.insert(row, -9999)
            end
        end
        table.insert(heights, row)
    end

    return {
        mapId = self.mapId,
        mapName = self.mapName,
        gridSpacing = self.spacing,
        originX = self.gridMinX * self.spacing,
        originZ = self.gridMinZ * self.spacing,
        gridW = gridW,
        gridH = gridH,
        heights = heights,
    }
end

--- Serialize a chunk to JSON string
--- Vertex stride is 7: x, y, z, nx, ny, nz, materialIndex
--- @param chunkData table from BuildChunk
--- @param chunkIndex number
--- @return string JSON
function MeshBuilder:ChunkToJSON(chunkData, chunkIndex)
    local parts = {}
    table.insert(parts, '{')
    table.insert(parts, '"mapId":"' .. self.mapId .. '",')
    table.insert(parts, '"mapName":"' .. self.mapName .. '",')
    table.insert(parts, '"chunkIndex":' .. chunkIndex .. ',')
    table.insert(parts, '"gridSpacing":' .. self.spacing .. ',')
    table.insert(parts, '"vertexStride":7,')
    table.insert(parts, '"vertexCount":' .. chunkData.vertexCount .. ',')
    table.insert(parts, '"indexCount":' .. chunkData.indexCount .. ',')

    -- Vertices as flat array
    table.insert(parts, '"vertices":[')
    for i, v in ipairs(chunkData.vertices) do
        if i > 1 then table.insert(parts, ',') end
        table.insert(parts, tostring(math.floor(v * 1000 + 0.5) / 1000))
    end
    table.insert(parts, '],')

    -- Indices as flat array
    table.insert(parts, '"indices":[')
    for i, idx in ipairs(chunkData.indices) do
        if i > 1 then table.insert(parts, ',') end
        table.insert(parts, tostring(idx))
    end
    table.insert(parts, ']')

    table.insert(parts, '}')
    return table.concat(parts)
end

--- Serialize heightmap to JSON string
function MeshBuilder:HeightmapToJSON()
    local hm = self:BuildHeightmap()
    if hm == nil then
        return '{}'
    end

    local parts = {}
    table.insert(parts, '{')
    table.insert(parts, '"type":"heightmap",')
    table.insert(parts, '"mapId":"' .. hm.mapId .. '",')
    table.insert(parts, '"mapName":"' .. hm.mapName .. '",')
    table.insert(parts, '"gridSpacing":' .. hm.gridSpacing .. ',')
    table.insert(parts, '"originX":' .. hm.originX .. ',')
    table.insert(parts, '"originZ":' .. hm.originZ .. ',')
    table.insert(parts, '"gridW":' .. hm.gridW .. ',')
    table.insert(parts, '"gridH":' .. hm.gridH .. ',')
    table.insert(parts, '"heights":[')

    for rIdx, row in ipairs(hm.heights) do
        if rIdx > 1 then table.insert(parts, ',') end
        table.insert(parts, '[')
        for cIdx, val in ipairs(row) do
            if cIdx > 1 then table.insert(parts, ',') end
            table.insert(parts, tostring(val))
        end
        table.insert(parts, ']')
    end

    table.insert(parts, ']')
    table.insert(parts, '}')
    return table.concat(parts)
end

--- Get statistics about collected data
function MeshBuilder:GetStats()
    local cellCount = 0
    local multiLayerCells = 0
    local maxLayers = 0

    for gx, col in pairs(self.grid) do
        for gz, cell in pairs(col) do
            cellCount = cellCount + 1
            local layers = #cell.hits
            if layers > 1 then
                multiLayerCells = multiLayerCells + 1
            end
            if layers > maxLayers then
                maxLayers = layers
            end
        end
    end

    -- Rough memory estimate: ~150 bytes per hit in Lua tables
    -- In streaming mode, freed hits are no longer in memory
    local activeHits = self.totalHits - self.freedHits
    local estMemoryMB = (activeHits * 150) / (1024 * 1024)

    return {
        totalHits = self.totalHits,
        droppedHits = self.droppedHits,
        freedHits = self.freedHits,
        activeHits = activeHits,
        cellCount = cellCount,
        multiLayerCells = multiLayerCells,
        maxLayers = maxLayers,
        cumulativeCells = self.cumulativeCells,
        cumulativeMultiLayer = self.cumulativeMultiLayer,
        peakMaxLayers = self.peakMaxLayers,
        gridRangeX = { self.gridMinX, self.gridMaxX },
        gridRangeZ = { self.gridMinZ, self.gridMaxZ },
        estMemoryMB = math.floor(estMemoryMB * 10 + 0.5) / 10,
    }
end

--- Free grid data for a specific chunk region after it has been exported
--- This allows incremental memory reclamation during export
--- The heightGrid is NOT freed (it's compact and needed for final export)
--- @param chunkStartGX number grid X start
--- @param chunkStartGZ number grid Z start
--- @param chunkSize number grid cells per chunk side
--- @return number hitsFreed count of hits removed from memory
function MeshBuilder:FreeChunkData(chunkStartGX, chunkStartGZ, chunkSize)
    local hitsFreed = 0

    for gx = chunkStartGX, chunkStartGX + chunkSize - 1 do
        if self.grid[gx] then
            for gz = chunkStartGZ, chunkStartGZ + chunkSize - 1 do
                if self.grid[gx][gz] then
                    hitsFreed = hitsFreed + #self.grid[gx][gz].hits
                    self.grid[gx][gz] = nil
                end
            end
            -- If column is now empty, remove it entirely
            if next(self.grid[gx]) == nil then
                self.grid[gx] = nil
            end
        end
    end

    self.freedHits = self.freedHits + hitsFreed
    return hitsFreed
end

return MeshBuilder
