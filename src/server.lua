local bank = require("bankApi")
local storageDrive = peripheral.wrap("back")
local cardDrive = peripheral.wrap("right")
--local pingInterval = 5 * 60
local users = {}
local ATMs = {}

-- Helper function to convert between currencies
local function convert(amount, from, to)
    return amount * bank.coins[from].rate / bank.coins[to].rate
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

local function getUser(cardID)
    print("Searching for user ID: " .. cardID)
    return users[cardID]
end

-- generate unique IDs
local function genUUID(atmID)
    local ts = os.time(os.date("!*t"))
    local UUID = atmID .. ts
    UUID = string.format("%x", tonumber(UUID))
    return UUID
end


-- Function to register a new user
local function registerUser(name, atmID)
    if (#name > 16) then
        return error("Name too long")
    end
    if (#name < 3) then
        return error("Name too short")
    end
    for key, user in pairs(users) do
        if user.name == name then
            return error("User already exists")
        end
    end
    if (not cardDrive.isDiskPresent()) then
        return error("No card inserted")
    end
    --local cardID = cardDrive.getDiskID()
    local cardID = genUUID(atmID)
    if (not cardID) then
        return error("Error creating " .. name .. "'s card")
    end
    cardDrive.setDiskLabel(name .. "'s card")

    -- write card ID to card
    bank.setUUID(cardDrive, cardID)

    -- output card
    redstone.setAnalogOutput("bottom", 0)
    sleep(.05)
    redstone.setAnalogOutput("bottom", 15)

    -- save user data
    users[cardID] = { name = name, balance = 0 }
    saveUsers()
end

-- Function to get a user's balance
local function getBalance(cardID)
    return users[cardID].balance
end

-- Function to handle an incoming deposit
local function deposit(name, amount, cardID)
    local user = users[cardID]
    if user.name ~= name then
        error("Incorrect Card")
    end
    local balance = users[cardID].balance
    users[cardID].balance = balance + amount
    saveUsers()
    return true
end

-- Function to handle an incoming withdrawal
local function withdraw(name, amount, cardID)
    print(name, amount, cardID)
    local user = users[cardID]
    if user.name ~= name then
        error("Incorrect Card")
    elseif user.balance < amount then
        error("Insufficient funds")
    else
        user.balance = user.balance - amount
        saveUsers()
        return true
    end
end

-- Function to handle incoming alerts
local function alert(message)
    bank.printErr(message)
end

local function registerATM(id, status)
    ATMs[id] = { id = id, status = status }
    print("Registered ATM " .. id)
end

-- not needed as we now use cryptoNet to handle inccoming requests
--[[
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
end]]
--

local function handleRequest(id, command, data)
    local function respond(message)
        bank.respond(message, data)
    end
    if command == "register" then
        local status, res = pcall(registerUser, data.name, id)
        if (status) then
            respond({ status = "success", name = data.name })
        else
            bank.printErr(res)
            respond({ status = "error", name = data.name, message = bank.trimErr(res) })
        end
    elseif command == "balance" then
        local status, res = pcall(getBalance, data.cardID)
        if (status) then
            respond({ status = "success", balance = res })
        else
            bank.printErr(res)
            respond({ status = "error", message = bank.trimErr(res) })
        end
    elseif command == "deposit" then
        if not ATMs[id] then
            respond({ status = "error", message = "ATM not registered" })
        end
        local status, res = pcall(deposit, data.name, data.amount, data.cardID)
        if (status) then
            respond({ status = "success" })
        else
            bank.printErr(res)
            respond({ status = "error", message = bank.trimErr(res) })
        end
    elseif command == "withdraw" then
        if not ATMs[id] then
            respond({ status = "error", message = "ATM not registered" })
        end
        local status, res = pcall(withdraw, data.name, data.amount, data.cardID)
        if (status) then
            respond({ status = "success" })
        else
            bank.printErr(res)
            respond({ status = "error", message = bank.trimErr(res) })
        end
    elseif command == "alert" then
        -- alerts could never throw an error (to my knowledge)
        alert("ATM " .. id .. ": " .. data.message)
        respond({ status = "success", message = data.message })
    elseif command == "registerATM" then
        -- registering an ATM could never throw an error (to my knowledge)
        registerATM(id, "ONLINE")
        respond({ status = "success" })
    elseif command == "search" then
        local status, res = pcall(getUser, data.cardID)
        if status then
            print("Found user " .. res.name)
            respond({
                status = "success",
                user = {
                    name = res.name,
                    balance = res.balance,
                    cardID = data.cardID
                }
            })
        else
            bank.printErr(res)
            respond({ status = "error", message = "Card not registered." })
        end
    end
end
-- net needed as we have a dedicated request hanlder
-- and all request events are handled by cryptoNet
--[[
local function handleModemRequest(e)
    local _, _, channel, replyChannel, command, data, id = receive_modem(e)

end]]
--

local function onEvent(event)
    -- call api listners first
    local handled = bank.onEvent(event)

    -- if event wasn't handled, try and handle it
    if (not handled) then

    end
    return handled
end

local function main()
    redstone.setAnalogOutput("bottom", 15)

    -- run any start methods for the APIs
    bank.onStart()

    print("Server started...")

    -- Main loop to listen for incoming requests
    -- main loop no longer need as messages are handled by cryptoNet
    -- and pings are sent from clients, not requested by server
    --[[
    local PING_TIMER = os.startTimer(pingInterval)

    while true do
        local e = { os.pullEvent() }
        if e[1] == "modem_message" then
            handleModemRequest(e)
        elseif e[1] == "timer" and e[2] == PING_TIMER then
            print("Pinging ATMs")
            PING_TIMER = os.startTimer(pingInterval)
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
    end]]
    --
end




-- intialize, passing main and this onEvent function as the entry listener
-- and pass that this is a server and the server
-- request handler function
bank.initialize(main, onEvent, true, handleRequest)
