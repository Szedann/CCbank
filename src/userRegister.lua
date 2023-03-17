local modem = peripheral.find("modem") or error("No modem attached", 0)
local diskDrive = peripheral.wrap("right")

local bankPort = 421
local responsePort = 832


modem.open(responsePort)

local function bankRequest(command, args)
    modem.transmit(bankPort, responsePort, os.getComputerID() .. " " .. command .. " " .. table.concat(args, " "))

    -- And wait for a reply
    local event, side, channel, replyChannel, message, distance
    repeat
        event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
    until channel == responsePort
    local lines = {}
    for s in string.gmatch(message, "[^\r\n]+") do
        table.insert(lines, s)
    end
    message = lines[1]
    local type = lines[2]
    return message, type
end

local function registerUser(name)
    local response = bankRequest("register", { name })
    if response == "success" then
        print("Registered user " .. name)
    else
        print("Failed to register user " .. name)
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
    local response = bankRequest("registerATM", {
        os.getComputerID(),
        responsePort,
        "online"
    })
    if response == "success" then
        print("Registered ATM")
    else
        print("Failed to register ATM")
    end
end

registerATM()

local function handleModemRequest(e)
    local _, _, channel, replyChannel, command, args = receive_modem(e)
    print("Received command: " .. command .. " args: " .. table.concat(args or { "none" }, ", "))
    if command == "PING" then
        modem.transmit(replyChannel, channel, os.getComputerID() .. " PONG")
    end
end



-- Main loop to listen for incoming requests

while true do
    local e = { os.pullEvent() }
    if e[1] == "modem_message" then
        handleModemRequest(e)
    end
    local username = io.stdin:read()
    registerUser(username)
    print("Registered user " .. username)
end
