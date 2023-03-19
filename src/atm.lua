local bank = require("atmBankApi")
local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
local cardDrive = peripheral.wrap("right")
local interfaceStorage = peripheral.wrap("front")
local internalStorage = peripheral.wrap("back")

local interfaceStorageMoney = {
    total = 0,
    detail = {}
}
local internalStorageMoney = {
    total = 0,
    detail = {}
}

local currentUser = nil

local function countCoins(tab, amount)
    if ((tab.total or 0) < amount) then
        if (bank.logging) then print("Not enough money (" .. tab.total .. " < " .. amount .. ")") end
        return 0
    end
    if (tab.total == amount) then
        return tab.detail
    end

    local result = {}
    local total = 0

    for slot, data in pairs(tab.detail) do
        data.slot = slot
    end

    table.sort(tab.detail, function(a, b) return bank.coins[a.coin].rate > bank.coins[b.coin].rate end)
    for _, data in pairs(tab.detail) do
        local coin = bank.coins[data.coin]
        local count = math.floor((amount - total) / coin.rate)
        if (count > data.count) then
            count = data.count
        end
        if (count > 0) then
            result[data.slot] = {
                coin = data.coin,
                count = count,
            }
            total = total + count * coin.rate
        end
        if (total == amount) then
            break
        end
    end
    return result
end

local function checkInterfaceStorage()
    interfaceStorageMoney.total = 0
    for slot, item in pairs(interfaceStorage.list()) do
        for key, coin in pairs(bank.coins) do
            if (item.nbt == coin.nbt) then
                interfaceStorageMoney.detail[slot] = {
                    coin = key,
                    count = item.count,
                }
                interfaceStorageMoney.total = interfaceStorageMoney.total + item.count * coin.rate
            end
        end
    end
end

local function checkInternalStorage()
    internalStorageMoney.total = 0
    for slot, item in pairs(internalStorage.list()) do
        for key, coin in pairs(bank.coins) do
            if (item.nbt == coin.nbt) then
                internalStorageMoney.detail[slot] = {
                    coin = key,
                    count = item.count,
                }
                internalStorageMoney.total = internalStorageMoney.total + item.count * coin.rate
            end
        end
    end
end

-- screen variables
local DisplayedMessage = "Unknown error"
local screen = "insert" -- insert, info, withdraw, deposit, transfer, balance(main)
local skipInfo = true   -- true if user can continue from current info screen
monitor.setTextScale(0.5)
local w, h = monitor.getSize()

-- call to update UI state
local function updateUI()
    if screen == "info" then
        if (bank.logging) then print("Info: " .. DisplayedMessage) end
        monitor.clear()
        local wrappedErrorMessageLines = require "cc.strings".wrap(DisplayedMessage, w)
        for i, line in ipairs(wrappedErrorMessageLines) do
            monitor.setCursorPos(1, i)
            monitor.write(line)
        end
        -- allow going to the main menu only if user can skip this info
        if skipInfo then
            monitor.setCursorPos(1, h)
            monitor.write("Continue")
        end
    elseif screen == "main" then
        checkInterfaceStorage()
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write(currentUser.name)
        monitor.setCursorPos(1, 2)
        monitor.write("Bal: " .. math.floor(currentUser.balance * 100) / 100 .. "C")
        monitor.setCursorPos(1, 4)
        monitor.write("deposit " .. math.floor(interfaceStorageMoney.total * 100) / 100 .. "C")
        monitor.setCursorPos(1, 5)
        monitor.write("withdraw")
    elseif screen == "insert" then
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write("Insert card")
    end
end

-- Function to display a message on the monitor
local function displayMessage(message, skip)
    if (skip == nil) then skip = true end -- skip defaults to true if not passed

    if (bank.logging) then print("displaying message: " .. message) end
    screen = "info"
    skipInfo = skip
    DisplayedMessage = message or "Unknown error"
end

local function updateUser()
    local UUID = bank.getUUID(cardDrive)
    if (bank.logging) then print(UUID) end
    displayMessage("Reading Card. Please Wait...", false)
    updateUI()
    currentUser = bank.getUser(UUID)
end

local function deposit(amount)
    if (bank.logging) then print("Depositing " .. amount .. "C into " .. currentUser.name .. "'s account") end
    checkInterfaceStorage()
    -- redundant as countCoins achieves this with extra validation
    --[[if interfaceStorageMoney.total < amount then
        if (bank.logging) then print("Not enough money in interface storage")
        displayMessage("Not enough money in interface storage") end
        return false
    end]]
          --
    local coinSlots = countCoins(interfaceStorageMoney, amount)
    if coinSlots == 0 then
        if (bank.logging) then print("Not enough coins to make up " .. amount .. "C") end
        displayMessage("Not enough money in interface storage")
        return false
    end
    local response = bank.request("deposit", { name = currentUser.name, amount = amount, cardID = currentUser.cardID })
    if (response.status == "success") then
        -- update user balance locally
        currentUser.balance = currentUser.balance + amount
        for slot, value in pairs(coinSlots) do
            interfaceStorage.pushItems("back", slot, value.count)
        end
        if (bank.logging) then print("Deposited " .. amount .. "C into " .. currentUser.name .. "'s account") end
        displayMessage("Deposited " .. amount .. "C")
        return true
    else
        displayMessage("Failed to deposit " .. amount .. "C")
        if (bank.logging) then print("Failed to deposit " .. amount .. "C into " .. currentUser.name .. "'s account") end
        return false
    end
end

local function withdraw(amount)
    checkInternalStorage()
    local coinSlots = countCoins(internalStorageMoney, amount)
    if (coinSlots == 0) then
        if (bank.logging) then print("Not enough money in internal storage") end
        bank.alertServer("Not enough money in internal storage")
        displayMessage("Not enough money in internal storage")
        return false
    end
    local response = bank.request("withdraw", { name = currentUser.name, amount = amount, cardID = currentUser.cardID })
    if (response.status == "success") then
        -- update user balance locally
        currentUser.balance = currentUser.balance - amount
        for slot, value in pairs(coinSlots) do
            internalStorage.pushItems("front", slot, value.count)
        end
        displayMessage("Withdrew " .. amount .. "C")
        if (bank.logging) then print("Withdrew " .. amount .. "C from " .. currentUser.name .. "'s account") end
        return true
    else
        displayMessage("Failed to withdraw " .. amount .. "C")
        if (bank.logging) then print("Failed to withdraw " .. amount .. "C from " .. currentUser.name .. "'s account") end
        return false
    end
end

bank.initialize()

-- Main loop to listen for incoming requests
local withdrawAmountString = ""

while true do
    checkInterfaceStorage()
    local e = { os.pullEvent() }
    if e[1] == "modem_message" then
        bank.handleModemRequest(e)
    elseif e[1] == "disk" then
        updateUser()
        if not currentUser then
            displayMessage("Invalid card. Please remove card and insert a valid card.", false)
        else
            screen = "main"
        end
    elseif e[1] == "disk_eject" then
        currentUser = nil
        screen = "insert"
    elseif e[1] == "monitor_touch" then
        if (bank.logging) then print("Touch: " .. screen) end
        if screen == "info" and skipInfo then
            -- go back to the main menu only if the user can skip this info
            screen = "main"
        elseif screen == "main" then
            local x, y = e[3], e[4]
            if (bank.logging) then print(x, y) end
            if y == 4 then
                deposit(interfaceStorageMoney.total)
            elseif y == 5 then
                screen = "withdraw"
                monitor.clear()
                monitor.setCursorPos(1, 1)
                monitor.write("Withdraw")
                monitor.setCursorPos(1, 2)
                monitor.write("Amount:")
                monitor.setCursorPos(1, 3)
                monitor.write((tonumber(withdrawAmountString) or 0) .. "C")
                monitor.setCursorPos(1, 5)
                monitor.write("Confirm")
                monitor.setBackgroundColor(colors.gray)
                monitor.setCursorPos(4, 7)
                monitor.write(" 1 2 3 ")
                monitor.setCursorPos(4, 8)
                monitor.write(" 4 5 6 ")
                monitor.setCursorPos(4, 9)
                monitor.write(" 7 8 9 ")
                monitor.setCursorPos(4, 10)
                monitor.write(" 0 < x ")
                monitor.setBackgroundColor(colors.black)
                withdrawAmountString = "0"
            end
        elseif screen == "withdraw" then
            local x, y = e[3], e[4]

            if y == 5 then
                withdraw(tonumber(withdrawAmountString))
                withdrawAmountString = "0"
            end
            print(x, y)
            if y == 7 then
                if x == 5 then
                    withdrawAmountString = withdrawAmountString .. "1"
                elseif x == 7 then
                    withdrawAmountString = withdrawAmountString .. "2"
                elseif x == 9 then
                    withdrawAmountString = withdrawAmountString .. "3"
                end
            elseif y == 8 then
                if x == 5 then
                    withdrawAmountString = withdrawAmountString .. "4"
                elseif x == 7 then
                    withdrawAmountString = withdrawAmountString .. "5"
                elseif x == 9 then
                    withdrawAmountString = withdrawAmountString .. "6"
                end
            elseif y == 9 then
                if x == 5 then
                    withdrawAmountString = withdrawAmountString .. "7"
                elseif x == 7 then
                    withdrawAmountString = withdrawAmountString .. "8"
                elseif x == 9 then
                    withdrawAmountString = withdrawAmountString .. "9"
                end
            elseif y == 10 then
                if x == 5 then
                    withdrawAmountString = withdrawAmountString .. "0"
                elseif x == 7 then
                    withdrawAmountString = withdrawAmountString:sub(1, -2)
                elseif x == 9 then
                    withdrawAmountString = ""
                end
            end
            monitor.setCursorPos(1, 3)
            monitor.clearLine()
            monitor.write((tonumber(withdrawAmountString) or 0) .. "C")
        end
    end
    updateUI()
end
