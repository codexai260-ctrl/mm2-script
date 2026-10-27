_G.AutoFarm = true
_G.FarmSpeed = 25

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Studio-only testing helper. Place this LocalScript in StarterPlayerScripts.
-- It does not run in published games or simulate AFK input.
if not RunService:IsStudio() then
	return
end

local LocalPlayer = Players.LocalPlayer
local Connections = {}
local ActiveTween = nil
local Stopped = false

local function Cleanup()
	if Stopped then
		return
	end

	Stopped = true

	if ActiveTween then
		ActiveTween:Cancel()
		ActiveTween = nil
	end

	for _, connection in ipairs(Connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end

	table.clear(Connections)
end

local function GetCharacter()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end

	return character, humanoid, root
end

local function GetActiveMap()
	local normal = workspace:FindFirstChild("Normal")
	return normal and normal:FindFirstChild("Map")
end

local function GetCoinContainer()
	local map = GetActiveMap()
	if not map then
		return nil, nil
	end

	local container = map:FindFirstChild("CoinContainer", true)

	if not container then
		local candidate = workspace:FindFirstChild("CoinContainer", true)

		if candidate and candidate:IsDescendantOf(map) then
			container = candidate
		end
	end

	return container, map
end

local function IsCollectible(instance)
	if not instance:IsA("BasePart") then
		return false
	end

	local name = string.lower(instance.Name)

	return name == "coin"
		or name == "candy"
		or name == "candycorn"
		or string.find(name, "candy", 1, true) ~= nil
end

local function GetNearestCollectible(container, root)
	local nearest = nil
	local shortestDistance = math.huge

	for _, instance in ipairs(container:GetDescendants()) do
		if IsCollectible(instance) and instance:IsDescendantOf(container) then
			local distance = (instance.Position - root.Position).Magnitude

			if distance < shortestDistance then
				shortestDistance = distance
				nearest = instance
			end
		end
	end

	return nearest, shortestDistance
end

local function GetBagStatus()
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	local mainGui = playerGui and playerGui:FindFirstChild("MainGui")
	local gameFrame = mainGui and mainGui:FindFirstChild("Game")
	local coinBag = gameFrame and gameFrame:FindFirstChild("CoinBag")
	local container = coinBag and coinBag:FindFirstChild("Container")
	local coins = container and container:FindFirstChild("Coins")

	if not coins then
		return false, nil, nil
	end

	local text = coins:IsA("TextLabel") or coins:IsA("TextButton")
		and coins.Text or nil

	if typeof(text) ~= "string" then
		if coins:IsA("TextLabel") or coins:IsA("TextButton") then
			text = coins.Text
		else
			return false, nil, nil
		end
	end

	local current, maximum = string.match(text, "(%d+)%s*/%s*(%d+)")

	if not current or not maximum then
		return false, nil, nil
	end

	current = tonumber(current)
	maximum = tonumber(maximum)

	return current >= maximum, current, maximum
end

local function GetSafeCFrame()
	local safePoint = workspace:FindFirstChild("FarmSafePoint", true)

	if safePoint and safePoint:IsA("BasePart") then
		return CFrame.new(safePoint.Position + Vector3.new(0, 3, 0))
	end

	local lobby = workspace:FindFirstChild("Lobby", true)

	if lobby then
		for _, instance in ipairs(lobby:GetDescendants()) do
			if instance:IsA("SpawnLocation") then
				return CFrame.new(instance.Position + Vector3.new(0, 3, 0))
			end
		end
	end

	-- Fallback for isolated Studio testing.
	return CFrame.new(0, 300, 0)
end

local function MoveTo(targetCFrame)
	local character, humanoid, root = GetCharacter()

	if not character or Stopped or not _G.AutoFarm then
		return false
	end

	local speed = math.max(tonumber(_G.FarmSpeed) or 25, 1)
	local distance = (targetCFrame.Position - root.Position).Magnitude

	if distance < 1 then
		return true
	end

	local duration = distance / speed

	local tween = TweenService:Create(
		root,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ CFrame = targetCFrame }
	)

	ActiveTween = tween
	tween:Play()

	while tween.PlaybackState == Enum.PlaybackState.Playing
		and _G.AutoFarm
		and not Stopped do

		task.wait(0.05)

		local currentCharacter, currentHumanoid, currentRoot = GetCharacter()

		if currentCharacter ~= character
			or currentHumanoid ~= humanoid
			or currentRoot ~= root then
			tween:Cancel()
			break
		end
	end

	if ActiveTween == tween then
		ActiveTween = nil
	end

	return not Stopped and _G.AutoFarm
		and tween.PlaybackState == Enum.PlaybackState.Completed
end

local function WaitForNextRound(previousMap)
	while _G.AutoFarm and not Stopped do
		task.wait(0.5)

		local currentMap = GetActiveMap()
		local full = GetBagStatus()

		if not currentMap or currentMap ~= previousMap or not full then
			return
		end
	end
end

-- Stop and release the event connections when AutoFarm is disabled.
table.insert(Connections, RunService.Heartbeat:Connect(function()
	if not _G.AutoFarm then
		Cleanup()
	end
end))

task.spawn(function()
	while _G.AutoFarm and not Stopped do
		local character, humanoid, root = GetCharacter()

		if not character then
			task.wait(0.5)
			continue
		end

		local container, currentMap = GetCoinContainer()

		if not currentMap or not container then
			task.wait(0.5)
			continue
		end

		local full = GetBagStatus()

		if full then
			MoveTo(GetSafeCFrame())
			WaitForNextRound(currentMap)
			continue
		end

		local collectible = GetNearestCollectible(container, root)

		if collectible and collectible.Parent then
			local targetPosition = collectible.Position
				+ Vector3.new(0, 2.5, 0)

			local targetCFrame = CFrame.new(
				targetPosition,
				targetPosition + root.CFrame.LookVector
			)

			MoveTo(targetCFrame)
			task.wait(0.1)
		else
			task.wait(0.25)
		end
	end

	Cleanup()
end)