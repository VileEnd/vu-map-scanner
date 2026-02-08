-- MapScanner Data Exporter
-- Handles exporting scan data via HTTP POST or SQL local storage

local ScanConfig = require '__shared/ScanConfig'
local Logger = require '__shared/ScanLogger'
local log = Logger:New('DataExporter')

local DataExporter = {}
DataExporter.__index = DataExporter

function DataExporter:New()
    local instance = {
        pendingBatches = {},
        exportedChunks = 0,
        failedExports = 0,
        sqlInitialized = false,
    }
    setmetatable(instance, DataExporter)
    return instance
end

--- Initialize SQL storage (creates table if not exists)
function DataExporter:InitSQL()
    if self.sqlInitialized then return true end

    local ok = SQL:Open()
    if not ok then
        log:Error('Failed to open SQL database: %s', SQL:Error() or 'unknown')
        return false
    end

    -- Create tables for scan data
    local result = SQL:Query([[
        CREATE TABLE IF NOT EXISTS map_scans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            map_id TEXT NOT NULL,
            map_name TEXT NOT NULL,
            scan_preset TEXT NOT NULL,
            grid_spacing REAL NOT NULL,
            started_at TEXT NOT NULL,
            completed_at TEXT,
            total_hits INTEGER DEFAULT 0,
            status TEXT DEFAULT 'scanning'
        )
    ]])
    if result == nil then
        log:Error('Failed to create map_scans table: %s', SQL:Error() or 'unknown')
        return false
    end

    result = SQL:Query([[
        CREATE TABLE IF NOT EXISTS scan_chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scan_id INTEGER NOT NULL,
            chunk_index INTEGER NOT NULL,
            data_json TEXT NOT NULL,
            vertex_count INTEGER DEFAULT 0,
            index_count INTEGER DEFAULT 0,
            FOREIGN KEY (scan_id) REFERENCES map_scans(id)
        )
    ]])
    if result == nil then
        log:Error('Failed to create scan_chunks table: %s', SQL:Error() or 'unknown')
        return false
    end

    result = SQL:Query([[
        CREATE TABLE IF NOT EXISTS scan_heightmaps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scan_id INTEGER NOT NULL,
            data_json TEXT NOT NULL,
            FOREIGN KEY (scan_id) REFERENCES map_scans(id)
        )
    ]])
    if result == nil then
        log:Error('Failed to create scan_heightmaps table: %s', SQL:Error() or 'unknown')
        return false
    end

    self.sqlInitialized = true
    log:Info('SQL storage initialized')
    return true
end

--- Start a new scan record in SQL
--- @return number|nil scanId
function DataExporter:StartScanRecord(mapId, mapName, gridSpacing)
    if not self:InitSQL() then return nil end

    local result = SQL:Query(
        'INSERT INTO map_scans (map_id, map_name, scan_preset, grid_spacing, started_at) VALUES (?, ?, ?, ?, datetime("now"))',
        SQL:Escape(mapId),
        SQL:Escape(mapName),
        SQL:Escape(ScanConfig.activePreset),
        gridSpacing
    )

    if result == nil then
        log:Error('Failed to create scan record: %s', SQL:Error() or 'unknown')
        return nil
    end

    -- Get the last inserted ID
    local idResult = SQL:Query('SELECT last_insert_rowid() as id')
    if idResult and #idResult > 0 then
        local scanId = idResult[1]['id']
        log:Info('Created scan record #%d for %s', scanId, mapId)
        return scanId
    end

    return nil
end

--- Save a chunk to SQL
function DataExporter:SaveChunkSQL(scanId, chunkIndex, jsonData, vertexCount, indexCount)
    if not self.sqlInitialized then
        log:Error('SQL not initialized')
        return false
    end

    local result = SQL:Query(
        'INSERT INTO scan_chunks (scan_id, chunk_index, data_json, vertex_count, index_count) VALUES (?, ?, ?, ?, ?)',
        scanId,
        chunkIndex,
        SQL:Escape(jsonData),
        vertexCount,
        indexCount
    )

    if result == nil then
        log:Error('Failed to save chunk %d: %s', chunkIndex, SQL:Error() or 'unknown')
        return false
    end

    self.exportedChunks = self.exportedChunks + 1
    return true
end

--- Save heightmap to SQL
function DataExporter:SaveHeightmapSQL(scanId, jsonData)
    if not self.sqlInitialized then
        log:Error('SQL not initialized')
        return false
    end

    local result = SQL:Query(
        'INSERT INTO scan_heightmaps (scan_id, data_json) VALUES (?, ?)',
        scanId,
        SQL:Escape(jsonData)
    )

    if result == nil then
        log:Error('Failed to save heightmap: %s', SQL:Error() or 'unknown')
        return false
    end

    return true
end

--- Complete a scan record
function DataExporter:CompleteScanRecord(scanId, totalHits)
    if not self.sqlInitialized then return false end

    SQL:Query(
        'UPDATE map_scans SET completed_at = datetime("now"), total_hits = ?, status = "completed" WHERE id = ?',
        totalHits,
        scanId
    )

    log:Info('Scan #%d marked complete with %d total hits', scanId, totalHits)
    return true
end

--- Export chunk via HTTP POST
function DataExporter:ExportChunkHTTP(jsonData, chunkIndex, callback)
    local url = ScanConfig.exportUrl .. '/chunk'
    local opts = HttpOptions({}, ScanConfig.httpTimeout)
    opts:SetHeader('Content-Type', 'application/json')
    opts.verifyCertificate = ScanConfig.tlsVerify

    if ScanConfig.ingestToken ~= '' then
        opts:SetHeader('Authorization', 'Bearer ' .. ScanConfig.ingestToken)
    end

    Net:PostHTTPAsync(url, jsonData, opts, function(response)
        if response and response.status >= 200 and response.status < 300 then
            self.exportedChunks = self.exportedChunks + 1
            log:Debug('Exported chunk %d (HTTP %d)', chunkIndex, response.status)
            if callback then callback(true) end
        else
            self.failedExports = self.failedExports + 1
            local status = response and response.status or 0
            log:Error('Failed to export chunk %d (HTTP %d)', chunkIndex, status)
            if callback then callback(false) end
        end
    end)
end

--- Export heightmap via HTTP POST
function DataExporter:ExportHeightmapHTTP(jsonData, callback)
    local url = ScanConfig.exportUrl .. '/heightmap'
    local opts = HttpOptions({}, ScanConfig.httpTimeout)
    opts:SetHeader('Content-Type', 'application/json')
    opts.verifyCertificate = ScanConfig.tlsVerify

    if ScanConfig.ingestToken ~= '' then
        opts:SetHeader('Authorization', 'Bearer ' .. ScanConfig.ingestToken)
    end

    Net:PostHTTPAsync(url, jsonData, opts, function(response)
        if response and response.status >= 200 and response.status < 300 then
            log:Info('Heightmap exported successfully (HTTP %d)', response.status)
            if callback then callback(true) end
        else
            local status = response and response.status or 0
            log:Error('Failed to export heightmap (HTTP %d)', status)
            if callback then callback(false) end
        end
    end)
end

--- Get export statistics
function DataExporter:GetStats()
    return {
        exportedChunks = self.exportedChunks,
        failedExports = self.failedExports,
    }
end

--- Close SQL connection
function DataExporter:Close()
    if self.sqlInitialized then
        SQL:Close()
        self.sqlInitialized = false
    end
end

--- Query stored scan data (for RCON retrieval)
function DataExporter:GetStoredScans()
    if not self:InitSQL() then return {} end

    local result = SQL:Query('SELECT * FROM map_scans ORDER BY id DESC LIMIT 20')
    return result or {}
end

--- Retrieve stored heightmap JSON by scan ID
function DataExporter:GetStoredHeightmap(scanId)
    if not self:InitSQL() then return nil end

    local result = SQL:Query('SELECT data_json FROM scan_heightmaps WHERE scan_id = ? LIMIT 1', scanId)
    if result and #result > 0 then
        return result[1]['data_json']
    end
    return nil
end

--- Retrieve stored chunks for a scan
function DataExporter:GetStoredChunks(scanId)
    if not self:InitSQL() then return {} end

    local result = SQL:Query('SELECT chunk_index, data_json FROM scan_chunks WHERE scan_id = ? ORDER BY chunk_index', scanId)
    return result or {}
end

return DataExporter
