local modem = peripheral.find("modem") or error("No modem attached", 0)

local bankPort = 421
local responsePort = 531 + os.getComputerID()

modem.open(responsePort)

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


local function bankRequest(command, data)
    local id = randomString(8)
    data.messageID = id
    modem.transmit(bankPort, responsePort, os.getComputerID() .. " " .. command .. " " .. textutils.serialize(data))

    -- And wait for a reply
    local event, side, channel, replyChannel, message, distance
    local data
    repeat
        event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        data = textutils.unserialize(message)
    until channel == responsePort and replyChannel == bankPort and data.responseTo == id
    local lines = {}
    return data
end


local function registerUser(name)
    local data = bankRequest("register", { name = name })
    if data.status == "success" then
        print("Registered user " .. name)
    else
        print("Failed to register user " .. name)
        print(data.message)
    end
end

local function receive_modem(e)
    event, side, channel, replyChannel, message, distance = table.unpack(e)
    print(event, side, channel, replyChannel, message, distance)
    local args = {}
    for arg in string.gmatch(message, "%S+") do
        table.insert(args, arg)
    end
    local command = table.remove(args, 1)
    return event, side, channel, replyChannel, command, args
end

-- Register the ATM

local function registerATM()
    local data = bankRequest("registerATM", {
        port = responsePort
    })
    if data.status == "success" then
        print("Registered ATM")
    else
        print("Failed to register ATM")
    end
end

registerATM()

w, h = term.getSize()
term.setBackgroundColor(colors.red)
term.setCursorPos(1, 1)
term.clearLine()
print("Account Creation Terminal")
term.setBackgroundColor(colors.black)
local window = window.create(term.current(), 1, 2, w, h - 1)
term.redirect(window)

local function handleModemRequest(e)
    local _, _, channel, replyChannel, command, args = receive_modem(e)
    print("Received command: " .. command .. " args: " .. table.concat(args or { "none" }, ", "))
    if command == "PING" then
        modem.transmit(replyChannel, channel, os.getComputerID() .. " PONG")
    end
end

while true do
    local e = { os.pullEvent() }
    if e[1] == "modem_message" then
        handleModemRequest(e)
    end
    print("Input account name to register:")
    local username = io.stdin:read()
    registerUser(username)
end
