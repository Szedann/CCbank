local bank = require("bankApi")
local opMode = false
local reconnectTimer
local reconnectTime = 5
local onReconnect;

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

local function registerATM(fileList, callback)
    if (bank.getLoggingEnabled()) then print("Registering ATM") end

    -- package local files
    local localFiles = {}

    local fileData
    for _, filename in ipairs(fileList) do
        fileData = bank.loadFile("/startup/" .. filename)
        localFiles[filename] = fileData
    end

    print("Checking for Updates...")
    bank.request("registerATM", { files = localFiles },
        function(response)
            if (response.status == "success") then
                if (bank.getLoggingEnabled()) then print("Registered ATM") end
            elseif (response.status == "updates") then
                local files = response.files
                -- tell parent we are updating
                if (callback) then callback(response.status) end
                if (bank.getLoggingEnabled()) then print("updating ATM") end
                -- overwrite existing files with updates
                for filename, file in pairs(files) do
                    bank.writeFile("/startup/" .. filename, file)
                end

                -- close all connections to notify server you're disconnecting
                bank.closeAllConnections()

                -- reboot
                os.reboot()
            else
                if (bank.getLoggingEnabled()) then print("Failed to register ATM") end
            end
            -- send back response to parent
            if (callback) then callback(response.status) end
        end
    )
end

local function handleRequest(id, command, data)
    -- hearbeat from server
    if (command == "beat") then
        -- reset reconnect timer, -- should be started on a different thread
        reconnectTimer = os.startTimer(reconnectTime)
    end
end

-- handles connection to server then starts heart bat timer
local function onStart()
    bank.onStart()

    -- we are connected, start timer
    reconnectTimer = os.startTimer(reconnectTime)
end

local function initialize(onParentStart, onParentEvent, onDisconnect)
    if (bank.getLoggingEnabled()) then print("Initializing") end
    onReconnect = onDisconnect
    bank.initialize(onParentStart, onParentEvent, false, handleRequest, onDisconnect)
end

local function onEvent(event)
    -- call api listners first
    local handled = bank.onEvent(event)

    -- if event wasn't handled, try and handle it
    if (not handled) then
        -- handle events that don't need connection
        if event[1] == "timer" and event[2] == reconnectTimer then
            handled = true
            -- no hearbeat from server in enough time
            -- try to close connection and reconnect
            bank.closeAllConnections()

            -- pass disconnection to parent
            onReconnect()
        end

        -- check if we are connected
        if (bank.isConnected()) then
            -- handle event that need connection
        elseif (not handled) then
            -- don't pass up the event if we are not connected
            handled = true
        end
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
    onStart = onStart,
    coins = bank.coins,
    opMode = opMode,
    setLoggingEnabled = bank.setLoggingEnabled,
    setCryptoLoggingEnabled = bank.setCryptoLoggingEnabled,
    getLoggingEnabled = bank.getLoggingEnabled,
    getCryptoLoggingEnabled = bank.getCryptoLoggingEnabled,
    isConnected = bank.isConnected,
    loadFile = bank.loadFile,
    writeFile = bank.writeFile,
    registerATM = registerATM,
}
