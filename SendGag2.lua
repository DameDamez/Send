if not game:IsLoaded() then game.Loaded:Wait() end
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Auto Gift (Standalone)",
    SubTitle = "FB : Nattawat",
    TabWidth = 140,
    Size = UDim2.fromOffset(480, 380),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Gifting", Icon = "gift" })
}

local targetUsername = ""
local category = "Seeds"
local items = {"Gold"}
local amount = 999999
local isLooping = false
local isGifting = false

Tabs.Main:AddInput("TargetUser", {
    Title = "Target Username",
    Default = "",
    Placeholder = "Enter exact username (e.g. benze_423)",
    Numeric = false,
    Finished = false,
    Callback = function(Value)
        targetUsername = Value
    end
})

Tabs.Main:AddDropdown("GiftCategory", {
    Title = "Category",
    Values = {"Seeds", "Fruits"},
    Multi = false,
    Default = 1,
    Callback = function(Value)
        category = Value
    end
})

local dynamicItemsList = {"Gold", "Rainbow", "Dragon's Breath"}
task.spawn(function()
    pcall(function()
        if not game:IsLoaded() then game.Loaded:Wait() end
        local SM = game:GetService("ReplicatedStorage"):WaitForChild("SharedModules", 5)
        if not SM then return end
        local seedData = SM:WaitForChild("SeedData", 5)
        if not seedData then return end
        
        for _, v in pairs(require(seedData)) do
            if v.SeedName then 
                local fName = string.gsub(v.SeedName, " Seed", "")
                if not table.find(dynamicItemsList, fName) then
                    table.insert(dynamicItemsList, fName)
                end
            end
        end
        table.sort(dynamicItemsList)
    end)
end)

Tabs.Main:AddDropdown("GiftItems", {
    Title = "Items to Send",
    Description = "Select what you want to send",
    Values = dynamicItemsList,
    Multi = true,
    Default = {"Gold"},
    Callback = function(Value)
        items = {}
        for k, v in pairs(Value) do
            if v then table.insert(items, k) end
        end
    end
})

Tabs.Main:AddInput("AmountLimit", {
    Title = "Amount Limit",
    Description = "Leave blank to send all items in backpack",
    Default = "",
    Numeric = true,
    Finished = false,
    Callback = function(Value)
        amount = tonumber(Value) or 999999
    end
})

local function performGift()
    local ok, Networking = pcall(function()
        return require(game:GetService("ReplicatedStorage"):WaitForChild("SharedModules"):WaitForChild("Networking"))
    end)
    local SendBatch = ok and Networking and Networking.Mailbox and Networking.Mailbox.SendBatch
    
    if not SendBatch then
        Fluent:Notify({Title="Error", Content="Networking module not ready!", Duration=3})
        return false
    end

    if targetUsername == "" then
        Fluent:Notify({Title="Error", Content="Please enter target username", Duration=3})
        return false
    end
    
    local targetId
    pcall(function()
        targetId = game.Players:GetUserIdFromNameAsync(targetUsername)
    end)
    
    if not targetId then
        Fluent:Notify({Title="Error", Content="Player not found!", Duration=3})
        return false
    end
    
    if #items == 0 then
        Fluent:Notify({Title="Error", Content="Please select at least 1 item", Duration=3})
        return false
    end
    
    local batch = {}
    local totalCount = 0
    local backpack = game:GetService("Players").LocalPlayer:FindFirstChild("Backpack")
    
    for _, itemName in ipairs(items) do
        local finalCount = 0
        if backpack then
            local tool = backpack:FindFirstChild(itemName)
            if tool then
                local realCount = tool:GetAttribute("Count")
                if realCount and type(realCount) == "number" then
                    finalCount = math.min(amount, realCount)
                else
                    finalCount = math.min(amount, 1)
                end
            end
        end
        if finalCount > 0 then
            table.insert(batch, {
                Category = category,
                ItemKey = itemName,
                Count = finalCount
            })
            totalCount = totalCount + finalCount
        end
    end
    
    if #batch > 0 then
        pcall(function()
            SendBatch:Fire(targetId, batch, "")
        end)
        Fluent:Notify({Title="Success", Content="Sent " .. totalCount .. " items!", Duration=2})
        return true
    else
        return true -- return true so loop continues waiting for items
    end
end

Tabs.Main:AddButton({
    Title = "Send Once",
    Description = "Send selected items one time manually",
    Callback = function()
        if isGifting then return end
        isGifting = true
        task.spawn(function()
            performGift()
            isGifting = false
        end)
    end
})

local LoopToggle = Tabs.Main:AddToggle("AutoLoop", {Title = "Enable Auto Loop", Default = false })

LoopToggle:OnChanged(function()
    isLooping = LoopToggle.Value
    if isLooping then
        Fluent:Notify({Title="Loop Started", Content="Will send items every 1.5s", Duration=3})
        task.spawn(function()
            while isLooping do
                isGifting = true
                local success = performGift()
                if not success then
                    LoopToggle:SetValue(false)
                    break
                end
                task.wait(1.5)
            end
            isGifting = false
        end)
    else
        Fluent:Notify({Title="Loop Stopped", Content="Auto Gift Loop Stopped", Duration=3})
    end
end)

Window:SelectTab(1)
Fluent:Notify({
    Title = "Loaded",
    Content = "Standalone Auto Gift is ready!",
    Duration = 3
})
