local bank = require("atmBankApi")
local UUIDPath = "info"

bank.setLoggingEnabled(true)
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

local recipient = nil
local recipientList = {}
local function transferScreen()
    print("       ==TRANSFER==")
    if not recipient then
        if not recipientList then
            getUsers(function(response)
                recipientList = response
                transferScreen()
            end)
        end
        print("Select a recipient:")
        for i, v in pairs(recipientList) do
            print(i .. ": " .. v.name)
        end
    end
end

local function updateUser(callback)
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

local function updateUI()
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
                end
            end
            if screen == "info" and skipInfo then
                handled = true
                -- go back to the main menu only if the user can skip this info
                screen = "main"
            elseif screen == "main" then
            end
            updateUserUI()
            updateUI()
        end
    end
    return handled
end

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
