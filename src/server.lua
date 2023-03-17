local modem = peripheral.find("modem") or error("No modem attached", 0)
local storageDrive = peripheral.wrap("back")
local cardDrive = peripheral.wrap("right")
local pingInterval = 5

local bank = {}
local users = {}
local ATMs = {}

local port = 421

modem.open(port)
redstone.setAnalogOutput("bottom", 15)

print("Server started on port " .. port)

-- Define the currency conversion rates
local rates = {
    spurs = 1 / 64,
    bevels = 1 / 8,
    sprockets = 1 / 4,
    cogs = 1,
    crowns = 8,
    suns = 64
}

-- Helper function to convert between currencies
local function convert(amount, from, to)
    return amount * rates[from] / rates[to]
end

-- Load the user database
local function loadUsers()
    if (not storageDrive.isDiskPresent()) then
        return error("No storage disk inserted")
    end
    local file = fs.open("/disk/users", "r")
    local data
    if (file) then
        data = file.readAll()
        file.close()
    else
        data = "{}"
    end
    users = textutils.unserialize(data) or {}
end

loadUsers()

-- Save the user database

local function saveUsers()
    if (not storageDrive.isDiskPresent()) then
        return error("No storage disk inserted")
    end
    local file = fs.open("/disk/users", "w")
    file.write(textutils.serialize(users))
    file.close()
end

-- Function to register a new user
function bank.registerUser(name)
    if (#name > 16) then
        return false --error("Name too long")
    end
    if (#name < 3) then
        return false --error("Name too short")
    end
    for key, user in pairs(users) do
        if user.name == name then
            return false --error("User already exists")
        end
    end
    if (not cardDrive.isDiskPresent()) then
        return error("No card inserted")
    end
    local cardID = cardDrive.getDiskID()
    cardDrive.setDiskLabel(name .. "'s card")
    redstone.setAnalogOutput("bottom", 0)
    sleep(.05)
    redstone.setAnalogOutput("bottom", 15)
    users[cardID] = { name = name, balance = 0 }
    saveUsers()
end

-- Function to get a user's balance
function bank.getBalance(name)
    return users[name].balance
end

-- Function to handle an incoming deposit
function bank.deposit(name, amount, cardID)
    local user = users[cardID]
    if user.name ~= name then
        return false --error("Incorrect Card")
    end
    local balance = users[cardID].balance
    users[cardID].balance = balance + amount
    saveUsers()
    return true
end

-- Function to handle an incoming withdrawal
function bank.withdraw(name, amount, cardID)
    print(name, amount, cardID)
    local user = users[cardID]
    if user.name ~= name then
        return false --error("Incorrect Card")
    elseif user.balance < amount then
        return false --error("Insufficient funds")
    else
        user.balance = user.balance - amount
        saveUsers()
        return true
    end
end

-- Function to handle incoming alerts
function bank.alert(message)
    term.clear()
    print(message)
end

function registerATM(id, port, status)
    ATMs[id] = { id = id, port = tonumber(port), status = status }
    print("Registered ATM " .. id .. " on port " .. port)
end

local function receive_modem(e)
    event, side, channel, replyChannel, message, distance = table.unpack(e)
    print(event, side, channel, replyChannel, message, distance)
    local args = {}
    for arg in string.gmatch(message, "%S+") do
        table.insert(args, arg)
    end
    local id = table.remove(args, 1)
    local command = table.remove(args, 1)
    local serialized = table.concat(args, " ")
    local data = textutils.unserialize(serialized) or {}
    print("Received command: " .. command .. " args: " .. table.concat(data, ", "))
    return event, side, channel, replyChannel, command, data, id
end

local function handleModemRequest(e)
    local _, _, channel, replyChannel, command, data, id = receive_modem(e)
    local function respond(message)
        message.responseTo = data.messageID
        modem.transmit(replyChannel, channel, textutils.serialize(message))
    end
    if command == "register" then
        bank.registerUser(data.name)
        respond({ status = "success" })
    elseif command == "balance" then
        local balance = bank.getBalance(data.name)
        modem.transmit(replyChannel, channel, balance)
    elseif command == "deposit" then
        if not ATMs[id] then
            respond { status = "error", message = "ATM not registered" }
        end
        local res = bank.deposit(data.name, data.amount, data.cardID)
        if (res) then
            respond({ status = "success" })
        else
            respond({ status = "error" })
        end
    elseif command == "withdraw" then
        if not ATMs[id] then
            respond({ status = "error", message = "ATM not registered" })
        end
        local res = bank.withdraw(data.name, data.amount, data.cardID)
        if (res) then
            respond({ status = "success" })
        else
            respond({ status = "error" })
        end
    elseif command == "alert" then
        bank.alert(data.message)
    elseif command == "registerATM" then
        registerATM(id, data.port, "ONLINE")
        respond({ status = "success" })
    elseif command == "search" then
        print("Searching for user " .. data.cardID)
        local user = users[data.cardID]
        if user then
            print("Found user " .. user.name)
            respond({
                status = "success",
                user = {
                    name = user.name,
                    balance = user.balance
                }
            })
        else
            respond({ status = "error", message = "Card not registered" })
        end
    end
end


local PING_TIMER = os.startTimer(5 * 60)
-- Main loop to listen for incoming requests
while true do
    local e = { os.pullEvent() }
    if e[1] == "modem_message" then
        handleModemRequest(e)
    elseif e[1] == "timer" and e[2] == PING_TIMER then
        print("Pinging ATMs")
        PING_TIMER = os.startTimer(5)
        for index, value in pairs(ATMs) do
            print("Pinging ATM " .. value.id .. " on port " .. value.port)
            modem.transmit(value.port, port, textutils.serialize({ command = "PING" }))
            local timeoutTimer = os.startTimer(1)
            local e2 = { os.pullEvent() }
            if e2[1] == "timer" and e2[2] == timeoutTimer then
                value.status = "OFFLINE"
                bank.alert("ATM " .. value.id .. " is offline")
            elseif e2[1] == "modem_message" then
                local _, _, channel, replyChannel, command, data, id = receive_modem(e2)
                if command == "PONG" then
                    os.cancelTimer(timeoutTimer)
                    print("ATM " .. value.id .. " is online")
                    value.status = "ONLINE"
                end
            end
        end
    end
end
