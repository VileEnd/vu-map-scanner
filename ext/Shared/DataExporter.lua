-- MapScanner Data Exporter — S3 Direct Upload
-- Uploads scan chunks and heightmap JSON to S3 using AWS Signature V4
-- Follows the positionTracking mod's TelemetryS3Uploader pattern

local ScanConfig = require '__shared/ScanConfig'
local S3Signer = require '__shared/S3Signer'
local Logger = require '__shared/ScanLogger'
local log = Logger:New('DataExporter')

local DataExporter = {}
DataExporter.__index = DataExporter

function DataExporter:New()
    local instance = {
        exportedChunks = 0,
        failedExports = 0,
        pendingUploads = 0,
        enabled = false,
    }
    setmetatable(instance, DataExporter)

    -- Validate S3 config
    if ScanConfig.s3AccessKey == '' or ScanConfig.s3SecretKey == '' or ScanConfig.s3Bucket == '' then
        log:Error('S3 configuration incomplete — set s3AccessKey, s3SecretKey, and s3Bucket in ScanConfig')
    else
        instance.enabled = true
        log:Info('S3 exporter ready (bucket: %s, endpoint: %s)', ScanConfig.s3Bucket, ScanConfig.s3Endpoint)
    end

    return instance
end

--- Build the S3 URL for a given object key
--- @param objectKey string
--- @return string
function DataExporter:BuildUrl(objectKey)
    if ScanConfig.s3PathStyle then
        if ScanConfig.s3Endpoint ~= '' then
            return 'https://' .. ScanConfig.s3Endpoint .. '/' .. ScanConfig.s3Bucket .. '/' .. objectKey
        else
            return 'https://s3.' .. ScanConfig.s3Region .. '.amazonaws.com/' .. ScanConfig.s3Bucket .. '/' .. objectKey
        end
    else
        if ScanConfig.s3Endpoint ~= '' then
            return 'https://' .. ScanConfig.s3Bucket .. '.' .. ScanConfig.s3Endpoint .. '/' .. objectKey
        else
            return 'https://' .. ScanConfig.s3Bucket .. '.s3.' .. ScanConfig.s3Region .. '.amazonaws.com/' .. objectKey
        end
    end
end

--- Generate the S3 object key prefix for a scan
--- Format: mapscans/<mapId>/<preset>/
--- @param mapId string
--- @return string
function DataExporter:BuildKeyPrefix(mapId)
    local safeMapId = ScanConfig.SanitizeKey(mapId)
    local safePreset = ScanConfig.SanitizeKey(ScanConfig.activePreset)
    return ScanConfig.s3Prefix .. '/' .. safeMapId .. '/' .. safePreset .. '/'
end

--- Upload a JSON payload to S3
--- @param objectKey string - full S3 object key
--- @param jsonPayload string - JSON content
--- @param label string - human-readable label for logging
--- @param callback function|nil - callback(success)
function DataExporter:UploadToS3(objectKey, jsonPayload, label, callback)
    if not self.enabled then
        log:Error('S3 exporter not enabled — skipping upload of %s', label)
        if callback then callback(false) end
        return
    end

    local url = self:BuildUrl(objectKey)
    local contentType = 'application/json'

    -- Sign the request
    local headers, debugInfo = S3Signer.SignPutRequest(
        ScanConfig.s3AccessKey,
        ScanConfig.s3SecretKey,
        ScanConfig.s3Region,
        ScanConfig.s3Bucket,
        objectKey,
        contentType,
        jsonPayload,
        ScanConfig.s3Endpoint,
        ScanConfig.s3PathStyle
    )

    local httpOptions = HttpOptions(headers, ScanConfig.s3Timeout)

    if ScanConfig.debugLogging then
        log:Debug('S3 PUT %s (%d bytes) — %s', url, #jsonPayload, label)
        if debugInfo then
            log:Debug('  Host: %s | CanonicalUri: %s', debugInfo.host, debugInfo.canonicalUri)
        end
    end

    self.pendingUploads = self.pendingUploads + 1

    local exporter = self
    Net:PutHTTPAsync(url, jsonPayload, httpOptions, function(response)
        exporter.pendingUploads = exporter.pendingUploads - 1

        if response and response.status >= 200 and response.status < 300 then
            exporter.exportedChunks = exporter.exportedChunks + 1
            log:Info('S3 upload OK: %s (HTTP %d)', label, response.status)
            if callback then callback(true) end
        else
            exporter.failedExports = exporter.failedExports + 1
            local status = response and response.status or 0
            local body = ''
            if response and response.body then
                body = tostring(response.body)
                if #body > 300 then body = body:sub(1, 300) .. '...' end
            end
            log:Error('S3 upload FAILED: %s (HTTP %d)', label, status)
            if body ~= '' then
                log:Error('  Response: %s', body)
            end
            if debugInfo then
                log:Error('  Host: %s | CanonicalUri: %s', debugInfo.host or '', debugInfo.canonicalUri or '')
            end
            if callback then callback(false) end
        end
    end)
end

--- Export a heightmap JSON to S3
--- @param mapId string
--- @param heightmapJSON string
--- @param callback function|nil
function DataExporter:ExportHeightmap(mapId, heightmapJSON, callback)
    local prefix = self:BuildKeyPrefix(mapId)
    local objectKey = prefix .. 'heightmap.json'
    self:UploadToS3(objectKey, heightmapJSON, 'heightmap/' .. mapId, callback)
end

--- Export a mesh chunk JSON to S3
--- @param mapId string
--- @param chunkIndex number
--- @param chunkJSON string
--- @param callback function|nil
function DataExporter:ExportChunk(mapId, chunkIndex, chunkJSON, callback)
    local prefix = self:BuildKeyPrefix(mapId)
    local objectKey = string.format('%schunk_%03d.json', prefix, chunkIndex)
    local label = string.format('chunk_%03d/%s', chunkIndex, mapId)
    self:UploadToS3(objectKey, chunkJSON, label, callback)
end

--- Export a manifest/metadata JSON to S3
--- @param mapId string
--- @param manifestJSON string
--- @param callback function|nil
function DataExporter:ExportManifest(mapId, manifestJSON, callback)
    local prefix = self:BuildKeyPrefix(mapId)
    local objectKey = prefix .. 'manifest.json'
    self:UploadToS3(objectKey, manifestJSON, 'manifest/' .. mapId, callback)
end

--- Get export statistics
function DataExporter:GetStats()
    return {
        exportedChunks = self.exportedChunks,
        failedExports = self.failedExports,
        pendingUploads = self.pendingUploads,
        enabled = self.enabled,
    }
end

--- Check if all pending uploads have completed
function DataExporter:IsUploadComplete()
    return self.pendingUploads <= 0
end

return DataExporter
