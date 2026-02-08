-- MapScanner Shared Logger
-- Lightweight logging utility

local ScanConfig = require '__shared/ScanConfig'

local Logger = {}
Logger.__index = Logger

function Logger:New(prefix)
    local instance = {
        prefix = prefix or 'MapScanner'
    }
    setmetatable(instance, Logger)
    return instance
end

function Logger:Error(msg, ...)
    print('[' .. self.prefix .. ':ERROR] ' .. string.format(msg, ...))
end

function Logger:Warn(msg, ...)
    print('[' .. self.prefix .. ':WARN] ' .. string.format(msg, ...))
end

function Logger:Info(msg, ...)
    print('[' .. self.prefix .. ':INFO] ' .. string.format(msg, ...))
end

function Logger:Debug(msg, ...)
    if ScanConfig.debugLogging then
        print('[' .. self.prefix .. ':DEBUG] ' .. string.format(msg, ...))
    end
end

--- Write a progress bar to the console
function Logger:Progress(current, total, label)
    local pct = math.floor((current / total) * 100)
    local barLen = 30
    local filled = math.floor(barLen * current / total)
    local bar = string.rep('=', filled) .. string.rep('-', barLen - filled)
    print(string.format('[%s] [%s] %d%% (%d/%d) %s', self.prefix, bar, pct, current, total, label or ''))
end

return Logger
