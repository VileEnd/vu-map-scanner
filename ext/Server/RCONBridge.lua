-- MapScanner RCON Bridge
-- Provides configuration and status commands via RCON
-- v2: Simplified for S3-only workflow (no SQL retrieval)

local ScanConfig = require '__shared/ScanConfig'
local Logger = require '__shared/ScanLogger'

local log = Logger:New('RCONBridge')

class 'RCONBridge'

function RCONBridge:__init()
    log:Info('RCONBridge initializing...')

    -- RCON commands for configuration
    self.m_SetConfig = RCON:RegisterCommand('mapscan.config', RemoteCommandFlag.RequiresLogin, self, self.OnConfig)
    self.m_SetS3 = RCON:RegisterCommand('mapscan.s3', RemoteCommandFlag.RequiresLogin, self, self.OnS3Config)
    self.m_AutoStart = RCON:RegisterCommand('mapscan.autostart', RemoteCommandFlag.RequiresLogin, self, self.OnAutoStart)
    self.m_AutoRotate = RCON:RegisterCommand('mapscan.autorotate', RemoteCommandFlag.RequiresLogin, self, self.OnAutoRotate)

    log:Info('RCONBridge initialized')
end

--- Configure scanning parameters via RCON
function RCONBridge:OnConfig(command, args, loggedIn)
    if not args or #args < 1 then
        return {
            'OK',
            'Current configuration:',
            '  preset: ' .. ScanConfig.activePreset,
            '  autoStart: ' .. tostring(ScanConfig.autoStart),
            '  autoRotate: ' .. tostring(ScanConfig.autoRotate),
            '  autoStartDelay: ' .. tostring(ScanConfig.autoStartDelay) .. 's',
            '  debugLogging: ' .. tostring(ScanConfig.debugLogging),
            '  s3Bucket: ' .. ScanConfig.s3Bucket,
            '  s3Endpoint: ' .. ScanConfig.s3Endpoint,
            '',
            'Usage: mapscan.config <key> <value>',
            'Keys: preset, debug, delay',
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
    elseif key == 'debug' and value then
        ScanConfig.debugLogging = (value == 'true' or value == '1')
        return { 'OK', 'Debug logging: ' .. tostring(ScanConfig.debugLogging) }
    elseif key == 'delay' and value then
        ScanConfig.autoStartDelay = tonumber(value) or 10
        return { 'OK', 'Auto-start delay: ' .. tostring(ScanConfig.autoStartDelay) .. 's' }
    end

    return { 'ERR', 'Unknown config key: ' .. key }
end

--- Configure S3 settings via RCON
function RCONBridge:OnS3Config(command, args, loggedIn)
    if not args or #args < 2 then
        return {
            'OK',
            'S3 configuration:',
            '  endpoint: ' .. ScanConfig.s3Endpoint,
            '  region: ' .. ScanConfig.s3Region,
            '  bucket: ' .. ScanConfig.s3Bucket,
            '  pathStyle: ' .. tostring(ScanConfig.s3PathStyle),
            '  accessKey: ' .. (ScanConfig.s3AccessKey ~= '' and '(set)' or '(empty)'),
            '  secretKey: ' .. (ScanConfig.s3SecretKey ~= '' and '(set)' or '(empty)'),
            '',
            'Usage: mapscan.s3 <key> <value>',
            'Keys: endpoint, region, bucket, accessKey, secretKey, pathStyle',
        }
    end

    local key = args[1]
    local value = args[2]

    if key == 'endpoint' then
        ScanConfig.s3Endpoint = value
        return { 'OK', 'S3 endpoint: ' .. value }
    elseif key == 'region' then
        ScanConfig.s3Region = value
        return { 'OK', 'S3 region: ' .. value }
    elseif key == 'bucket' then
        ScanConfig.s3Bucket = value
        return { 'OK', 'S3 bucket: ' .. value }
    elseif key == 'accessKey' then
        ScanConfig.s3AccessKey = value
        return { 'OK', 'S3 access key updated' }
    elseif key == 'secretKey' then
        ScanConfig.s3SecretKey = value
        return { 'OK', 'S3 secret key updated' }
    elseif key == 'pathStyle' then
        ScanConfig.s3PathStyle = (value == 'true' or value == '1')
        return { 'OK', 'S3 path style: ' .. tostring(ScanConfig.s3PathStyle) }
    end

    return { 'ERR', 'Unknown S3 key: ' .. key }
end

--- Toggle auto-start
function RCONBridge:OnAutoStart(command, args, loggedIn)
    if args and #args > 0 then
        ScanConfig.autoStart = (args[1] == 'true' or args[1] == '1' or args[1] == 'on')
    else
        ScanConfig.autoStart = not ScanConfig.autoStart
    end
    return { 'OK', 'Auto-start: ' .. tostring(ScanConfig.autoStart) }
end

--- Toggle auto-rotate
function RCONBridge:OnAutoRotate(command, args, loggedIn)
    if args and #args > 0 then
        ScanConfig.autoRotate = (args[1] == 'true' or args[1] == '1' or args[1] == 'on')
    else
        ScanConfig.autoRotate = not ScanConfig.autoRotate
    end
    return { 'OK', 'Auto-rotate: ' .. tostring(ScanConfig.autoRotate) }
end

return RCONBridge
