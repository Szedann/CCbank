local bank = require("bankApi")
local responsePort = 531 + os.getComputerID()
local opMode = false

local function alertServer(message)
    local data = bank.request("alert", { message = message })
    if (data.status == "success") then
        if (bank.logging) then print("Alerted bank of " .. message) end
    else
        if (bank.logging) then print("Failed to alert bank of " .. message) end
    end
end

local function registerATM()
    local data = bank.request("registerATM", {
        port = responsePort
    })
    if (data.status == "success") then
        if (bank.logging) then print("Registered ATM") end
    else
        if (bank.logging) then print("Failed to register ATM") end
    end
end

local function initialize()
    if (bank.logging) then print("Initializing") end
    bank.initialize(responsePort)
    registerATM()
end

local function handleModemRequest(e)
    local _, _, channel, replyChannel, data = bank.receive_modem(e)
    if (bank.logging) then print("Received data: " .. table.concat(data or { "none" }, ", ")) end
    if command == "PING" then
        bank.modem.transmit(replyChannel, channel, os.getComputerID() .. " PONG")
    end
end

return {
    alertServer = alertServer,
    request = bank.request,
    handleModemRequest = handleModemRequest,
    initialize = initialize,
    getUser = bank.getUser,
    getUUID = bank.getUUID,
    logging = bank.logging,
    coins = bank.coins,
    opMode = opMode
}
