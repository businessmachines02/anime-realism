local Logger = {}

Logger.levels = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

Logger.currentLevel = Logger.levels.DEBUG

local function levelName(level)
    for k, v in pairs(Logger.levels) do
        if v == level then return k end
    end
    return "UNKNOWN"
end

function Logger.setLevel(level)
    if type(level) == "string" then
        level = Logger.levels[level:upper()] or Logger.levels.DEBUG
    end
    Logger.currentLevel = level
end

function Logger._log(level, ...)
    if level < Logger.currentLevel then
        return
    end
    local msg = ""
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        msg = msg .. tostring(v)
        if i < select("#", ...) then
            msg = msg .. "\t"
        end
    end
    print(("[%s] %s"):format(levelName(level), msg))
end

function Logger.debug(...)
    Logger._log(Logger.levels.DEBUG, ...)
end

function Logger.info(...)
    Logger._log(Logger.levels.INFO, ...)
end

function Logger.warn(...)
    Logger._log(Logger.levels.WARN, ...)
end

function Logger.error(...)
    Logger._log(Logger.levels.ERROR, ...)
end

return Logger