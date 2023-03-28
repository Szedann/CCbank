local bank = require("atmBankApi")
local completion = require "cc.completion"
local UUIDPath = "info"

bank.setLoggingEnabled(false)
bank.setCryptoLoggingEnabled(true)

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
screenSelectWindow.write("  T  ")
screenSelectWindow.setCursorPos(8, 1)
screenSelectWindow.write("  L  ")
screenSelectWindow.setCursorPos(14, 1)
screenSelectWindow.write("  R  ")
screenSelectWindow.setCursorPos(20, 1)
screenSelectWindow.write("  A  ")

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
        userInfoWindow.setCursorPos(1, 3)
        userInfoWindow.write("--coming soon--")
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

-- Function to display a message on the monitor
local function displayMessage(message, skip)
    print(message)
    updateUserUI()
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
    if table.getn(recipientList) < 1 then
        print("Loading recipient list...")
        getUsers(function(response)
            recipientList = response.users
            if (table.getn(recipientList) <= 0) then
                print("No recipients found.")
                screen = "main"
                return
            else
                updateUI()
            end
        end)
    else
        print("Select a recipient:")
        print("0: Cancel")
        for i, user in pairs(recipientList) do
            print(i .. ": " .. user.name)
        end
        local input = tonumber(read())
        local recipient = nil
        if input == 0 then
            screen = "main"
        elseif input > 0 and input <= table.getn(recipientList) then
            recipient = recipientList[input]
        else
            print("Invalid input")
        end
        print("Recipient selected: " .. recipient.name)
        print("Input amount (c)")
        local amount = tonumber(read())
        mainWindow.clear()
        mainWindow.setCursorPos(1, 1)
        print("Confirm transfer:")
        print("Recipient: " .. recipient.name)
        print("Amount: " .. amount .. "c")
        local confirmation = read(nil, nil, function(text) return completion.choice(text, { "yes", "no" }) end)
        mainWindow.clear()
        mainWindow.setCursorPos(1, 1)
        if confirmation == "yes" then
            bank.request("transfer", { fromCardID = UUID, toCardID = recipient.UUID, amount = amount },
                function(response)
                    if response.status == "success" then
                        print("Transferred " .. amount .. " to " .. recipient.name .. ".")
                    else
                        print("Failed to transfer " .. amount .. " to " .. recipient.name .. ".")
                    end
                    print("Press any key to continue...")
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
        end
    end
end


function updateUser(callback)
    if (bank.logging) then print(UUID) end
    displayMessage("Reading Card. Please Wait...", false)
    bank.getUser(UUID,
        function(response)
            user = response
            if not user then
                displayMessage("Invalid card. Please remove card and insert a valid card.", false)
            else
                screen = "main"
            end
            updateUserUI()
            if (callback) then callback() end
        end
    )
end

function updateUI()
    mainWindow.clear()
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
                if x < 6 then
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

local function main()
    -- run any start methods for the APIs
    bank.onStart()
    bank.registerATM(function()
        updateUser(function()
            mainWindow.clear()
            screen = "main"
        end)
    end)
end

-- intialize, passing main and this onEvent function as the entry listener
bank.initialize(main, onEvent)
