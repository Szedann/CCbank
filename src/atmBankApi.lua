local bank = require("bankApi")
local opMode = false

local function alertServer(message)
    bank.request("alert", { message = message },
        function(respose)
            if (respose.status == "success") then
                if (bank.getLoggingEnabled()) then print("Alerted bank of " .. message) end
            else
                if (bank.getLoggingEnabled()) then print("Failed to alert bank of " .. message) end
            end
        end
    )
end

local function registerATM()
    if (bank.getLoggingEnabled()) then print("Registering ATM") end
    bank.request("registerATM", {},
        function(response)
            if (response.status == "success") then
                if (bank.getLoggingEnabled()) then print("Registered ATM") end
            else
                if (bank.getLoggingEnabled()) then print("Failed to register ATM") end
            end
        end
    )
end

local function initialize(onParentStart, onParentEvent)
    if (bank.getLoggingEnabled()) then print("Initializing") end
    bank.initialize(onParentStart, onParentEvent, false)
end

local function onEvent(event)
    -- call api listners first
    local handled = bank.onEvent(event)

    -- if event wasn't handled, try and handle it
    if (not handled) then

    end
    return handled
end

-- pings are now sent from client to server, not requested by server, this is no longer needed
--[[
local function handleModemRequest(e)
    local _, _, channel, replyChannel, data = bank.receive_modem(e)
    if (bank.logging) then print("Received data: " .. table.concat(data or { "none" }, ", ")) end
    if command == "PING" then
        bank.modem.transmit(replyChannel, channel, os.getComputerID() .. " PONG")
    end
end]]
--

return {
    alertServer = alertServer,
    request = bank.request,
    --handleModemRequest = handleModemRequest,
    initialize = initialize,
    getUser = bank.getUser,
    getUUID = bank.getUUID,
    trimErr = bank.trimErr,
    printErr = bank.printErr,
    onEvent = onEvent,
    onStart = bank.onStart,
    coins = bank.coins,
    opMode = opMode,
    setLoggingEnabled = bank.setLoggingEnabled,
    setCryptoLoggingEnabled = bank.setCryptoLoggingEnabled,
    getLoggingEnabled = bank.getLoggingEnabled,
    getCryptoLoggingEnabled = bank.getCryptoLoggingEnabled,
    registerATM = registerATM,
}
