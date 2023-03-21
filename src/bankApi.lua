local UUIDFile = "info"
local cryptoNetPath = "cryptoNet"
local cryptoNetURL = "https://raw.githubusercontent.com/SiliconSloth/CryptoNet/master/cryptoNet.lua"
local serverName = "BANK - Server"
local socket = nil
local callbacks = {}       -- functions to call after getting a response
local messageHandler = nil -- handles responding to message received
local isServer = false     -- will get set based on parent calls
local cryptoLogging = true
local logging = false

-- check for and download needed cryptoNet API
if not fs.exists(cryptoNetPath) then
    print("can't find " .. cryptoNetPath .. " API file.\nDownloading, please wait...")
    shell.run("wget", cryptoNetURL, cryptoNetPath)
    -- TODO: handle no internet connection, and download errors
    repeat
    until fs.exists(cryptoNetPath) -- wait for downlaod to finish
end

os.loadAPI(cryptoNetPath)

local coins = {
    spurs = {
        nbt = "d3adddbc586c8a708b5e213b206b7687",
        rate = 1 / 64
    },
    bevels = {
        nbt = "c9f52ce05acf3715bf592eea6edbc450",
        rate = 1 / 8
    },
    sprockets = {
        nbt = "25a3275f9ecdc11c78648e61e95376b0",
        rate = 1 / 4
    },
    cogs = {
        nbt = "2442f28a7aec5cf7b09d2c2756caa1a4",
        rate = 1
    },
    crowns = {
        nbt = "77b458f3adececb55e27a47b4ecb714b",
        rate = 8
    },
    suns = {
        nbt = "9eabd6c6d7c587c1694fb86d4182cd62",
        rate = 64
    }
}

local currentUser = nil

local charset = {}
do -- [0-9a-zA-Z]
    for c = 48, 57 do table.insert(charset, string.char(c)) end
    for c = 65, 90 do table.insert(charset, string.char(c)) end
    for c = 97, 122 do table.insert(charset, string.char(c)) end
end

local function randomString(length)
    if not length or length <= 0 then return '' end
    math.randomseed(os.clock() ^ 5)
    return randomString(length - 1) .. charset[math.random(1, #charset)]
end

-- currently sends message to client from server in response to client
local function respond(message, messageData)
    message.responseTo = messageData.messageID
    cryptoNet.send(messageData.socket, textutils.serialize(message))
    --modem.transmit(replyChannel, channel, textutils.serialize(message))
end

-- currently sends message from client to server
local function bankRequest(command, data, callback)
    local id = randomString(8)
    if (callback) then -- if we have a callback
        callbacks[id] = callback
    end
    data.messageID = id
    cryptoNet.send(socket, os.getComputerID() .. " " .. command .. " " .. textutils.serialize(data))

    -- And wait for a reply
    --[[local event, side, channel, replyChannel, message, distance
    local data
    if not expectResponse then
        return
    end
    local timeoutTimer = os.startTimer(5)
    repeat
        local e = { os.pullEvent() }

        if e[1] == "timer" and e[2] == timeoutTimer then
            error("Bank request timed out")
        elseif e[1] == "modem_message" then
            event, side, channel, replyChannel, message, distance = table.unpack(e)
            if (logging) then print(event, side, channel, replyChannel, message, distance) end
            data = textutils.unserialize(message)
        end
    until channel == responsePort and replyChannel == bankPort and data.responseTo == id
    return data]]
    --
end

local function getBalance()
    bankRequest("balance", { cardID = currentUser.cardID },
        function(response)
            if (response.status == "success") then
                if (logging) then print(currentUser.name .. " has " .. response.balance .. " cogs") end
                currentUser.balance = response.balance
            else
                if (logging) then print("Failed to get " .. currentUser.name .. "'s account balance.") end
            end
        end
    )
end

local function getUser(UUID, callback)
    if (not UUID or not callback) then
        callback(nil)
    end
    bankRequest("search", { cardID = UUID },
        function(response)
            if (response.status == "error") then
                if (logging) then print("Error: " .. (response.message or "Unknown")) end
                callback(nil)
            else
                callback({
                    name = response.user.name,
                    balance = response.user.balance,
                    cardID = UUID
                })
            end
        end
    )
end

-- replaced by cryptoNet's Event Loop
--[[
local function receive_modem(e)
    event, side, channel, replyChannel, message, distance = table.unpack(e)
    if (logging) then print(event, side, channel, replyChannel, message, distance) end
    local args = {}
    for arg in string.gmatch(message, "%S+") do
        table.insert(args, arg)
    end
    local data = textutils.unserialize(table.concat(args, " ")) or {}
    return event, side, channel, replyChannel, data
end]]
--

local function trimErr(err)
    -- trim beginning "location data" from system error message
    local trimIndex = string.find(err, ': ', 1, true)
    if (trimIndex) then
        err = string.sub(err, trimIndex + 2)
    end
    return err
end

local function printErr(err)
    -- save current color and change text to red: error text
    local color = term.getTextColor()
    term.setTextColor(colors.red)

    print(err)

    -- restore text color
    term.setTextColor(color)
end

local function setUUID(cardDrive, cardID)
    local UUIDPath = cardDrive.getMountPath()
    local file = fs.open("/" .. UUIDPath .. "/" .. UUIDFile, "w")
    file.write(cardID)
    file.close()
end
local function getUUID(cardDrive)
    local UUIDPath = cardDrive.getMountPath()
    local file = fs.open("/" .. UUIDPath .. "/" .. UUIDFile, "r")
    local cardID
    if (file) then
        cardID = file.readAll()
        file.close()
    end
    return cardID
end

-- Runs every time an event occurs
local function onEvent(event)
    --print(event[1])
    local handled = false
    -- Received a message from the server
    if event[1] == "connection_closed" then
        -- close socket
        cryptoNet.close(event[2])
    elseif event[1] == "encrypted_message" then
        handled = true
        local args = {}
        for arg in string.gmatch(event[2], "%S+") do
            table.insert(args, arg)
        end
        if (isServer) then
            -- uppack message request
            local id = table.remove(args, 1)
            local command = table.remove(args, 1)
            local serialized = table.concat(args, " ")
            local data = textutils.unserialize(serialized) or {}
            if (logging) then print("Received command: " .. command .. " args: " .. table.concat(data, ", ")) end
            -- socket of request sender, use this to respond
            data.socket = event[3]
            -- send message to server handler
            messageHandler(id, command, data)
        else
            -- unpack message response
            local data = textutils.unserialize(table.concat(args, " ")) or {}
            if (logging) then print("got message: " .. data.responseTo) end
            -- check for a response callback
            if (callbacks[data.responseTo]) then
                callbacks[data.responseTo](data)
                -- callback used, set this respose id to nil to "remove" it
                callbacks[data.responseTo] = nil
            end
        end
    else

    end

    return handled
end

local function onStart()
    if (isServer) then
        -- Start the server
        cryptoNet.host(serverName)
    else
        -- connect to server
        local status, res = pcall(cryptoNet.connect, serverName)
        if (status) then
            socket = res
            print("connected")
        else
            print("could not connect:" .. res)
        end
    end
end

local function initialize(onParentStart, onParentEvent, server, msgHanlder)
    isServer = server
    messageHandler = msgHanlder
    cryptoNet.setLoggingEnabled(cryptoLogging)

    -- start cryptoNet event loop
    cryptoNet.startEventLoop(onParentStart, onParentEvent)
end

return {
    getUser = getUser,
    getBalance = getBalance,
    request = bankRequest,
    randomString = randomString,
    --receive_modem = receive_modem,
    onEvent = onEvent,
    onStart = onStart,
    respond = respond,
    coins = coins,
    initialize = initialize,
    getUUID = getUUID,
    setUUID = setUUID,
    trimErr = trimErr,
    printErr = printErr,
    logging = logging,
    cryptoLogging = cryptoLogging
}
