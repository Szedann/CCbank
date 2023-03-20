local bank = require("atmBankApi")
local prompt = true -- set to true when terminal should prompt user

local function registerUserCallback(data)
    if (data.status == "success") then
        print("Registered user " .. data.name)
    else
        print("Failed to register user " .. data.name)
        print(data.message)
    end
    -- prompt user for another registration
    prompt = true;
end
local function registerUser(name)
    bank.request("register", { name = name }, registerUserCallback)
end

local function onEvent(event)
    -- call api listners first
    local handled = bank.onEvent(event)

    -- if event wasn't handled, try and handle it
    if (not handled) then

    end
    return handled
end

local function main()
    -- run any start methods for the APIs
    bank.onStart()

    -- setup screen
    local w, h = term.getSize()
    term.setBackgroundColor(colors.red)
    term.setCursorPos(1, 1)
    term.clearLine()
    print("Account Creation Terminal")
    term.setBackgroundColor(colors.black)
    local window = window.create(term.current(), 1, 2, w, h - 1)
    term.redirect(window)

    while true do
        -- polling is no longer required with cryptoNet
        --[[
    local e = { os.pullEvent() }
    if e[1] == "modem_message" then
        bank.handleModemRequest(e)
    end]]
        --

        if (prompt) then
            prompt = false
            print("Input account name to register:")
            local username = io.stdin:read()
            registerUser(username)
        end
    end
end

-- intialize, passing main and this onEvent function as the entry listener
bank.initialize(main, onEvent)
