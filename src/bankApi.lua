local modem = peripheral.find("modem") or error("No modem attached", 0)
local UUIDFile = "info"
local bankPort = 421
local logging = false

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

local responsePort

local function initialize(port)
    responsePort = port
    modem.open(responsePort)
end

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

local function bankRequest(command, data, expectResponse)
    if expectResponse == nil then
        expectResponse = true
    end
    local id = randomString(8)
    data.messageID = id
    modem.transmit(bankPort, responsePort, os.getComputerID() .. " " .. command .. " " .. textutils.serialize(data))

    -- And wait for a reply
    local event, side, channel, replyChannel, message, distance
    local data
    if not expectResponse then
        return
    end
    repeat
        event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if (logging) then print(event, side, channel, replyChannel, message, distance) end
        data = textutils.unserialize(message)
    until channel == responsePort and replyChannel == bankPort and data.responseTo == id
    local lines = {}
    return data
end

local function getBalance(cardID)
    local balance = bankRequest("balance", { cardID = cardID })
    if (logging) then print(currentUser.name .. " has " .. balance .. " cogs") end
end


local function receive_modem(e)
    event, side, channel, replyChannel, message, distance = table.unpack(e)
    if (logging) then print(event, side, channel, replyChannel, message, distance) end
    local args = {}
    for arg in string.gmatch(message, "%S+") do
        table.insert(args, arg)
    end
    local data = textutils.unserialize(table.concat(args, " ")) or {}
    return event, side, channel, replyChannel, data
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

local function getUser(UUID)
    local data = bankRequest("search", { cardID = UUID })
    if data.status == "error" then
        if (logging) then print("Error: " .. (data.message or "Unknown")) end
        return nil
    else
        return {
            name = data.user.name,
            balance = data.user.balance,
            cardID = UUID
        }
    end
end

return {
    getUser = getUser,
    getBalance = getBalance,
    request = bankRequest,
    randomString = randomString,
    receive_modem = receive_modem,
    coins = coins,
    initialize = initialize,
    bankPort = bankPort,
    getUUID = getUUID,
    logging = logging
}
