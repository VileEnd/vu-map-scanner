-- MapScanner Startup Overrides
-- Registers RCON commands for every ScanConfig key so they can be set
-- from Startup.txt (which runs RCON commands, not Lua code).
--
-- Usage in Startup.txt:
--   MapScanner.s3AccessKey YOUR_ACCESS_KEY
--   MapScanner.s3SecretKey YOUR_SECRET_KEY
--   MapScanner.s3Endpoint nbg1.your-objectstorage.com
--   MapScanner.activePreset turbo
--   MapScanner.autoStart true
--
-- Pattern adapted from positionTracking's TelemetryStartupOverrides.

local ScanConfig = require '__shared/ScanConfig'
local Logger = require '__shared/ScanLogger'
local log = Logger:New('StartupOverrides')

local StartupOverrides = {}

local SENSITIVE_KEYS = {
    s3AccessKey = true,
    s3SecretKey = true,
}

local function trim(value)
    return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function parse_value(raw)
    if raw == nil then return nil end
    local text = trim(raw)
    if text == '' then return nil end

    -- Strip quotes
    local quoted = text:match('^"(.*)"$') or text:match("^'(.*)'$")
    if quoted ~= nil then return quoted end

    -- Booleans
    local lower = string.lower(text)
    if lower == 'true' then return true end
    if lower == 'false' then return false end

    -- Numbers
    local num = tonumber(text)
    if num ~= nil then return num end

    return text
end

local function join_args(args)
    if args == nil or #args == 0 then return nil end
    return table.concat(args, ' ')
end

local function is_settable(value)
    local t = type(value)
    return t == 'string' or t == 'number' or t == 'boolean'
end

function StartupOverrides.Apply()
    if RCON == nil then
        log:Warn('RCON not available — startup overrides disabled')
        return
    end

    local registered = 0

    for key, value in pairs(ScanConfig) do
        if is_settable(value) then
            local commandName = 'MapScanner.' .. key

            RCON:RegisterCommand(commandName, RemoteCommandFlag.RequiresLogin, nil,
                function(p_Default, p_Command, p_Args)
                    local args = p_Args

                    -- GET: no args → return current value
                    if args == nil or #args == 0 then
                        if SENSITIVE_KEYS[key] then
                            return { 'OK', '(hidden)' }
                        end
                        return { 'OK', tostring(ScanConfig[key]) }
                    end

                    -- SET: parse and apply
                    local rawValue = join_args(args)
                    local parsed = parse_value(rawValue)
                    if parsed == nil then
                        return { 'InvalidArguments' }
                    end

                    ScanConfig[key] = parsed

                    if SENSITIVE_KEYS[key] then
                        log:Info('MapScanner.%s updated (sensitive value hidden)', key)
                    else
                        log:Info('MapScanner.%s = %s', key, tostring(parsed))
                    end

                    return { 'OK' }
                end
            )

            registered = registered + 1
        end
    end

    log:Info('Registered %d startup override commands (MapScanner.<key>)', registered)
end

return StartupOverrides
