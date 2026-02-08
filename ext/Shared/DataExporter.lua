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

--- Build the bucket-root URL (no object key)
--- @return string
function DataExporter:BuildBucketUrl()
    if ScanConfig.s3PathStyle then
        if ScanConfig.s3Endpoint ~= '' then
            return 'https://' .. ScanConfig.s3Endpoint .. '/' .. ScanConfig.s3Bucket .. '/'
        else
            return 'https://s3.' .. ScanConfig.s3Region .. '.amazonaws.com/' .. ScanConfig.s3Bucket .. '/'
        end
    else
        if ScanConfig.s3Endpoint ~= '' then
            return 'https://' .. ScanConfig.s3Bucket .. '.' .. ScanConfig.s3Endpoint .. '/'
        else
            return 'https://' .. ScanConfig.s3Bucket .. '.s3.' .. ScanConfig.s3Region .. '.amazonaws.com/'
        end
    end
end

--- Probe whether the S3 bucket exists (GET with list-type=2&max-keys=0)
--- If the bucket doesn't exist, attempts to create it automatically.
--- Calls callback(true) if the bucket is ready, callback(false) if not.
--- @param callback function - callback(bucketReady: boolean)
function DataExporter:ProbeBucket(callback)
    if not self.enabled then
        log:Error('S3 exporter not enabled — cannot probe bucket')
        if callback then callback(false) end
        return
    end

    -- Signed GET on bucket root with max-keys=0 (cheapest list call)
    local queryString = 'list-type=2&max-keys=0'
    local headers = S3Signer.SignGetRequest(
        ScanConfig.s3AccessKey,
        ScanConfig.s3SecretKey,
        ScanConfig.s3Region,
        ScanConfig.s3Bucket,
        '',              -- no object key
        queryString,
        ScanConfig.s3Endpoint,
        ScanConfig.s3PathStyle
    )

    local url = self:BuildBucketUrl() .. '?' .. queryString
    local httpOptions = HttpOptions(headers, ScanConfig.s3Timeout)

    log:Info('Probing S3 bucket "%s" ...', ScanConfig.s3Bucket)

    local exporter = self
    Net:GetHTTPAsync(url, httpOptions, function(response)
        local status = response and response.status or 0
        if status >= 200 and status < 300 then
            log:Info('Bucket "%s" exists and is accessible (HTTP %d)', ScanConfig.s3Bucket, status)
            if callback then callback(true) end
        elseif status == 404 or (response and response.body and tostring(response.body):find('NoSuchBucket')) then
            log:Warn('Bucket "%s" does not exist (HTTP %d) — attempting auto-create...', ScanConfig.s3Bucket, status)
            exporter:CreateBucket(callback)
        elseif status == 403 then
            log:Error('Bucket probe DENIED (HTTP 403) — check S3 credentials and permissions')
            if callback then callback(false) end
        else
            local body = response and response.body and tostring(response.body):sub(1, 300) or ''
            log:Error('Bucket probe failed (HTTP %d): %s', status, body)
            if callback then callback(false) end
        end
    end)
end

--- Create the S3 bucket using a signed PUT on the bucket root
--- @param callback function - callback(success: boolean)
function DataExporter:CreateBucket(callback)
    local headers = S3Signer.SignCreateBucket(
        ScanConfig.s3AccessKey,
        ScanConfig.s3SecretKey,
        ScanConfig.s3Region,
        ScanConfig.s3Bucket,
        ScanConfig.s3Endpoint,
        ScanConfig.s3PathStyle
    )

    local url = self:BuildBucketUrl()
    local httpOptions = HttpOptions(headers, ScanConfig.s3Timeout)

    log:Info('Creating S3 bucket "%s" at %s ...', ScanConfig.s3Bucket, url)

    Net:PutHTTPAsync(url, '', httpOptions, function(response)
        local status = response and response.status or 0
        if status >= 200 and status < 300 then
            log:Info('Bucket "%s" created successfully (HTTP %d)', ScanConfig.s3Bucket, status)
            if callback then callback(true) end
        elseif status == 409 then
            -- BucketAlreadyOwnedByYou — that's fine
            log:Info('Bucket "%s" already exists (HTTP 409) — proceeding', ScanConfig.s3Bucket)
            if callback then callback(true) end
        else
            local body = response and response.body and tostring(response.body):sub(1, 300) or ''
            log:Error('Failed to create bucket "%s" (HTTP %d): %s', ScanConfig.s3Bucket, status, body)
            log:Error('Please create the bucket manually via your S3 provider console')
            if callback then callback(false) end
        end
    end)
end

return DataExporter
