local bank = require("atmBankApi")
local UUIDPath = "info"

bank.logging = false

local user = nil
local UUID = fs.open("/" .. UUIDPath, "r").readAll()

-- screen variables
local DisplayedMessage = "Unknown error"
local screen = "main" -- insert, info, withdraw, deposit, transfer, balance(main)
local skipInfo = true -- true if user can continue from current info screen
local w, h = term.getSize()

-- user info window
local userInfoWindow = window.create(term.current(), 1, 1, w, 3)
local userInfoWindowW, userInfoWindowH = userInfoWindow.getSize()

-- main window
local mainWindow = window.create(term.current(), 1, userInfoWindowH + 1, w, h - userInfoWindowH)
term.redirect(mainWindow)

-- call to update UI state
local function updateUI()
    if (user) then
        userInfoWindow.clear()
        userInfoWindow.setCursorPos(1, 1)
        userInfoWindow.write("Welcome, " .. user.name)
        userInfoWindow.setCursorPos(1, 2)
        userInfoWindow.write("Balance: " .. user.balance)
        userInfoWindow.setCursorPos(1, 3)
        userInfoWindow.write(string.rep("-", userInfoWindowW))
        userInfoWindow.setBackgroundColor(colors.orange)
        userInfoWindow.setTextColor(colors.white)
        userInfoWindow.setCursorPos(w, 1)
        userInfoWindow.write("R")
        userInfoWindow.setBackgroundColor(colors.black)
        userInfoWindow.setTextColor(colors.white)
    end
    mainWindow.clear()
end

-- Function to display a message on the monitor
local function displayMessage(message, skip)
    print(message)
    updateUI()
end

local function updateUser()
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
            updateUI()
        end
    )
end

-- Event driven handler for listening to events
local withdrawAmountString = "0"

local function onEvent(event)
    -- call api listners first
    local handled = bank.onEvent(event)

    -- if event wasn't handled, try and handle it
    if (not handled) then
        if event[1] == "mouse_click" then
            local x, y = event[3], event[4]
            if (x == w and y == 1) then
                updateUser()
            end
            if (bank.logging) then print("Touch: " .. screen) end
            if screen == "info" and skipInfo then
                handled = true
                -- go back to the main menu only if the user can skip this info
                screen = "main"
            elseif screen == "main" then
            end
            updateUI()
        end
    end
    return handled
end

local function main()
    -- run any start methods for the APIs
    bank.onStart()
    bank.registerATM()
end

-- intialize, passing main and this onEvent function as the entry listener
bank.initialize(main, onEvent)
