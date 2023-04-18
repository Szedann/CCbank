local bank = require("atmBankApi")
local completion = require "cc.completion"
local UUIDPath = "info"

bank.setLoggingEnabled(false)
bank.setCryptoLoggingEnabled(false)

local user = nil
local UUID = fs.open("/" .. UUIDPath, "r").readAll()

-- screen variables
local DisplayedMessage = "Unknown error"
local screen = "main" -- insert, info, withdraw, deposit, transfer, balance(main)
local skipInfo = true -- true if user can continue from current info screen
local w, h = term.getSize()

-- user info window
local userInfoWindow = window.create(term.current(), 1, 1, w, 4)
local userInfoWindowW, userInfoWindowH = userInfoWindow.getSize()

-- Screen selection window
local screenSelectWindow = window.create(term.current(), 1, h, w, 1)
screenSelectWindow.setBackgroundColor(colors.orange)
screenSelectWindow.setTextColor(colors.white)
screenSelectWindow.setCursorPos(2, 1)
screenSelectWindow.write(" TRANSFER ")
screenSelectWindow.setCursorPos(15, 1)
screenSelectWindow.write(" CURRENCY ")

-- main window
local mainWindow = window.create(term.current(), 1, userInfoWindowH + 1, w, h - userInfoWindowH - 1)
term.redirect(mainWindow)

-- call to update UI state
local function updateUserUI()
    if (user) then
        userInfoWindow.clear()
        userInfoWindow.setCursorPos(1, 1)
        userInfoWindow.write("Welcome, " .. user.name)
        userInfoWindow.setCursorPos(1, 2)
        userInfoWindow.write("Balance: " .. user.balance .. "C")
        userInfoWindow.setCursorPos(1, 4)
        userInfoWindow.write(string.rep("=", userInfoWindowW))
        userInfoWindow.setBackgroundColor(colors.orange)
        userInfoWindow.setTextColor(colors.white)
        userInfoWindow.setBackgroundColor(colors.black)
        userInfoWindow.setTextColor(colors.white)
    else
        userInfoWindow.clear()
        userInfoWindow.setCursorPos(1, 1)
        userInfoWindow.write("Couldn't find user")
    end
end

local function getUsers(callback)
    bank.request("getUsers", {},
        function(response)
            callback(response)
        end
    )
end

local recipientList = {}
local function transferScreen()
    mainWindow.clear()
    mainWindow.setCursorPos(1, 1)
    print("       ==TRANSFER==")
    if #recipientList < 1 then
        print("Loading recipient list...")
        getUsers(function(response)
            recipientList = response.users
            if (#recipientList <= 0) then
                print("No recipients found.")
                screen = "main"
                return
            else
                updateUI()
            end
        end)
    else
        print("Select a recipient:")
        local names = {}
        for i, v in ipairs(recipientList) do
            names[i] = v.name
        end
        local input = read(nil, nil, function(text) return completion.choice(text, names) end)
        local recipient = nil
        for i, v in ipairs(recipientList) do
            if v.name == input then
                recipient = v
                break
            end
        end
        if recipient == nil then
            screen = "main"
            updateUI()
            print("Invalid recipient.")
            return
        end
        mainWindow.clear()
        mainWindow.setCursorPos(1, 1)
        print("Recipient selected: " .. recipient.name)
        print("Input amount (c)")
        local amount = tonumber(read())
        if (amount == nil or amount <= 0) then
            screen = "main"
            updateUI()
            print("Invalid amount.")
            return
        end
        mainWindow.clear()
        mainWindow.setCursorPos(1, 1)
        print("Confirm transfer:")
        print("Recipient: " .. recipient.name)
        print("Amount: " .. amount .. "c")
        print("")
        mainWindow.setTextColor(colors.orange)
        print("Confirm? (yes/no)")
        mainWindow.setTextColor(colors.white)
        local confirmation = read(nil, nil, function(text) return completion.choice(text, { "yes", "no" }) end)
        mainWindow.clear()
        mainWindow.setCursorPos(1, 1)
        if confirmation == "yes" then
            bank.request("transfer", { fromCardID = UUID, toCardID = recipient.UUID, amount = amount },
                function(response)
                    if response.status == "success" then
                        mainWindow.setTextColor(colors.green)
                        print("Transferred " .. amount .. " to " .. recipient.name .. ".")
                    else
                        mainWindow.setTextColor(colors.red)
                        print("Failed to transfer " .. amount .. " to " .. recipient.name .. ".")
                    end
                    mainWindow.setTextColor(colors.white)
                    print("\nPress any key to continue...")
                    os.sleep(1)
                    os.pullEvent("key")
                    screen = "main"
                    updateUI()
                    updateUser()
                    recipient = nil
                    recipientList = {}
                end)
        else
            screen = "main"
            recipient = nil
            recipientList = {}
            updateUI()
            print("Transfer cancelled.")
        end
    end
end


function updateUser(callback)
    if (bank.logging) then print(UUID) end
    print("Reading Card. Please Wait...")
    bank.getUser(UUID,
        function(response)
            user = response
            if not user then
                print("Invalid card.")
            else
                screen = "main"
            end
            updateUserUI()
            if (callback) then callback() end
        end
    )
    updateUI()
end

function updateUI()
    mainWindow.clear()
    mainWindow.setCursorPos(1, 1)
    if screen == "transfer" then
        transferScreen()
    end
end

-- Event driven handler for listening to events

local function onEvent(event)
    -- call api listners first
    local handled = bank.onEvent(event)

    -- if event wasn't handled, try and handle it
    if (not handled) then
        if event[1] == "mouse_click" then
            local x, y = event[3], event[4]
            if (bank.logging) then print("Touch: " .. screen) end
            if y == h then
                if x < 13 then
                    screen = "transfer"
                    updateUI()
                end
            end
            if screen == "info" and skipInfo then
                handled = true
                -- go back to the main menu only if the user can skip this info
                screen = "main"
            elseif screen == "main" then
            end
            updateUserUI()
        end
    end
    return handled
end

userInfoWindow.setCursorPos(1, 1)
userInfoWindow.write("Loading...")

local function onDisconnect()
    mainWindow.clear()
    print("Disconnected... Trying to reconnect...")
end

local function main()
    -- run any start methods for the APIs
    bank.onStart()
    print("Connecting to Server...")
    bank.registerATM({
        "atmBankApi.lua",
        "bankApi.lua",
        "userRegister.lua"
    }, function(status)
        if (status == "updates") then
            print("Updating Card...")
        elseif (status == "unknown") then
            print("Card not Registered. Please contact support.")
        elseif (status == "success") then
            updateUser(function()
                mainWindow.clear()
                screen = "main"
            end)
        end
    end)
end

-- intialize, passing main and this onEvent function as the entry listener
bank.initialize(main, onEvent, onDisconnect)
