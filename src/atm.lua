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
    local total = 0
    for slot, item in pairs(interfaceStorage.list()) do
        for key, coin in pairs(bank.coins) do
            if (item.nbt == coin.nbt) then
                interfaceStorageMoney.detail[slot] = {
                    coin = key,
                    count = item.count,
                }
                total = total + item.count * coin.rate
            end
        end
    end

    local changed = interfaceStorageMoney.total ~= total
    if (changed) then
        interfaceStorageMoney.total = total
    end
    return changed
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
    updateUI()
end

local function updateUser()
    local UUID = bank.getUUID(cardDrive)
    if (bank.logging) then print(UUID) end
    displayMessage("Reading Card. Please Wait...", false)
    bank.getUser(UUID,
        function(response)
            currentUser = response
            if not currentUser then
                displayMessage("Invalid card. Please remove card and insert a valid card.", false)
            else
                screen = "main"
            end
            updateUI()
        end
    )
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
        return
    end
    bank.request("deposit", { name = currentUser.name, amount = amount, cardID = currentUser.cardID },
        function(response)
            if (response.status == "success") then
                -- update user balance locally
                currentUser.balance = currentUser.balance + amount
                for slot, value in pairs(coinSlots) do
                    interfaceStorage.pushItems("back", slot, value.count)
                end
                if (bank.logging) then print("Deposited " .. amount .. "C into " .. currentUser.name .. "'s account") end
                displayMessage("Deposited " .. amount .. "C")
            else
                displayMessage("Failed to deposit " .. amount .. "C")
                if (bank.logging) then
                    print("Failed to deposit " ..
                        amount .. "C into " .. currentUser.name .. "'s account")
                end
            end
        end
    )
end


local function withdraw(amount)
    checkInternalStorage()
    local coinSlots = countCoins(internalStorageMoney, amount)
    if (coinSlots == 0) then
        if (bank.logging) then print("Not enough money in internal storage") end
        bank.alertServer("Not enough money in internal storage")
        displayMessage("Not enough money in internal storage")
        return
    end

    bank.request("withdraw", { name = currentUser.name, amount = amount, cardID = currentUser.cardID },
        function(response)
            if (response.status == "success") then
                -- update user balance locally
                currentUser.balance = currentUser.balance - amount
                for slot, value in pairs(coinSlots) do
                    internalStorage.pushItems("front", slot, value.count)
                end
                displayMessage("Withdrew " .. amount .. "C")
                if (bank.logging) then print("Withdrew " .. amount .. "C from " .. currentUser.name .. "'s account") end
            else
                displayMessage("Failed to withdraw " .. amount .. "C")
                if (bank.logging) then
                    print("Failed to withdraw " ..
                        amount .. "C from " .. currentUser.name .. "'s account")
                end
            end
        end
    )
end

-- Event driven handler for listening to events
local withdrawAmountString = "0"
local spurCnt = 9999
local bevelCnt = 9999
local sprocketCnt = 9999
local cogCnt = 9999
local crownCnt = 9999
local sunCnt = 9999
--[[
Spurs
beVels
sprocKets
Cogs
cRowns
sUns]]
local withdraw
local function onEvent(event)
    -- if there was a change to the total in the interface
    if (checkInterfaceStorage()) then
        -- update the UI
        updateUI()
    end
    -- call api listners first
    local handled = bank.onEvent(event)

    -- if event wasn't handled, try and handle it
    if (not handled) then
        if event[1] == "disk" then
            handled = true
            updateUser()
        elseif event[1] == "disk_eject" then
            handled = true
            currentUser = nil
            screen = "insert"
            updateUI()
        elseif event[1] == "monitor_touch" then
            if (bank.logging) then print("Touch: " .. screen) end
            if screen == "info" and skipInfo then
                handled = true
                -- go back to the main menu only if the user can skip this info
                screen = "main"
            elseif screen == "main" then
                handled = true
                local x, y = event[3], event[4]
                if (bank.logging) then print(x, y) end
                if y == 4 then
                    ---- remove this
                    print("depositing " .. interfaceStorageMoney.total)
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

                    monitor.setCursorPos(7, 5)
                    monitor.write("S")
                    monitor.setCursorPos(7, 6)
                    monitor.write(tostring(spurCnt))

                    monitor.setCursorPos(7, 7)
                    monitor.write("V")
                    monitor.setCursorPos(7, 8)
                    monitor.write(tostring(bevelCnt))

                    monitor.setCursorPos(7, 9)
                    monitor.write("K")
                    monitor.setCursorPos(7, 10)
                    monitor.write(tostring(sprocketCnt))

                    monitor.setCursorPos(12, 5)
                    monitor.write("C")
                    monitor.setCursorPos(12, 6)
                    monitor.write(tostring(cogCnt))

                    monitor.setCursorPos(12, 7)
                    monitor.write("W")
                    monitor.setCursorPos(12, 8)
                    monitor.write(tostring(crownCnt))

                    monitor.setCursorPos(12, 9)
                    monitor.write("U")
                    monitor.setCursorPos(12, 10)
                    monitor.write(tostring(sunCnt))

                    monitor.setBackgroundColor(colors.gray)
                    monitor.setCursorPos(8, 5)
                    monitor.write("<>")
                    monitor.setCursorPos(8, 7)
                    monitor.write("<>")
                    monitor.setCursorPos(8, 9)
                    monitor.write("<>")
                    monitor.setCursorPos(13, 5)
                    monitor.write("<>")
                    monitor.setCursorPos(13, 7)
                    monitor.write("<>")
                    monitor.setCursorPos(13, 9)
                    monitor.write("<>")
                    monitor.setCursorPos(10, 1)
                    monitor.write("Cancel")
                    monitor.setCursorPos(9, 2)
                    monitor.write("Confirm")
                    monitor.setCursorPos(1, 6)
                    monitor.write("1 2 3")
                    monitor.setCursorPos(1, 7)
                    monitor.write("4 5 6")
                    monitor.setCursorPos(1, 8)
                    monitor.write("7 8 9")
                    monitor.setCursorPos(1, 9)
                    monitor.write("0 < x")
                    monitor.setBackgroundColor(colors.black)
                    withdrawAmountString = "0"
                end
            elseif screen == "withdraw" then
                handled = true
                local x, y = event[3], event[4]

                if y == 5 then
                    withdraw(tonumber(withdrawAmountString))
                    withdrawAmountString = "0"
                end
                print(x, y)
                if y == 7 then
                    if x == 1 then
                        withdrawAmountString = withdrawAmountString .. "1"
                    elseif x == 3 then
                        withdrawAmountString = withdrawAmountString .. "2"
                    elseif x == 5 then
                        withdrawAmountString = withdrawAmountString .. "3"
                    end
                elseif y == 8 then
                    if x == 1 then
                        withdrawAmountString = withdrawAmountString .. "4"
                    elseif x == 3 then
                        withdrawAmountString = withdrawAmountString .. "5"
                    elseif x == 5 then
                        withdrawAmountString = withdrawAmountString .. "6"
                    end
                elseif y == 9 then
                    if x == 1 then
                        withdrawAmountString = withdrawAmountString .. "7"
                    elseif x == 3 then
                        withdrawAmountString = withdrawAmountString .. "8"
                    elseif x == 5 then
                        withdrawAmountString = withdrawAmountString .. "9"
                    end
                elseif y == 10 then
                    if x == 1 then
                        withdrawAmountString = withdrawAmountString .. "0"
                    elseif x == 3 then
                        withdrawAmountString = withdrawAmountString:sub(1, -2)
                    elseif x == 5 then
                        withdrawAmountString = ""
                    end
                end
                monitor.setCursorPos(1, 3)
                monitor.clearLine()
                monitor.write((tonumber(withdrawAmountString) or 0) .. "C")
            end
            updateUI()
        end
    end
    return handled
end

local function main()
    -- run any start methods for the APIs
    bank.onStart()
    -- initalize UI
    monitor.setTextScale(0.5)
    updateUI()
end

-- intialize, passing main and this onEvent function as the entry listener
bank.initialize(main, onEvent)
