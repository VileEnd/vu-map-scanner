-- MapScanner RCON HTTP Bridge
-- Exposes stored scan data via RCON commands so external tools can retrieve it
-- Also provides a simple way to dump data as NDJSON lines for file-based export

local ScanConfig = require '__shared/ScanConfig'
local Logger = require '__shared/ScanLogger'
local DataExporter = require '__shared/DataExporter'

local log = Logger:New('RCONBridge')

class 'RCONBridge'

function RCONBridge:__init()
    log:Info('RCONBridge initializing...')

    self.m_Exporter = DataExporter:New()

    -- RCON commands for data retrieval
    self.m_FetchHeightmap = RCON:RegisterCommand('mapscan.fetch.heightmap', RemoteCommandFlag.RequiresLogin, self, self.OnFetchHeightmap)
    self.m_FetchChunk = RCON:RegisterCommand('mapscan.fetch.chunk', RemoteCommandFlag.RequiresLogin, self, self.OnFetchChunk)
    self.m_FetchMeta = RCON:RegisterCommand('mapscan.fetch.meta', RemoteCommandFlag.RequiresLogin, self, self.OnFetchMeta)
    self.m_HttpPush = RCON:RegisterCommand('mapscan.push', RemoteCommandFlag.RequiresLogin, self, self.OnHttpPush)
    self.m_SetConfig = RCON:RegisterCommand('mapscan.config', RemoteCommandFlag.RequiresLogin, self, self.OnConfig)

    log:Info('RCONBridge initialized')
end

--- Fetch heightmap JSON for a scan
function RCONBridge:OnFetchHeightmap(command, args, loggedIn)
    if not args or #args < 1 then
        return { 'ERR', 'Usage: mapscan.fetch.heightmap <scanId>' }
    end

    local scanId = tonumber(args[1])
    if not scanId then
        return { 'ERR', 'Invalid scan ID' }
    end

    local data = self.m_Exporter:GetStoredHeightmap(scanId)
    if data then
        -- Return data in chunks (RCON has message size limits)
        -- Split into 4KB chunks
        local chunkSize = 4000
        local results = { 'OK', 'HEIGHTMAP_BEGIN' }
        for i = 1, #data, chunkSize do
            table.insert(results, data:sub(i, i + chunkSize - 1))
        end
        table.insert(results, 'HEIGHTMAP_END')
        return results
    else
        return { 'ERR', 'No heightmap found for scan #' .. scanId }
    end
end

--- Fetch a specific mesh chunk
function RCONBridge:OnFetchChunk(command, args, loggedIn)
    if not args or #args < 2 then
        return { 'ERR', 'Usage: mapscan.fetch.chunk <scanId> <chunkIndex>' }
    end

    local scanId = tonumber(args[1])
    local chunkIdx = tonumber(args[2])
    if not scanId or not chunkIdx then
        return { 'ERR', 'Invalid parameters' }
    end

    local chunks = self.m_Exporter:GetStoredChunks(scanId)
    for _, chunk in ipairs(chunks) do
        if chunk['chunk_index'] == chunkIdx then
            local data = chunk['data_json']
            local chunkSize = 4000
            local results = { 'OK', 'CHUNK_BEGIN' }
            for i = 1, #data, chunkSize do
                table.insert(results, data:sub(i, i + chunkSize - 1))
            end
            table.insert(results, 'CHUNK_END')
            return results
        end
    end

    return { 'ERR', 'Chunk not found' }
end

--- Fetch scan metadata
function RCONBridge:OnFetchMeta(command, args, loggedIn)
    local scans = self.m_Exporter:GetStoredScans()
    local results = { 'OK' }

    for _, scan in ipairs(scans) do
        -- Count chunks for this scan
        local chunks = self.m_Exporter:GetStoredChunks(scan['id'])
        table.insert(results, string.format(
            '{"id":%d,"mapId":"%s","mapName":"%s","preset":"%s","spacing":%.1f,"hits":%d,"chunks":%d,"status":"%s","started":"%s","completed":"%s"}',
            scan['id'],
            scan['map_id'] or '',
            scan['map_name'] or '',
            scan['scan_preset'] or '',
            scan['grid_spacing'] or 0,
            scan['total_hits'] or 0,
            #chunks,
            scan['status'] or '',
            scan['started_at'] or '',
            scan['completed_at'] or ''
        ))
    end

    return results
end

--- Push stored scan data to an HTTP endpoint
function RCONBridge:OnHttpPush(command, args, loggedIn)
    if not args or #args < 2 then
        return { 'ERR', 'Usage: mapscan.push <scanId> <url>' }
    end

    local scanId = tonumber(args[1])
    local url = args[2]

    if not scanId then
        return { 'ERR', 'Invalid scan ID' }
    end

    -- Push heightmap
    local heightmap = self.m_Exporter:GetStoredHeightmap(scanId)
    if heightmap then
        local opts = HttpOptions({}, 60)
        opts:SetHeader('Content-Type', 'application/json')
        opts.verifyCertificate = ScanConfig.tlsVerify

        Net:PostHTTPAsync(url .. '/heightmap', heightmap, opts, function(response)
            if response and response.status >= 200 and response.status < 300 then
                log:Info('Heightmap pushed to %s (HTTP %d)', url, response.status)
            else
                log:Error('Failed to push heightmap (HTTP %d)', response and response.status or 0)
            end
        end)
    end

    -- Push chunks
    local chunks = self.m_Exporter:GetStoredChunks(scanId)
    for _, chunk in ipairs(chunks) do
        local opts = HttpOptions({}, 60)
        opts:SetHeader('Content-Type', 'application/json')
        opts.verifyCertificate = ScanConfig.tlsVerify

        Net:PostHTTPAsync(url .. '/chunk', chunk['data_json'], opts, function(response)
            if response and response.status >= 200 and response.status < 300 then
                log:Debug('Chunk %d pushed', chunk['chunk_index'])
            else
                log:Error('Failed to push chunk %d', chunk['chunk_index'])
            end
        end)
    end

    return { 'OK', string.format('Pushing scan #%d (%d chunks) to %s', scanId, #chunks, url) }
end

--- Configure scanning parameters via RCON
function RCONBridge:OnConfig(command, args, loggedIn)
    if not args or #args < 1 then
        return {
            'OK',
            'Current configuration:',
            '  preset: ' .. ScanConfig.activePreset,
            '  exportUrl: ' .. ScanConfig.exportUrl,
            '  useHttpExport: ' .. tostring(ScanConfig.useHttpExport),
            '  debugLogging: ' .. tostring(ScanConfig.debugLogging),
            '',
            'Usage: mapscan.config <key> <value>',
            'Keys: preset, exportUrl, useHttp, debug, tlsVerify, token',
        }
    end

    local key = args[1]
    local value = args[2]

    if key == 'preset' and value then
        if ScanConfig.Presets[value] then
            ScanConfig.activePreset = value
            return { 'OK', 'Preset set to: ' .. value }
        else
            return { 'ERR', 'Unknown preset: ' .. value }
        end
    elseif key == 'exportUrl' and value then
        ScanConfig.exportUrl = value
        return { 'OK', 'Export URL set to: ' .. value }
    elseif key == 'useHttp' and value then
        ScanConfig.useHttpExport = (value == 'true' or value == '1')
        return { 'OK', 'HTTP export: ' .. tostring(ScanConfig.useHttpExport) }
    elseif key == 'debug' and value then
        ScanConfig.debugLogging = (value == 'true' or value == '1')
        return { 'OK', 'Debug logging: ' .. tostring(ScanConfig.debugLogging) }
    elseif key == 'tlsVerify' and value then
        ScanConfig.tlsVerify = (value == 'true' or value == '1')
        return { 'OK', 'TLS verify: ' .. tostring(ScanConfig.tlsVerify) }
    elseif key == 'token' and value then
        ScanConfig.ingestToken = value
        return { 'OK', 'Ingest token updated' }
    end

    return { 'ERR', 'Unknown config key: ' .. key }
end

return RCONBridge
