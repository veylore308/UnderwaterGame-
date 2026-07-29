--[[
    Knit.lua
    Deep Tide Studios — Knit Framework Loader
    
    In production, Knit is installed via Wally and synced by Rojo.
    This file should be replaced by the actual Knit module.
    
    Install: wally install
    Or manually from: https://github.com/Sleitnick/Knit
    
    This stub provides the API surface for development/testing.
]]

local Knit = {}
Knit.__index = Knit

-- Internal registry
Knit._services = {}
Knit._controllers = {}
Knit._signals = {}

-- Promise-like implementation for Knit.Start
local function createPromise()
    local promise = {}
    local _resolved = false
    local _value = nil
    local _error = nil
    local _thenCallbacks = {}
    local _catchCallbacks = {}

    function promise:andThen(callback)
        if _resolved and not _error then
            callback(_value)
        else
            table.insert(_thenCallbacks, callback)
        end
        return promise
    end

    function promise:catch(callback)
        if _resolved and _error then
            callback(_error)
        else
            table.insert(_catchCallbacks, callback)
        end
        return promise
    end

    function promise:_resolve(value)
        _resolved = true
        _value = value
        for _, cb in ipairs(_thenCallbacks) do
            cb(value)
        end
    end

    function promise:_reject(err)
        _resolved = true
        _error = err
        for _, cb in ipairs(_catchCallbacks) do
            cb(err)
        end
    end

    return promise
end

--- Create a new signal (RemoteSignal/RemoteEvent wrapper)
function Knit.CreateSignal()
    return {
        _listeners = {},
        Fire = function(self, ...)
            for _, listener in ipairs(self._listeners) do
                listener(...)
            end
        end,
        FireAll = function(self, ...)
            for _, listener in ipairs(self._listeners) do
                listener(...)
            end
        end,
        Connect = function(self, callback)
            table.insert(self._listeners, callback)
            return {
                Disconnect = function()
                    for i, cb in ipairs(self._listeners) do
                        if cb == callback then
                            table.remove(self._listeners, i)
                            break
                        end
                    end
                end,
            }
        end,
        Call = function(self, ...)
            -- Synchronous call: fire to all server listeners
            -- In production, Knit handles RemoteFunctions
            local results = {}
            for _, listener in ipairs(self._listeners) do
                results[#results + 1] = listener(...)
            end
            return results[1]
        end,
    }
end

--- Create a server-side service
function Knit.CreateService(config)
    local service = setmetatable({
        Name = config.Name,
        Client = config.Client or {},
        Services = {}, -- populated by Knit at init
        Controllers = {},
    }, { __index = Knit })

    -- Store lifecycle hooks
    service._init = service.KnitInit
    service._start = service.KnitStart

    Knit._services[config.Name] = service
    return service
end

--- Create a client-side controller
function Knit.CreateController(config)
    local controller = setmetatable({
        Name = config.Name,
        Services = {}, -- populated by Knit at init
        Controllers = {},
    }, { __index = Knit })

    controller._init = controller.KnitInit
    controller._start = controller.KnitStart

    Knit._controllers[config.Name] = controller
    return controller
end

--- Get a service by name (dependency injection helper)
function Knit.GetService(name)
    return Knit._services[name]
end

--- Get a controller by name
function Knit.GetController(name)
    return Knit._controllers[name]
end

--- Get or create a shared signal by name (cross-service communication)
function Knit.GetSignal(name)
    if not Knit._signals[name] then
        Knit._signals[name] = Knit.CreateSignal()
    end
    return Knit._signals[name]
end

--- Start all services and controllers
function Knit.Start()
    local promise = createPromise()

    -- Resolve service dependencies
    for name, service in pairs(Knit._services) do
        for otherName, otherService in pairs(Knit._services) do
            if otherName ~= name then
                service.Services[otherName] = otherService
            end
        end
    end

    -- Resolve controller dependencies
    for name, controller in pairs(Knit._controllers) do
        for svcName, service in pairs(Knit._services) do
            controller.Services[svcName] = service
        end
        for ctrlName, otherCtrl in pairs(Knit._controllers) do
            if ctrlName ~= name then
                controller.Controllers[ctrlName] = otherCtrl
            end
        end
    end

    -- Call KnitInit on all
    for _, service in pairs(Knit._services) do
        if service._init then
            local success, err = pcall(service._init, service)
            if not success then
                warn("[Knit] Init failed for service", service.Name, ":", err)
            end
        end
    end

    for _, controller in pairs(Knit._controllers) do
        if controller._init then
            local success, err = pcall(controller._init, controller)
            if not success then
                warn("[Knit] Init failed for controller", controller.Name, ":", err)
            end
        end
    end

    -- Call KnitStart on all
    for _, service in pairs(Knit._services) do
        if service._start then
            local success, err = pcall(service._start, service)
            if not success then
                warn("[Knit] Start failed for service", service.Name, ":", err)
            end
        end
    end

    for _, controller in pairs(Knit._controllers) do
        if controller._start then
            local success, err = pcall(controller._start, controller)
            if not success then
                warn("[Knit] Start failed for controller", controller.Name, ":", err)
            end
        end
    end

    promise:_resolve(true)
    return promise
end

return Knit
