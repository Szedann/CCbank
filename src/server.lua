-- os.pullEvent = os.pullEventRaw -- catches termination events
local bank = require("bankApi")
local storageDrive = peripheral.wrap("back")
local cardDrive = peripheral.wrap("right")
local beatTimer
local beatTime = 3

--local pingInterval = 5 * 60
local clientTypeFile = "clientTypes"
-- files needed for each client type
local clientTypes = {
    types = {
        pocket = {
            "bankApi.lua",
            "atmBankApi.lua",
            "pocket.lua"
        },
        atm = {
            "bankApi.lua",
            "atmBankApi.lua",
            "atm.lua"
        },
        register = {
            "bankApi.lua",
            "atmBankApi.lua",
            "userRegister.lua"
        },
        admin = {
            "atmBankApi.lua",
            "bankApi.lua",
            "admin.lua"
        }
    }
}

local fileList = {
    "atmBankApi.lua",
    "bankApi.lua",
    "pocket.lua",
    "atm.lua",
    "admin.lua",
    "userRegister.lua"
}
local users = {}
local ATMs = {}
local localFiles = {}

bank.setLoggingEnabled(false)
bank.setCryptoLoggingEnabled(false)

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

local function getUsers()
    local userTable = {}
    for key, user in pairs(users) do
        table.insert(userTable, {
            name = user.name,
            UUID = key,
        })
    end
    return userTable
end

local function readClients()
    -- load client type list
    local clientTypesData = bank.loadFile(clientTypeFile)
    -- if we have existing client type data
    if (clientTypesData) then
        print("client data:")
        if (type(clientTypeFile) == "string") then
            clientTypesData = textutils.unserialize(clientTypesData) or {}
        end
        print(textutils.serialise(clientTypesData))
        -- parse data
        for key, data in pairs(clientTypesData) do
            clientTypes[key] = data
        end
    else
        bank.writeFile(clientTypeFile, "")
        print("Client type file created: " .. clientTypeFile)
        print("Take this time to add an admin client id to that file.")
    end
end

local function writeClients()
    local clientFileData = {}

    for key, data in pairs(clientTypes) do
        clientFileData[key] = data
    end

    clientFileData["types"] = nil

    bank.writeFile(clientTypeFile, textutils.serialize(clientFileData))
end


-- Function to register a new client
local function registerClient(id, type)
    -- add client id to Client types
    clientTypes[id] = type

    -- re write client file
    writeClients()
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
    for index, value in ipairs(clientTypes.types.pocket) do
        fs.copy(value, cardDrive.getMountPath() .. "/startup/" .. value)
    end

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
local function deposit(amount, cardID)
    local user = users[cardID]
    if (not user) then
        error("User not found")
    end
    local balance = users[cardID].balance
    users[cardID].balance = balance + amount
    saveUsers()
    return true
end

-- Function to handle an incoming withdrawal
local function withdraw(amount, cardID)
    local user = users[cardID]
    if (not user) then
        error("User not found")
    end
    if user.balance < amount then
        error("Insufficient funds")
    else
        user.balance = user.balance - amount
        saveUsers()
        return true
    end
end

-- Function to handle an incoming transfer
local function transfer(amount, fromCardID, toCardID)
    if amount <= 0 then
        error("Invalid amount")
    end
    if withdraw(amount, fromCardID) then
        deposit(amount, toCardID)
        return true
    else
        return false
    end
end

-- Function to handle incoming alerts
local function alert(message)
    bank.printErr(message)
end

local function getUpdatedFiles()
    -- check for updates

    -- load client type list
    readClients()

    -- load all local updated files
    for _, filename in ipairs(fileList) do
        local fileData = bank.loadFile(filename)
        localFiles[filename] = fileData
    end
end

local function updateCheck(id, files)
    -- files defaults to an empty table
    if (files == nil) then
        files = {}
    end

    -- get client type
    local type = clientTypes[id]

    -- get files to compare based on client type
    if (type ~= nil) then
        local updateFiles = {}
        local updated = true
        local compareFilenames = clientTypes.types[type]

        -- comare files
        for _, filename in ipairs(compareFilenames) do
            if (localFiles[filename] ~= files[filename]) then
                updated = false
                updateFiles[filename] = localFiles[filename]
            end
        end

        -- if no updates
        if (updated) then
            -- return nil, there are no updates
            return nil
        else
            -- return files
            print("Updating CLient " .. id)
            return updateFiles
        end
    else
        -- client not recognized
        print("CLient " .. id .. " not recognized")
        return -1
    end
end

local function registerATM(id, status, files)
    -- check for updates
    local stat, res = pcall(updateCheck, id, files)
    local updateFiles
    if (stat) then
        updateFiles = res
    else
        bank.printErr(res)
        error(res)
    end

    -- if there are no files to update
    if (updateFiles == nil) then
        -- allow client to register
        ATMs[id] = { id = id, status = status }
        print("Registered CLient " .. id)
    else
        -- deny client registration
        ATMs[id] = nil
    end
    return updateFiles
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
    if command == "setup" then
        if clientTypes[id] ~= "admin" then
            respond({ status = "error", message = "Not allowed to use this action." })
        else
            print(data.id)
            local status, res = pcall(registerClient, data.id, data.type)
            if (status) then
                respond({ status = "success" })
            else
                bank.printErr(res)
                respond({ status = "error", message = bank.trimErr(res) })
            end
        end
    elseif command == "register" then
        if not ATMs[id] then
            respond({ status = "error", message = "Not logged In, Invalid Client" })
        else
            local status, res = pcall(registerUser, data.name, id)
            if (status) then
                respond({ status = "success" })
            else
                bank.printErr(res)
                respond({ status = "error", message = bank.trimErr(res) })
            end
        end
    elseif command == "balance" then
        if not ATMs[id] then
            respond({ status = "error", message = "Not logged In, Invalid Client" })
        else
            local status, res = pcall(getBalance, data.cardID)
            if (status) then
                respond({ status = "success", balance = res })
            else
                bank.printErr(res)
                respond({ status = "error", message = bank.trimErr(res) })
            end
        end
    elseif command == "getUsers" then
        if not ATMs[id] then
            respond({ status = "error", message = "Not logged In, Invalid Client" })
        else
            local status, res = pcall(getUsers)
            if (status) then
                respond({ status = "success", users = res })
            else
                bank.printErr(res)
                respond({ status = "error", message = bank.trimErr(res) })
            end
        end
    elseif command == "deposit" then
        if not ATMs[id] then
            respond({ status = "error", message = "Not logged In, Invalid Client" })
        else
            local status, res = pcall(deposit, data.amount, data.cardID)
            if (status) then
                respond({ status = "success" })
            else
                bank.printErr(res)
                respond({ status = "error", message = bank.trimErr(res) })
            end
        end
    elseif command == "withdraw" then
        if not ATMs[id] then
            respond({ status = "error", message = "Not logged In, Invalid Client" })
        else
            local status, res = pcall(withdraw, data.amount, data.cardID)
            if (status) then
                respond({ status = "success" })
            else
                bank.printErr(res)
                respond({ status = "error", message = bank.trimErr(res) })
            end
        end
    elseif command == "transfer" then
        if not ATMs[id] then
            respond({ status = "error", message = "Not logged In, Invalid Client" })
        else
            local status, res = pcall(transfer, data.amount, data.fromCardID, data.toCardID)
            if (status) then
                respond({ status = "success" })
            else
                bank.printErr(res)
                respond({ status = "error", message = bank.trimErr(res) })
            end
        end
    elseif command == "alert" then
        -- alerts could never throw an error (to my knowledge)
        alert("ATM " .. id .. ": " .. data.message)
        respond({ status = "success" })
    elseif command == "registerATM" then
        -- registering an ATM might throw an error during updates
        local status, res = pcall(registerATM, id, "ONLINE", data.files)
        if (status) then
            -- check if there are files
            if (res) then
                -- reject registration
                if (res == -1) then
                    -- client not recognized
                    respond({ status = "unknown" })
                else
                    -- updates, send back files
                    respond({ status = "updates", files = res })
                end
            else
                -- send back success
                respond({ status = "success" })
            end
        else
            bank.printErr(res)
            respond({ status = "error", message = bank.trimErr(res) })
        end
    elseif command == "search" then
        if not ATMs[id] then
            respond({ status = "error", message = "Not logged In, Invalid Client" })
        else
            local status, res = pcall(getUser, data.cardID)
            if status then
                print("Found user " .. res.name)
                respond({
                    status = "success",
                    user = {
                        name = res.name,
                        balance = res.balance,
                    }
                })
            else
                bank.printErr(res)
                respond({ status = "error", message = "Card not registered." })
            end
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
        if event[1] == "timer" and event[2] == beatTimer then
            handled = true
            -- time to braodcase another heartbeat
            bank.broadcast("beat")

            -- reset timer
            beatTimer = os.startTimer(beatTime)
        elseif event[1] == "terminate" then
            handled = true
            print("terminating...")
            -- close all sockets
            bank.closeAllConnections()
        end
    end
    return handled
end

local function main()
    redstone.setAnalogOutput("bottom", 15)

    -- get updated files
    getUpdatedFiles()

    -- run any start methods for the APIs
    bank.onStart()

    print("Server started...")

    -- start a beat timer
    beatTimer = os.startTimer(beatTime)
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
