--[[
    Global Pet Sniper Network (Lumin Hub Style)
    คำแนะนำ:
    1. นำ URL Firebase ของคุณมาใส่ในบรรทัด FIREBASE_URL
    2. รันสคริปต์นี้ทิ้งไว้เพื่อดูรายการสัตว์ที่เครือข่าย Scout ค้นพบแบบ Real-time
    3. กด Join เพื่อวาร์ปไปจับสัตว์ได้เลย หรือกด Auto Hop เพื่อให้มันวาร์ปเองเมื่อเจอสัตว์ระดับที่ต้องการ
--]]

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
-- 🛑 ป้องกันบัควาร์ปรัวๆ ตอนสคริปต์รันจาก Auto Execute
if not game:IsLoaded() then 
    game.Loaded:Wait() 
end

local player = Players.LocalPlayer
if not player then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    player = Players.LocalPlayer
end

-- รอจนกว่าตัวละครจะเกิดสมบูรณ์
if not player.Character then
    player.CharacterAdded:Wait()
end
task.wait(3) -- หน่วงให้ UI ของเกมโหลดเสร็จจริงๆ

-- ออโต้บายพาสหน้า Loading (กดปุ่มรัวๆ เมื่อเจอหน้า LoadingScreenMenu)
task.spawn(function()
    local vim = game:GetService("VirtualInputManager")
    while task.wait(0.5) do
        -- เช็คว่ามีโมเดลหน้าโหลดโผล่มาในแมพหรือไม่
        if workspace:FindFirstChild("LoadingScreenMenu") then
            pcall(function() vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game) end)
            task.wait(0.05)
            pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        end
    end
end)

local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local FIREBASE_URL = "https://pet-finder-7daac-default-rtdb.asia-southeast1.firebasedatabase.app/pets.json" -- 🔴 ใส่ URL Firebase ตรงนี้
local AUTO_HOP_ENABLED = false
local AUTO_BUY_ENABLED = true -- 🎯 ซื้อสัตว์ที่ตั้งเป้าหมายไว้อัตโนมัติเมื่ออยู่ในเซิร์ฟเวอร์
local isRunning = true -- 🛑 ตัวแปรควบคุมการทำงานของสคริปต์
local isCurrentlyBuying = false -- 🟢 ล็อคระบบวาร์ป หากตัวละครกำลังวาร์ปไปซื้อสัตว์ในแมพอยู่
local isHopping = false -- 🔴 ล็อคระบบไม่ให้วาร์ปซ้ำซ้อนจนเกมรวน
local lastAttemptedJobId = nil -- 🔵 เก็บ jobId ล่าสุดที่เพิ่งพยายามวาร์ปไป
local blacklistedServers = {} -- 🚫 บล็อคเซิร์ฟที่คนเต็มหรือเข้าไม่ได้

local canAutoHop = false -- 🛡️ ป้องกันการ Hop รัวๆ ตอนสคริปต์เพิ่งโหลด
task.spawn(function()
    -- รอให้ Map และ WildPetSpawns โหลดให้เสร็จก่อน
    local map = workspace:WaitForChild("Map", 30)
    if map then
        map:WaitForChild("WildPetSpawns", 15)
    end
    -- หน่วงเวลาเผื่อให้ระบบ Auto Buy ได้ล็อคเป้าหมายก่อน (ถ้ามีสัตว์ในเซิร์ฟนี้)
    task.wait(5)
    canAutoHop = true
end)

local CONFIG_FILE = "PetSniperConfig.json"

local TARGET_PETS = {
    ["Unicorn"] = true,
    ["Golden Dragonfly"] = true,
    ["Black Dragon"] = false,
    ["Monkey"] = false,
    ["Robin"] = false,
    ["Bee"] = false,
    ["Ice Serpent"] = false,
    ["Raccoon"] = false
}

local TARGET_RARITIES = { 
    ["Mythic"] = true,  
    ["Super"] = true, 
    ["Legendary"] = true
}

local REMOVE_TREES_ENABLED = false
local TREE_REMOVAL_MODE = "Hide" -- 🔴 "Hide" (ซ่อนต้นไม้ ให้เดินทะลุได้) หรือ "Delete" (ลบทิ้งไปเลย)

local function saveConfig()
    if writefile then
        pcall(function()
            local data = { pets = TARGET_PETS, rarities = TARGET_RARITIES, removeTrees = REMOVE_TREES_ENABLED, treeMode = TREE_REMOVAL_MODE, autoHop = AUTO_HOP_ENABLED, autoBuy = AUTO_BUY_ENABLED }
            writefile(CONFIG_FILE, HttpService:JSONEncode(data))
        end)
    end
end

if isfile and isfile(CONFIG_FILE) and readfile then
    pcall(function()
        local data = HttpService:JSONDecode(readfile(CONFIG_FILE))  
        if data.pets then for k, v in pairs(data.pets) do if TARGET_PETS[k] ~= nil then TARGET_PETS[k] = v end end end
        if data.rarities then for k, v in pairs(data.rarities) do if TARGET_RARITIES[k] ~= nil then TARGET_RARITIES[k] = v end end end
        if data.removeTrees ~= nil then REMOVE_TREES_ENABLED = data.removeTrees end
        if data.treeMode ~= nil then TREE_REMOVAL_MODE = data.treeMode end
        if data.autoHop ~= nil then AUTO_HOP_ENABLED = data.autoHop end
        if data.autoBuy ~= nil then AUTO_BUY_ENABLED = data.autoBuy end
    end)
else
    saveConfig()
end

local req = (syn and syn.request) or (http and http.request) or http_request or request
if not req then
    warn("Exploit ของคุณไม่รองรับ HTTP Request")
    return
end

-- สร้างหน้าจอ UI สไตล์ Lumin Hub
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "LuminStylePetSniper"
ScreenGui.Parent = RunService:IsStudio() and Players.LocalPlayer:WaitForChild("PlayerGui") or CoreGui

for _, gui in pairs(ScreenGui.Parent:GetChildren()) do
    if gui.Name == "LuminStylePetSniper" and gui ~= ScreenGui then gui:Destroy() end
end

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 400)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -200)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -20, 0, 40)
Title.Position = UDim2.new(0, 15, 0, 10)
Title.BackgroundTransparency = 1
Title.Text = "Pet Sniper Network"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 22
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -45, 0, 15)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 16
CloseBtn.Parent = MainFrame
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

CloseBtn.MouseButton1Click:Connect(function()
    isRunning = false
    if ScreenGui then ScreenGui:Destroy() end
end)

local SettingsBtn = Instance.new("TextButton")
SettingsBtn.Size = UDim2.new(0, 75, 0, 30)
SettingsBtn.Position = UDim2.new(1, -125, 0, 15)
SettingsBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
SettingsBtn.Text = "⚙ Config"
SettingsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SettingsBtn.Font = Enum.Font.GothamBold
SettingsBtn.TextSize = 14
SettingsBtn.Parent = MainFrame
Instance.new("UICorner", SettingsBtn).CornerRadius = UDim.new(0, 6)

-- Settings Panel
local SettingsFrame = Instance.new("Frame")
SettingsFrame.Size = UDim2.new(1, 0, 1, 0)
SettingsFrame.Position = UDim2.new(0, 0, 0, 0)
SettingsFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
SettingsFrame.Visible = false
SettingsFrame.ZIndex = 10
SettingsFrame.Parent = MainFrame
Instance.new("UICorner", SettingsFrame).CornerRadius = UDim.new(0, 8)

local SettingsTitle = Instance.new("TextLabel")
SettingsTitle.Size = UDim2.new(1, -20, 0, 40)
SettingsTitle.Position = UDim2.new(0, 15, 0, 10)
SettingsTitle.BackgroundTransparency = 1
SettingsTitle.Text = "⚙ Settings"
SettingsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
SettingsTitle.TextSize = 22
SettingsTitle.Font = Enum.Font.GothamBold
SettingsTitle.TextXAlignment = Enum.TextXAlignment.Left
SettingsTitle.ZIndex = 11
SettingsTitle.Parent = SettingsFrame

local SettingsCloseBtn = Instance.new("TextButton")
SettingsCloseBtn.Size = UDim2.new(0, 30, 0, 30)
SettingsCloseBtn.Position = UDim2.new(1, -45, 0, 15)
SettingsCloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
SettingsCloseBtn.Text = "X"
SettingsCloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SettingsCloseBtn.Font = Enum.Font.GothamBold
SettingsCloseBtn.TextSize = 16
SettingsCloseBtn.ZIndex = 11
SettingsCloseBtn.Parent = SettingsFrame
Instance.new("UICorner", SettingsCloseBtn).CornerRadius = UDim.new(0, 6)

SettingsBtn.MouseButton1Click:Connect(function() SettingsFrame.Visible = true end)
SettingsCloseBtn.MouseButton1Click:Connect(function() SettingsFrame.Visible = false end)

local AutoBuyBtn = Instance.new("TextButton")
AutoBuyBtn.Size = UDim2.new(0, 120, 0, 30)
AutoBuyBtn.Position = UDim2.new(1, -175, 0, 15)
AutoBuyBtn.BackgroundColor3 = AUTO_BUY_ENABLED and Color3.fromRGB(50, 200, 100) or Color3.fromRGB(30, 30, 30)
AutoBuyBtn.Text = AUTO_BUY_ENABLED and "Auto Buy: ON" or "Auto Buy: OFF"
AutoBuyBtn.TextColor3 = AUTO_BUY_ENABLED and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
AutoBuyBtn.Font = Enum.Font.GothamSemibold
AutoBuyBtn.TextSize = 14
AutoBuyBtn.ZIndex = 11
AutoBuyBtn.Parent = SettingsFrame
Instance.new("UICorner", AutoBuyBtn).CornerRadius = UDim.new(0, 6)

AutoBuyBtn.MouseButton1Click:Connect(function()
    AUTO_BUY_ENABLED = not AUTO_BUY_ENABLED
    if AUTO_BUY_ENABLED then
        AutoBuyBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
        AutoBuyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        AutoBuyBtn.Text = "Auto Buy: ON"
    else
        AutoBuyBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        AutoBuyBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
        AutoBuyBtn.Text = "Auto Buy: OFF"
    end
end)

-- Two Columns for Settings
local PetsScroll = Instance.new("ScrollingFrame")
PetsScroll.Size = UDim2.new(0.5, -20, 1, -110)
PetsScroll.Position = UDim2.new(0, 15, 0, 55)
PetsScroll.BackgroundTransparency = 1
PetsScroll.ScrollBarThickness = 2
PetsScroll.ZIndex = 11
PetsScroll.Parent = SettingsFrame
Instance.new("UIListLayout", PetsScroll).Padding = UDim.new(0, 5)

local RaritiesScroll = Instance.new("ScrollingFrame")
RaritiesScroll.Size = UDim2.new(0.5, -20, 1, -110)
RaritiesScroll.Position = UDim2.new(0.5, 5, 0, 55)
RaritiesScroll.BackgroundTransparency = 1
RaritiesScroll.ScrollBarThickness = 2
RaritiesScroll.ZIndex = 11
RaritiesScroll.Parent = SettingsFrame
Instance.new("UIListLayout", RaritiesScroll).Padding = UDim.new(0, 5)

local function createToggle(parent, text, isToggled, callback)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, -10, 0, 30)
    Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    Frame.ZIndex = 11
    Frame.Parent = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 4)
    
    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -40, 1, 0)
    Label.Position = UDim2.new(0, 10, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = Color3.fromRGB(200, 200, 200)
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 12
    Label.Parent = Frame
    
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0, 20, 0, 20)
    Btn.Position = UDim2.new(1, -30, 0.5, -10)
    Btn.BackgroundColor3 = isToggled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
    Btn.Text = ""
    Btn.ZIndex = 12
    Btn.Parent = Frame
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 4)
    
    local state = isToggled
    Btn.MouseButton1Click:Connect(function()
        state = not state
        Btn.BackgroundColor3 = state and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
        callback(state)
    end)
end

local PetsHeader = Instance.new("TextLabel")
PetsHeader.Size = UDim2.new(1, 0, 0, 20)
PetsHeader.BackgroundTransparency = 1
PetsHeader.Text = "🎯 TARGET PETS"
PetsHeader.TextColor3 = Color3.fromRGB(150, 150, 255)
PetsHeader.Font = Enum.Font.GothamBold
PetsHeader.TextSize = 14
PetsHeader.TextXAlignment = Enum.TextXAlignment.Left
PetsHeader.ZIndex = 12
PetsHeader.Parent = PetsScroll

local RaritiesHeader = Instance.new("TextLabel")
RaritiesHeader.Size = UDim2.new(1, 0, 0, 20)
RaritiesHeader.BackgroundTransparency = 1
RaritiesHeader.Text = "🎯 TARGET RARITIES"
RaritiesHeader.TextColor3 = Color3.fromRGB(150, 150, 255)
RaritiesHeader.Font = Enum.Font.GothamBold
RaritiesHeader.TextSize = 14
RaritiesHeader.TextXAlignment = Enum.TextXAlignment.Left
RaritiesHeader.ZIndex = 12
RaritiesHeader.Parent = RaritiesScroll

for k, v in pairs(TARGET_PETS) do
    createToggle(PetsScroll, k, v, function(s) TARGET_PETS[k] = s; saveConfig() end)
end

for k, v in pairs(TARGET_RARITIES) do
    createToggle(RaritiesScroll, k, v, function(s) TARGET_RARITIES[k] = s; saveConfig() end)
end

local TreeToggleFrame = Instance.new("Frame")
TreeToggleFrame.Size = UDim2.new(1, -30, 0, 30)
TreeToggleFrame.Position = UDim2.new(0, 15, 1, -45)
TreeToggleFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
TreeToggleFrame.ZIndex = 11
TreeToggleFrame.Parent = SettingsFrame
Instance.new("UICorner", TreeToggleFrame).CornerRadius = UDim.new(0, 4)

local TreeLabel = Instance.new("TextLabel")
TreeLabel.Size = UDim2.new(1, -120, 1, 0)
TreeLabel.Position = UDim2.new(0, 10, 0, 0)
TreeLabel.BackgroundTransparency = 1
TreeLabel.Text = "🌳 Remove Trees"
TreeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
TreeLabel.Font = Enum.Font.GothamBold
TreeLabel.TextSize = 12
TreeLabel.TextXAlignment = Enum.TextXAlignment.Left
TreeLabel.ZIndex = 12
TreeLabel.Parent = TreeToggleFrame

local TreeModeBtn = Instance.new("TextButton")
TreeModeBtn.Size = UDim2.new(0, 60, 0, 20)
TreeModeBtn.Position = UDim2.new(1, -95, 0.5, -10)
TreeModeBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
TreeModeBtn.Text = TREE_REMOVAL_MODE
TreeModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TreeModeBtn.Font = Enum.Font.GothamSemibold
TreeModeBtn.TextSize = 11
TreeModeBtn.ZIndex = 12
TreeModeBtn.Parent = TreeToggleFrame
Instance.new("UICorner", TreeModeBtn).CornerRadius = UDim.new(0, 4)

TreeModeBtn.MouseButton1Click:Connect(function()
    TREE_REMOVAL_MODE = (TREE_REMOVAL_MODE == "Hide") and "Delete" or "Hide"
    TreeModeBtn.Text = TREE_REMOVAL_MODE
    saveConfig()
end)

local TreeBtn = Instance.new("TextButton")
TreeBtn.Size = UDim2.new(0, 20, 0, 20)
TreeBtn.Position = UDim2.new(1, -30, 0.5, -10)
TreeBtn.BackgroundColor3 = REMOVE_TREES_ENABLED and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
TreeBtn.Text = ""
TreeBtn.ZIndex = 12
TreeBtn.Parent = TreeToggleFrame
Instance.new("UICorner", TreeBtn).CornerRadius = UDim.new(0, 4)

TreeBtn.MouseButton1Click:Connect(function()
    REMOVE_TREES_ENABLED = not REMOVE_TREES_ENABLED
    TreeBtn.BackgroundColor3 = REMOVE_TREES_ENABLED and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
    saveConfig()
end)

task.spawn(function()
    -- ฟังก์ชันซ่อนต้นไม้แทนการลบทิ้ง เพื่อให้สคริปต์ฟาร์มผลไม้อื่นๆ ยังทำงานได้
    local function hideModel(model)
        -- เช็คว่าถ้าซ่อนไปแล้วจะได้ไม่ทำซ้ำให้เปลือง CPU
        if model:GetAttribute("IsHidden") then return end
        model:SetAttribute("IsHidden", true)
        
        for _, obj in pairs(model:GetDescendants()) do
            if obj:IsA("BasePart") then
                obj.Transparency = 1
                obj.CanCollide = false
            elseif obj:IsA("Decal") or obj:IsA("Texture") then
                obj.Transparency = 1
            elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                obj.Enabled = false
            end
        end
    end

    local function handleTreeRemoval(model)
        if TREE_REMOVAL_MODE == "Delete" then
            model:Destroy()
        else
            hideModel(model)
        end
    end

    local function cleanTrees()
        pcall(function()
            local Gardens = workspace:FindFirstChild("Gardens")
            if Gardens then
                for _, plot in pairs(Gardens:GetChildren()) do
                    local plants = plot:FindFirstChild("Plants")
                    if plants then
                        for _, plant in pairs(plants:GetChildren()) do
                            if plant:IsA("Model") then handleTreeRemoval(plant) end
                        end
                    end
                end
            end
            
            local Map = workspace:FindFirstChild("Map")
            local Trees = Map and Map:FindFirstChild("Trees")
            if Trees then
                for _, v in pairs(Trees:GetChildren()) do
                    if v:IsA("Model") and (v.Name == "Tree" or string.find(v.Name, "Tree")) then
                        handleTreeRemoval(v)
                    end
                end
            end
        end)
    end

    -- ดักจับการเกิดของต้นไม้แบบ Real-time ทันทีที่เซิร์ฟเวอร์ส่งมา
    workspace.DescendantAdded:Connect(function(desc)
        if not REMOVE_TREES_ENABLED then return end
        
        if desc:IsA("Model") and (desc.Name == "Tree" or string.find(desc.Name, "Tree")) then
            local p = desc.Parent
            if p and p.Name == "Trees" and p.Parent and p.Parent.Name == "Map" then
                task.defer(function() handleTreeRemoval(desc) end)
                return
            end
        end
        
        if desc:IsA("Model") then
            local p = desc.Parent
            if p and p.Name == "Plants" then
                local plot = p.Parent
                if plot and plot.Parent and plot.Parent.Name == "Gardens" then
                    task.defer(function() handleTreeRemoval(desc) end)
                    return
                end
            end
        end
    end)

    -- ลูปเก็บกวาดหลงเหลือเผื่อระบบหลุด (เปลี่ยนเป็น 5 วิเพื่อลดการกิน CPU เพราะเรามีระบบดักจับ Real-time แล้ว)
    while isRunning do
        if REMOVE_TREES_ENABLED then
            cleanTrees()
        end
        task.wait(5)
    end
end)

local AutoHopBtn = Instance.new("TextButton")
AutoHopBtn.Size = UDim2.new(0, 120, 0, 30)
AutoHopBtn.Position = UDim2.new(1, -255, 0, 15)
AutoHopBtn.BackgroundColor3 = AUTO_HOP_ENABLED and Color3.fromRGB(100, 50, 255) or Color3.fromRGB(30, 30, 30)
AutoHopBtn.Text = AUTO_HOP_ENABLED and "Auto Hop: ON" or "Auto Hop: OFF"
AutoHopBtn.TextColor3 = AUTO_HOP_ENABLED and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
AutoHopBtn.Font = Enum.Font.GothamSemibold
AutoHopBtn.TextSize = 14
AutoHopBtn.Parent = MainFrame
Instance.new("UICorner", AutoHopBtn).CornerRadius = UDim.new(0, 6)

AutoHopBtn.MouseButton1Click:Connect(function()
    AUTO_HOP_ENABLED = not AUTO_HOP_ENABLED
    if AUTO_HOP_ENABLED then
        AutoHopBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 255) -- เปิดเป็นสีม่วง
        AutoHopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        AutoHopBtn.Text = "Auto Hop: ON"
    else
        AutoHopBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        AutoHopBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
        AutoHopBtn.Text = "Auto Hop: OFF"
        isHopping = false -- เพิ่มบรรทัดนี้เพื่อให้สคริปต์หลุดจากการค้างสถานะ Hopping เมื่อผู้ใช้กดปิด
    end
    saveConfig()
end)

local ScrollingFrame = Instance.new("ScrollingFrame")
ScrollingFrame.Size = UDim2.new(1, -30, 1, -70)
ScrollingFrame.Position = UDim2.new(0, 15, 0, 55)
ScrollingFrame.BackgroundTransparency = 1
ScrollingFrame.ScrollBarThickness = 3
ScrollingFrame.Parent = MainFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Padding = UDim.new(0, 10)
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Parent = ScrollingFrame

local RarityColors = {
    ["Legendary"] = Color3.fromRGB(255, 150, 50),
    ["Mythic"] = Color3.fromRGB(255, 50, 50),
    ["Super"] = Color3.fromRGB(50, 255, 255)
}

local function formatTimeAgo(timestamp)
    local diff = os.time() - timestamp
    if diff < 0 then diff = 0 end
    if diff < 60 then return diff .. "s ago" end
    return math.floor(diff/60) .. "m ago"
end

local function createPetCard(jobId, data)
    local Card = Instance.new("Frame")
    Card.Name = jobId
    Card.Size = UDim2.new(1, 0, 0, 95)
    Card.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
    Card.Parent = ScrollingFrame
    Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 6)
    
    local UIStroke = Instance.new("UIStroke")
    UIStroke.Color = Color3.fromRGB(40, 40, 45)
    UIStroke.Parent = Card

    local color = RarityColors[data.rarity] or Color3.fromRGB(150, 100, 255)

    local NameLabel = Instance.new("TextLabel")
    NameLabel.Size = UDim2.new(1, -100, 0, 25)
    NameLabel.Position = UDim2.new(0, 15, 0, 10)
    NameLabel.BackgroundTransparency = 1
    NameLabel.Text = data.petName or "Unknown"
    NameLabel.TextColor3 = color
    NameLabel.TextSize = 20
    NameLabel.Font = Enum.Font.GothamBold
    NameLabel.TextXAlignment = Enum.TextXAlignment.Left
    NameLabel.Parent = Card

    local InfoLabel = Instance.new("TextLabel")
    InfoLabel.Size = UDim2.new(0.7, 0, 0, 50)
    InfoLabel.Position = UDim2.new(0, 15, 0, 35)
    InfoLabel.BackgroundTransparency = 1
    InfoLabel.RichText = true
    
    local hexColor = string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
    
    -- อัปเดตเวลาเรียลไทม์
    task.spawn(function()
        while isRunning and Card.Parent do
            local safeRarity = data.rarity or "Unknown"
            local safePlayers = data.players or 0
            local safeMaxPlayers = data.maxPlayers or 0
            local safeTime = formatTimeAgo(data.timestamp or os.time())
            
            InfoLabel.Text = string.format("• Rarity: <b><font color='%s'>%s</font></b>\n• Have: x1\n• Players: %d/%d\n• Found: %s", 
                hexColor, safeRarity, safePlayers, safeMaxPlayers, safeTime)
            task.wait(1)
        end
    end)
    InfoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    InfoLabel.TextSize = 13
    InfoLabel.Font = Enum.Font.RobotoMono
    InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    InfoLabel.TextYAlignment = Enum.TextYAlignment.Top
    InfoLabel.Parent = Card

    local JoinBtn = Instance.new("TextButton")
    JoinBtn.Size = UDim2.new(0, 80, 0, 30)
    JoinBtn.Position = UDim2.new(1, -95, 0.5, -15)
    JoinBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    JoinBtn.Text = "Join"
    JoinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    JoinBtn.Font = Enum.Font.Gotham
    JoinBtn.TextSize = 14
    JoinBtn.Parent = Card
    Instance.new("UICorner", JoinBtn).CornerRadius = UDim.new(0, 6)

    JoinBtn.MouseButton1Click:Connect(function()
        JoinBtn.Text = "Joining..."
        isHopping = true -- ล็อคสถานะวาร์ปไว้ด้วย จะได้ไม่โดน Auto Hop แย่งซีน
        lastAttemptedJobId = jobId
        TeleportService:TeleportToPlaceInstance(data.placeId or game.PlaceId, jobId, Players.LocalPlayer)
    end)
    
    return Card
end

-- 🔴 ดักจับ Event เมื่อวาร์ปไม่สำเร็จ (เช่น Server Full)
TeleportService.TeleportInitFailed:Connect(function(plr, teleportResult, errorMessage)
    if lastAttemptedJobId then
        blacklistedServers[lastAttemptedJobId] = true -- แบล็คลิสต์เซิร์ฟนี้ไว้ จะได้ไม่พยายามเข้าซ้ำ
        lastAttemptedJobId = nil
    end
    
    -- 🛡️ ปิด Error ก่อน แล้วค่อยปลดล็อคให้ Hop ต่อได้ (ทำแบบลำดับขั้นตอนเดียวกัน ไม่ขนาน)
    task.spawn(function()
        -- ขั้นที่ 1: ปิดหน้าต่าง Error ก่อน
        task.wait(0.5)
        pcall(function() game:GetService("GuiService"):ClearError() end)
        local vim = game:GetService("VirtualInputManager")
        pcall(function() vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game) end)
        task.wait(0.1)
        pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game) end)
        
        -- ขั้นที่ 2: รอให้ Error หายออกจากจอจริงๆ ก่อน
        task.wait(2.5)
        
        -- ขั้นที่ 3: ปลดล็อคให้ไปหาเซิร์ถัดไปได้
        isHopping = false
        if AUTO_HOP_ENABLED and AutoHopBtn then
            AutoHopBtn.Text = "Auto Hop: ON"
            AutoHopBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 255)
        end
    end)
end)

-- อัปเดตข้อมูลทุกๆ 5 วินาที
local function refreshList()
    pcall(function()
        local res = req({
            Url = FIREBASE_URL,
            Method = "GET"
        })
        
        if res.StatusCode == 200 and res.Body ~= "null" then
            local pets = HttpService:JSONDecode(res.Body)
            
            local sortedPets = {}
            for key, data in pairs(pets) do
                -- กรองข้อมูลขยะที่ไม่มีชื่อสัตว์ทิ้งไป
                if type(data) == "table" and data.petName and data.timestamp then
                    -- โชว์เฉพาะสัตว์ที่มีชีพจรล่าช้าไม่เกิน 2 นาที (120 วินาที)
                    if os.time() - data.timestamp <= 120 then
                    -- 🕵️‍♂️ ถ้านี่คือเซิร์ฟเวอร์ที่เรากำลังอยู่ ให้เราเช็คก่อนว่าสัตว์ยังมีอยู่ไหม
                    if data.jobId == game.JobId then
                        local map = workspace:FindFirstChild("Map")
                        if map then
                            local wildPets = map:FindFirstChild("WildPetSpawns")
                            local found = false
                            if wildPets then
                                for _, model in pairs(wildPets:GetChildren()) do
                                    local name = string.match(model.Name, "WildPet_([^_]+)")
                                    if name == data.petName then
                                        found = true
                                        break
                                    end
                                end
                            end
                            if not found then
                                -- 🧹 สัตว์ไม่อยู่แล้ว! ลบข้อมูลผีดิบทิ้งเลย ป้องกันคนอื่นวาร์ปมาเก้อ
                                pcall(function()
                                    local deleteUrl = string.gsub(FIREBASE_URL, "%.json", "/" .. key .. ".json")
                                    req({Url = deleteUrl, Method = "DELETE"})
                                end)
                                continue -- ข้ามตัวนี้ไปเลย ไม่ต้องเอามาโชว์แล้ว
                            end
                        end
                    end
                    table.insert(sortedPets, {jobId = data.jobId or key, data = data})
                end
                end
            end
            
            -- เรียงลำดับตัวที่ใหม่สุดขึ้นก่อน
            table.sort(sortedPets, function(a, b) return a.data.timestamp > b.data.timestamp end)
            
            local currentPets = {}
            for i, item in ipairs(sortedPets) do
                currentPets[item.jobId] = true
                local existingCard = ScrollingFrame:FindFirstChild(item.jobId)
                
                if existingCard then
                    existingCard.LayoutOrder = i -- เลื่อนการ์ดเก่าไปตำแหน่งใหม่ถ้ามีอันใหม่แทรก
                else
                    local card = createPetCard(item.jobId, item.data)
                    card.LayoutOrder = i
                end
                
                -- ระบบ Auto Hop! (ย้ายออกมานอก else เพื่อให้วาร์ปได้ทันทีแม้รายชื่อจะเคยโหลดมาแล้ว)
                local isTarget = false
                if TARGET_RARITIES[item.data.rarity] then isTarget = true end
                if TARGET_PETS[item.data.petName] then 
                    isTarget = true 
                else
                    -- ลบเว้นวรรคออกก่อนเทียบ ป้องกันบัคชื่อ Golden Dragonfly
                    local checkName = string.gsub(tostring(item.data.petName), "%s+", "")
                    for k, v in pairs(TARGET_PETS) do
                        if v and string.gsub(k, "%s+", "") == checkName then
                            isTarget = true
                            break
                        end
                    end
                end
                
                -- ตรวจสอบด้วยว่าไม่ใช่เซิร์ฟเวอร์ที่เรากำลังเล่นอยู่ปัจจุบัน (ป้องกันวาร์ปซ้ำที่เดิม)
                -- 🟢 เพิ่มเงื่อนไข `not isCurrentlyBuying` เพื่อบังคับให้รอแฮกซื้อในเซิร์ฟนี้ให้เสร็จก่อนค่อยบินหนี
                if AUTO_HOP_ENABLED and canAutoHop and isTarget and item.jobId ~= game.JobId and not isCurrentlyBuying and not isHopping and not blacklistedServers[item.jobId] then
                    isHopping = true
                    lastAttemptedJobId = item.jobId
                    local hopTargetJobId = item.jobId -- เก็บไว้ใช้ใน timeout
                    AutoHopBtn.Text = "Hopping!"
                    AutoHopBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
                    task.spawn(function()
                        local currentJobId = game.JobId
                        pcall(function()
                            TeleportService:TeleportToPlaceInstance(item.data.placeId or game.PlaceId, item.jobId, Players.LocalPlayer)
                        end)
                        
                        -- 🛡️ Timeout: รอ 10 วิ ถ้า JobId ยังไม่เปลี่ยน = วาร์ปล้มเหลว (รองรับกรณี TeleportInitFailed ไม่ยิง)
                        task.wait(10)
                        if game.JobId == currentJobId and isHopping then
                            blacklistedServers[hopTargetJobId] = true
                            lastAttemptedJobId = nil
                            isHopping = false
                            if AUTO_HOP_ENABLED and AutoHopBtn then
                                AutoHopBtn.Text = "Auto Hop: ON"
                                AutoHopBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 255)
                            end
                        end
                    end)
                    break
                end
            end
            
            -- ลบการ์ดเก่าที่ไม่อยู่ในระบบแล้วออกไป
            for _, child in pairs(ScrollingFrame:GetChildren()) do
                if child:IsA("Frame") and not currentPets[child.Name] then
                    child:Destroy()
                end
            end
        end
    end)
end

task.spawn(function()
    while isRunning do
        refreshList()
        task.wait(5)
    end
end)

print("🚀 Pet Sniper Network Loaded!")

-- 🟢 ระบบ Auto Buy ภายในเซิร์ฟเวอร์
task.spawn(function()
    while isRunning and task.wait(0.5) do
        if AUTO_BUY_ENABLED or AUTO_HOP_ENABLED then
            local map = workspace:FindFirstChild("Map")
            local wildPets = map and map:FindFirstChild("WildPetSpawns")
            if wildPets then
                local CustomRarities = {
                    ["Raccoon"] = "Super", ["BlackDragon"] = "Super", ["Black Dragon"] = "Super",
                    ["IceSerpent"] = "Super", ["Ice Serpent"] = "Super", ["Robin"] = "Legendary", ["Bee"] = "Legendary",
                    ["GoldenDragonfly"] = "Mythic", ["Golden Dragonfly"] = "Mythic",
                    ["Unicorn"] = "Mythic", ["Monkey"] = "Mythic"
                }
                local RarityPriority = {
                    ["Mythic"] = 80, ["Super"] = 100, ["Legendary"] = 60
                }
                
                local targetsFound = {}
                
                -- สแกนและเก็บข้อมูลสัตว์เป้าหมายทั้งหมดในเซิร์ฟ
                for _, model in pairs(wildPets:GetChildren()) do
                    local petName = string.match(model.Name, "WildPet_([^_]+)")
                    if petName then
                        local rty = CustomRarities[petName] or "Unknown"
                        
                        local isTargetBuy = false
                        if TARGET_RARITIES[rty] then isTargetBuy = true end
                        if TARGET_PETS[petName] then 
                            isTargetBuy = true
                        else
                            local checkNameBuy = string.gsub(tostring(petName), "%s+", "")
                            for k, v in pairs(TARGET_PETS) do
                                if v and string.gsub(k, "%s+", "") == checkNameBuy then
                                    isTargetBuy = true
                                    break
                                end
                            end
                        end
                        
                        -- เช็คว่าเป็นเป้าหมายไหม (ชื่อตรง หรือ ระดับแรร์ตรง)
                        if isTargetBuy then
                            local p = RarityPriority[rty] or 0
                            table.insert(targetsFound, {model = model, name = petName, priority = p})
                        end
                    end
                end
                
                -- เรียงลำดับความสำคัญ (ตัวแรร์ที่สุดจะถูกซื้อก่อน)
                table.sort(targetsFound, function(a, b) return a.priority > b.priority end)
                
                -- ล็อคระบบการวาร์ป เพื่อไม่ให้เกมย้ายเซิร์ฟระหว่างที่เรากำลังจะไปขโมยของ
                if #targetsFound > 0 then
                    isCurrentlyBuying = true
                    
                    -- 🛑 บังคับรอให้ตัวละครโหลดเสร็จก่อนค่อยวิ่งไปซื้อ ป้องกันบัคที่มันรีบข้ามเซิร์ฟหนีขณะเรากำลังโหลดเข้าเกม
                    local char = Players.LocalPlayer.Character
                    if not char or not char:FindFirstChild("HumanoidRootPart") then
                        char = Players.LocalPlayer.CharacterAdded:Wait()
                    end
                    local rootPart = char:WaitForChild("HumanoidRootPart", 10)
                    
                    if rootPart then
                        -- เริ่มวิ่งไปซื้อทีละตัวตามลำดับ
                        for _, target in ipairs(targetsFound) do
                            local model = target.model
                            local petName = target.name
                            
                            if not model:IsDescendantOf(workspace) then continue end
                            
                            local petRoot = model:FindFirstChild("RootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                            if petRoot then
                                -- บังคับปลดแช่แข็ง
                                rootPart.Anchored = false 
                                
                                local prompt = petRoot:FindFirstChild("BuyPrompt") or model:FindFirstChildWhichIsA("ProximityPrompt", true)
                                if prompt then
                                    prompt.Enabled = true
                                    prompt.RequiresLineOfSight = false
                                    prompt.HoldDuration = 0
                                    prompt.MaxActivationDistance = 50 -- ขยายพอประมาณ
                                    prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
                                    
                                    while model:IsDescendantOf(workspace) do
                                        -- วาร์ปเกาะติดสัตว์รัวๆ แบบเดิม (ตอนนี้เราใช้ Remote ซื้อแล้ว ไม่ต้องกลัวปุ่มบัคอีกต่อไป)
                                        rootPart.Velocity = Vector3.new(0, 0, 0)
                                        local backPos = petRoot.Position - (petRoot.CFrame.LookVector * 3) + Vector3.new(0, 1, 0)
                                        rootPart.CFrame = CFrame.new(backPos, petRoot.Position + Vector3.new(0, 1, 0))
                                        
                                        pcall(function() fireproximityprompt(prompt) end)
                                        
                                        -- พยายามหาจอบหรืออาวุธในตัว แล้วสวมใส่เพื่อป้องกันคนแย่ง
                                        local humanoid = char:FindFirstChild("Humanoid")
                                        local weapon = char:FindFirstChild("Shovel") or player.Backpack:FindFirstChild("Shovel") or player.Backpack:FindFirstChildOfClass("Tool")
                                        if humanoid and weapon and weapon.Parent ~= char then
                                            humanoid:EquipTool(weapon)
                                        end
                                        
                                        -- กดตีรัวๆ (ยิง Remote ข้ามอนิเมชั่น)
                                        if weapon then
                                            pcall(function()
                                                local Networking = require(game:GetService("ReplicatedStorage").SharedModules.Networking)
                                                if Networking and Networking.Shovel and Networking.Shovel.HitPlayer then
                                                    Networking.Shovel.SwingShovel:Fire(weapon)
                                                    -- สแกนหาคนรอบๆ ในระยะ 20 Studs แล้วยิงดาเมจใส่ทุกคน
                                                    for _, otherPlayer in ipairs(game:GetService("Players"):GetPlayers()) do
                                                        if otherPlayer ~= player then
                                                            local otherChar = otherPlayer.Character
                                                            local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
                                                            if otherRoot and (otherRoot.Position - rootPart.Position).Magnitude <= 20 then
                                                                Networking.Shovel.HitPlayer:Fire(otherPlayer.UserId)
                                                            end
                                                        end
                                                    end
                                                end
                                            end)
                                        end
                                        
                                        pcall(function()
                                            local Networking = require(game:GetService("ReplicatedStorage").SharedModules.Networking)
                                            if Networking and Networking.Pets and Networking.Pets.WildPetTame then
                                                Networking.Pets.WildPetTame:Fire(model)
                                            end
                                        end)
                                        task.wait(0.1) -- ยิงรัวทุกๆ 0.1 วิ จนกว่าสัตว์จะหายไป
                                    end
                                    
                                    if not model:IsDescendantOf(workspace) then
                                        pcall(function()
                                            local safeJobId = string.gsub(tostring(game.JobId), "[^%w]", "")
                                            local safePetName = string.gsub(tostring(petName), "[^%w]", "")
                                            local key = safeJobId .. "_" .. safePetName
                                            
                                            local deleteUrl = string.gsub(FIREBASE_URL, "%.json", "/" .. key .. ".json")
                                            req({Url = deleteUrl, Method = "DELETE"})
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end
                
                -- ปลดล็อคระบบการวาร์ป อนุญาตให้ Auto Hop ทำงานได้ตามปกติ
                isCurrentlyBuying = false
            end
        end
    end
end)
