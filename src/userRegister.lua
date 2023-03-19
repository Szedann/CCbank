local bank = require("atmBankApi")

bank.initialize()

local function registerUser(name)
    local data = bank.request("register", { name = name })
    if (data.status == "success") then
        print("Registered user " .. name)
    else
        print("Failed to register user " .. name)
        print(data.message)
    end
end

local w, h = term.getSize()
term.setBackgroundColor(colors.red)
term.setCursorPos(1, 1)
term.clearLine()
print("Account Creation Terminal")
term.setBackgroundColor(colors.black)
local window = window.create(term.current(), 1, 2, w, h - 1)
term.redirect(window)

while true do
    local e = { os.pullEvent() }
    if e[1] == "modem_message" then
        bank.handleModemRequest(e)
    end
    print("Input account name to register:")
    local username = io.stdin:read()
    registerUser(username)
end
