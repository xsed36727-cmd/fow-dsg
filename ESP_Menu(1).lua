-- ESP_Menu.lua  (NIGHTFALL)
-- ESP с меню в стиле популярных читов для CS (боковые вкладки, секции,
-- переключатели, слайдеры, выбор цвета, конфиги).
-- Для executor/инжектора. Работает только на твоём экране.
--
-- Insert -> открыть/закрыть меню
--
-- Нужно от executor-а: Drawing API (боксы, линии, текст).
-- Chams (подсветка тела) работает и без Drawing.
-- Конфиги: writefile / readfile (папка NightfallESP).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Выгружаем старый экземпляр при повторном запуске
if getgenv and getgenv().Nightfall_Unload then
	pcall(getgenv().Nightfall_Unload)
end

local hasDrawing = (Drawing ~= nil)

-- ====================================================================
-- Настройки (то, что меняется в меню)
-- ====================================================================
local Cfg = {
	enabled = true,
	teamCheck = false,
	maxDist = 2000,
	textSize = 13,

	box = true,
	boxColor = Color3.fromRGB(255, 70, 70),
	boxStyle = "Full",          -- Full / Corner
	boxFill = false,
	boxFillColor = Color3.fromRGB(255, 70, 70),
	boxFillAlpha = 0.15,

	name = true,
	nameColor = Color3.fromRGB(255, 255, 255),
	distance = true,
	distColor = Color3.fromRGB(190, 200, 220),
	health = true,

	skeleton = false,
	skelColor = Color3.fromRGB(255, 255, 255),

	tracers = false,
	tracerColor = Color3.fromRGB(0, 170, 255),
	tracerOrigin = "Bottom",    -- Bottom / Center / Mouse

	chams = false,
	chamsFill = Color3.fromRGB(0, 170, 255),
	chamsTransp = 0.5,
	chamsOutlineOn = true,
	chamsOutline = Color3.fromRGB(255, 255, 255),

	aimbot = false,
	aimKey = "RMB",             -- RMB / LMB / Always
	aimPart = "Head",           -- Head / Chest / Root
	aimFov = 150,
	showFov = true,
	fovColor = Color3.fromRGB(255, 255, 255),
	aimSpeed = 30,              -- 1..100 (100 = мгновенно)
	wallCheck = true,

	snow = false,
	snowAmount = 150,           -- снежинок в секунду
	snowSize = 0.5,
	snowSpeed = 10,             -- скорость падения
	snowWind = 3,               -- боковой ветер (минус = влево)
	snowGlow = 1.0,             -- свечение (0 = выкл)
	jumpCircle = false,
	jumpColor = Color3.fromRGB(0, 140, 255),
	jumpSize = 10,              -- диаметр круга в студах
	jumpTime = 1.2,             -- сколько секунд круг живёт

	nightMode = false,
	nightIntensity = 0.7,       -- 0..1
	nightSky = true,            -- ставить ночное время суток

	snowTint = false,
	snowColor = Color3.fromRGB(200, 225, 255),
	snowIndoor = true,          -- не сыпать снег, если над головой крыша
	snowTexture = "",           -- пусто = встроенная текстура Roblox

	stretch = false,
	stretchX = 1.0,
	stretchY = 0.65,

	watermark = true,
}

local DIR = "NightfallESP"

-- ====================================================================
-- Служебное
-- ====================================================================
local connections = {}
local running = true
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

local function getParent()
	if gethui then
		local ok, h = pcall(gethui)
		if ok and h then return h end
	end
	local ok, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok and cg then return cg end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NightfallESP"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = getParent()

local chamsFolder = Instance.new("Folder")
chamsFolder.Name = "NightfallChams"
chamsFolder.Parent = screenGui.Parent

-- ====================================================================
-- ESP: рисование
-- ====================================================================
local BLACK = Color3.new(0, 0, 0)

local function D(kind, props)
	local d = Drawing.new(kind)
	for k, v in pairs(props) do d[k] = v end
	return d
end

local R15_BONES = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local R6_BONES = {
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local esp = {}     -- [player] = набор Drawing-объектов
local chams = {}   -- [player] = Highlight

local function newESP()
	local e = { all = {} }
	local function reg(d) table.insert(e.all, d) return d end
	e.fill = reg(D("Square", { Filled = true, Thickness = 1, Visible = false }))
	e.boxOut = reg(D("Square", { Filled = false, Thickness = 3, Color = BLACK, Visible = false }))
	e.box = reg(D("Square", { Filled = false, Thickness = 1, Visible = false }))
	e.cornersOut = {}
	e.corners = {}
	for i = 1, 8 do
		e.cornersOut[i] = reg(D("Line", { Thickness = 3, Color = BLACK, Visible = false }))
	end
	for i = 1, 8 do
		e.corners[i] = reg(D("Line", { Thickness = 1, Visible = false }))
	end
	e.name = reg(D("Text", { Center = true, Outline = true, Visible = false }))
	e.dist = reg(D("Text", { Center = true, Outline = true, Visible = false }))
	e.hpBack = reg(D("Square", { Filled = true, Color = BLACK, Visible = false }))
	e.hp = reg(D("Square", { Filled = true, Visible = false }))
	e.tracer = reg(D("Line", { Thickness = 1, Visible = false }))
	e.skel = {}
	for i = 1, 14 do
		e.skel[i] = reg(D("Line", { Thickness = 1, Visible = false }))
	end
	return e
end

local function hideAll(e)
	for _, d in ipairs(e.all) do d.Visible = false end
end

local function removeESP(player)
	local e = esp[player]
	if e then
		for _, d in ipairs(e.all) do pcall(function() d:Remove() end) end
		esp[player] = nil
	end
	local h = chams[player]
	if h then
		h:Destroy()
		chams[player] = nil
	end
end

local function isEnemy(player)
	if not Cfg.teamCheck then return true end
	if not LocalPlayer.Team or not player.Team then return true end
	return player.Team ~= LocalPlayer.Team
end

local function getBox(char, root)
	local head = char:FindFirstChild("Head")
	local topPos = (head and head.Position or (root.Position + Vector3.new(0, 2, 0))) + Vector3.new(0, 0.7, 0)
	local botPos = root.Position - Vector3.new(0, 3.2, 0)
	local top = Camera:WorldToViewportPoint(topPos)
	local bot = Camera:WorldToViewportPoint(botPos)
	if top.Z <= 0 or bot.Z <= 0 then return nil end
	local h = math.abs(bot.Y - top.Y)
	local w = h * 0.55
	local cx = (top.X + bot.X) / 2
	return Vector2.new(cx - w / 2, math.min(top.Y, bot.Y)), Vector2.new(w, h)
end

local function updateChams(player, char, visible)
	local h = chams[player]
	if not (visible and Cfg.chams and char) then
		if h then h.Enabled = false end
		return
	end
	if not h or not h.Parent then
		h = Instance.new("Highlight")
		h.Parent = chamsFolder
		chams[player] = h
	end
	if h.Adornee ~= char then h.Adornee = char end
	h.Enabled = true
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.FillColor = Cfg.chamsFill
	h.FillTransparency = Cfg.chamsTransp
	h.OutlineColor = Cfg.chamsOutline
	h.OutlineTransparency = Cfg.chamsOutlineOn and 0 or 1
end

local function updatePlayer(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local myChar = LocalPlayer.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

	local dist = (myRoot and root) and (myRoot.Position - root.Position).Magnitude or 0
	local visible = Cfg.enabled and root and hum and hum.Health > 0
		and isEnemy(player) and dist <= Cfg.maxDist

	updateChams(player, char, visible)

	if not hasDrawing then return end
	local e = esp[player]
	if not e then
		e = newESP()
		esp[player] = e
	end
	hideAll(e)
	if not visible then return end

	local pos, size = getBox(char, root)
	if not pos then return end
	local x, y, w, h = pos.X, pos.Y, size.X, size.Y

	-- Заливка бокса
	if Cfg.boxFill then
		e.fill.Position = pos
		e.fill.Size = size
		e.fill.Color = Cfg.boxFillColor
		e.fill.Transparency = Cfg.boxFillAlpha
		e.fill.Visible = true
	end

	-- Бокс
	if Cfg.box then
		if Cfg.boxStyle == "Full" then
			e.boxOut.Position = pos
			e.boxOut.Size = size
			e.boxOut.Visible = true
			e.box.Position = pos
			e.box.Size = size
			e.box.Color = Cfg.boxColor
			e.box.Visible = true
		else
			local l = math.min(w, h) * 0.3
			local lines = {
				{ Vector2.new(x, y), Vector2.new(x + l, y) },
				{ Vector2.new(x, y), Vector2.new(x, y + l) },
				{ Vector2.new(x + w, y), Vector2.new(x + w - l, y) },
				{ Vector2.new(x + w, y), Vector2.new(x + w, y + l) },
				{ Vector2.new(x, y + h), Vector2.new(x + l, y + h) },
				{ Vector2.new(x, y + h), Vector2.new(x, y + h - l) },
				{ Vector2.new(x + w, y + h), Vector2.new(x + w - l, y + h) },
				{ Vector2.new(x + w, y + h), Vector2.new(x + w, y + h - l) },
			}
			for i, ln in ipairs(lines) do
				e.cornersOut[i].From = ln[1]
				e.cornersOut[i].To = ln[2]
				e.cornersOut[i].Visible = true
				e.corners[i].From = ln[1]
				e.corners[i].To = ln[2]
				e.corners[i].Color = Cfg.boxColor
				e.corners[i].Visible = true
			end
		end
	end

	-- Имя
	if Cfg.name then
		e.name.Text = player.DisplayName ~= "" and player.DisplayName or player.Name
		e.name.Size = Cfg.textSize
		e.name.Color = Cfg.nameColor
		e.name.Position = Vector2.new(x + w / 2, y - Cfg.textSize - 3)
		e.name.Visible = true
	end

	-- Дистанция
	if Cfg.distance then
		e.dist.Text = math.floor(dist) .. "m"
		e.dist.Size = Cfg.textSize - 1
		e.dist.Color = Cfg.distColor
		e.dist.Position = Vector2.new(x + w / 2, y + h + 2)
		e.dist.Visible = true
	end

	-- Полоска здоровья
	if Cfg.health then
		local f = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
		e.hpBack.Position = Vector2.new(x - 6, y - 1)
		e.hpBack.Size = Vector2.new(4, h + 2)
		e.hpBack.Visible = true
		e.hp.Position = Vector2.new(x - 5, y + h * (1 - f))
		e.hp.Size = Vector2.new(2, h * f)
		e.hp.Color = Color3.fromRGB(255 * (1 - f), 255 * f, 40)
		e.hp.Visible = true
	end

	-- Линия к игроку
	if Cfg.tracers then
		local vp = Camera.ViewportSize
		local origin
		if Cfg.tracerOrigin == "Center" then
			origin = vp / 2
		elseif Cfg.tracerOrigin == "Mouse" then
			origin = UserInputService:GetMouseLocation()
		else
			origin = Vector2.new(vp.X / 2, vp.Y)
		end
		e.tracer.From = origin
		e.tracer.To = Vector2.new(x + w / 2, y + h)
		e.tracer.Color = Cfg.tracerColor
		e.tracer.Visible = true
	end

	-- Скелет
	if Cfg.skeleton then
		local bones = char:FindFirstChild("UpperTorso") and R15_BONES or R6_BONES
		for i, pair in ipairs(bones) do
			local a = char:FindFirstChild(pair[1])
			local b = char:FindFirstChild(pair[2])
			if a and b then
				local pa = Camera:WorldToViewportPoint(a.Position)
				local pb = Camera:WorldToViewportPoint(b.Position)
				if pa.Z > 0 and pb.Z > 0 then
					local ln = e.skel[i]
					ln.From = Vector2.new(pa.X, pa.Y)
					ln.To = Vector2.new(pb.X, pb.Y)
					ln.Color = Cfg.skelColor
					ln.Visible = true
				end
			end
		end
	end
end

-- ====================================================================
-- Меню (UI)
-- ====================================================================
-- ====================================================================
-- Аимбот
-- ====================================================================
local fovCircle
if hasDrawing then
	fovCircle = D("Circle", { Thickness = 1, NumSides = 64, Filled = false, Visible = false })
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function getAimPart(char)
	if Cfg.aimPart == "Head" then
		return char:FindFirstChild("Head")
	elseif Cfg.aimPart == "Chest" then
		return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	end
	return char:FindFirstChild("HumanoidRootPart")
end

-- true, если между камерой и целью нет стены
local function isVisible(part, char)
	local origin = Camera.CFrame.Position
	local ignore = { LocalPlayer.Character }
	for _ = 1, 6 do
		rayParams.FilterDescendantsInstances = ignore
		local res = Workspace:Raycast(origin, part.Position - origin, rayParams)
		if not res then return true end
		local hit = res.Instance
		if hit:IsDescendantOf(char) then return true end
		-- прозрачные и непроходимые для пуль детали пропускаем
		if hit.Transparency >= 0.95 or not hit.CanCollide then
			table.insert(ignore, hit)
		else
			return false
		end
	end
	return false
end

-- Ближайшая к курсору цель в пределах FOV
local function getTarget()
	local mouse = UserInputService:GetMouseLocation()
	local best, bestDist
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and isEnemy(player) then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local part = char and getAimPart(char)
			if hum and part and hum.Health > 0 then
				local sp = Camera:WorldToViewportPoint(part.Position)
				if sp.Z > 0 then
					local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
					if d <= Cfg.aimFov and (not bestDist or d < bestDist) then
						if not Cfg.wallCheck or isVisible(part, char) then
							best, bestDist = part, d
						end
					end
				end
			end
		end
	end
	return best
end

local function aimHeld()
	if Cfg.aimKey == "Always" then return true end
	local btn = Cfg.aimKey == "LMB" and Enum.UserInputType.MouseButton1 or Enum.UserInputType.MouseButton2
	return UserInputService:IsMouseButtonPressed(btn)
end

local function aimbotStep(dt)
	if fovCircle then
		local show = Cfg.aimbot and Cfg.showFov
		fovCircle.Visible = show
		if show then
			fovCircle.Position = UserInputService:GetMouseLocation()
			fovCircle.Radius = Cfg.aimFov
			fovCircle.Color = Cfg.fovColor
		end
	end

	if not Cfg.aimbot or not aimHeld() then return end
	local part = getTarget()
	if not part then return end

	local camCF = Camera.CFrame
	local goal = CFrame.lookAt(camCF.Position, part.Position)
	local alpha = 1
	if Cfg.aimSpeed < 100 then
		alpha = 1 - math.exp(-Cfg.aimSpeed * 0.5 * dt)
	end
	Camera.CFrame = camCF:Lerp(goal, alpha)
end

-- ====================================================================
-- Снег со свечением
-- ====================================================================
local Lighting = game:GetService("Lighting")
local SNOW_DEFAULT_TEX = "rbxasset://textures/particles/sparkles_main.dds"

-- Состояние night mode (объявлено здесь, чтобы снег мог усиливать свечение ночью)
local night = { applied = false, clockSet = false }

local snowPart, snowCore, snowHalo, snowBloom
local snowIndoorTimer = 0
local snowIndoorBlocked = false

local snowRay = RaycastParams.new()
snowRay.FilterType = Enum.RaycastFilterType.Exclude

local function kp(t, v, env)
	return NumberSequenceKeypoint.new(t, v, env or 0)
end

local function makeEmitter(parent)
	local e = Instance.new("ParticleEmitter")
	e.EmissionDirection = Enum.NormalId.Bottom
	e.LightInfluence = 0
	e.LightEmission = 1
	e.Drag = 0
	e.Lifetime = NumberRange.new(8, 11)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.SpreadAngle = Vector2.new(10, 10)
	e.Parent = parent
	return e
end

local function ensureSnow()
	if not snowPart or not snowPart.Parent then
		if snowPart then pcall(function() snowPart:Destroy() end) end
		snowPart = Instance.new("Part")
		snowPart.Name = "NightfallSnow"
		snowPart.Anchored = true
		snowPart.CanCollide = false
		snowPart.CanQuery = false
		snowPart.CanTouch = false
		snowPart.CastShadow = false
		snowPart.Transparency = 1
		snowPart.Size = Vector3.new(140, 1, 140)
		snowCore = makeEmitter(snowPart)
		snowHalo = makeEmitter(snowPart)
		snowPart.Parent = Camera
	end
	if not snowBloom or not snowBloom.Parent then
		snowBloom = Instance.new("BloomEffect")
		snowBloom.Name = "NightfallBloom"
		snowBloom.Size = 32
		snowBloom.Threshold = 0.9
		snowBloom.Parent = Lighting
	end
end

local function snowStep(dt)
	if not Cfg.snow then
		if snowCore then snowCore.Enabled = false end
		if snowHalo then snowHalo.Enabled = false end
		if snowBloom then snowBloom.Enabled = false end
		return
	end
	if not Camera then return end
	ensureSnow()

	local camPos = Camera.CFrame.Position
	snowPart.CFrame = CFrame.new(camPos + Vector3.new(0, 45, 0))

	-- Проверка крыши над головой (раз в 0.25 сек)
	snowIndoorTimer = snowIndoorTimer + dt
	if snowIndoorTimer > 0.25 then
		snowIndoorTimer = 0
		snowIndoorBlocked = false
		if Cfg.snowIndoor then
			local ignore = { LocalPlayer.Character }
			for _ = 1, 5 do
				snowRay.FilterDescendantsInstances = ignore
				local res = Workspace:Raycast(camPos, Vector3.new(0, 60, 0), snowRay)
				if not res then break end
				local hit = res.Instance
				if hit.Transparency >= 0.95 or not hit.CanCollide then
					table.insert(ignore, hit)
				else
					snowIndoorBlocked = true
					break
				end
			end
		end
	end

	local active = not snowIndoorBlocked
	local glow = Cfg.snowGlow
	if night.applied then
		glow = glow * (1 + Cfg.nightIntensity)   -- ночью свечение сильнее
	end
	local size = Cfg.snowSize
	local fall = Cfg.snowSpeed
	local color = Cfg.snowTint and Cfg.snowColor or Color3.new(1, 1, 1)
	local tex = (Cfg.snowTexture ~= "" and Cfg.snowTexture) or SNOW_DEFAULT_TEX
	local accel = Vector3.new(Cfg.snowWind, 0, 0)
	local speed = NumberRange.new(fall * 0.8, fall * 1.2)

	-- Сами снежинки
	if snowCore.Texture ~= tex then snowCore.Texture = tex end
	snowCore.Enabled = active
	snowCore.Rate = Cfg.snowAmount
	snowCore.Color = ColorSequence.new(color)
	snowCore.Speed = speed
	snowCore.Acceleration = accel
	snowCore.Brightness = 1 + glow
	snowCore.Size = NumberSequence.new({ kp(0, size, size * 0.4), kp(1, size, size * 0.4) })
	snowCore.Transparency = NumberSequence.new({ kp(0, 1), kp(0.08, 0.05), kp(0.85, 0.05), kp(1, 1) })

	-- Мягкий ореол вокруг (слой свечения)
	if snowHalo.Texture ~= tex then snowHalo.Texture = tex end
	snowHalo.Enabled = active and glow > 0
	snowHalo.Rate = Cfg.snowAmount * 0.5
	snowHalo.Color = ColorSequence.new(color)
	snowHalo.Speed = speed
	snowHalo.Acceleration = accel
	snowHalo.Brightness = glow * 2
	snowHalo.Size = NumberSequence.new({ kp(0, size * 3.5, size), kp(1, size * 3.5, size) })
	snowHalo.Transparency = NumberSequence.new({ kp(0, 1), kp(0.1, 0.88), kp(0.85, 0.88), kp(1, 1) })

	-- Bloom-шейдер всей сцены
	snowBloom.Enabled = glow > 0
	snowBloom.Intensity = glow
end

-- ====================================================================
-- Круг при прыжке
-- ====================================================================
local TweenService = game:GetService("TweenService")

local jumpRay = RaycastParams.new()
jumpRay.FilterType = Enum.RaycastFilterType.Exclude

local function spawnJumpCircle(char)
	if not Cfg.jumpCircle or not Camera then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Ищем землю под ногами
	jumpRay.FilterDescendantsInstances = { char }
	local res = Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), jumpRay)
	local pos = res and (res.Position + Vector3.new(0, 0.06, 0)) or (root.Position - Vector3.new(0, 3, 0))

	local part = Instance.new("Part")
	part.Name = "NightfallJump"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Cfg.jumpColor
	part.Transparency = 0.3
	part.Size = Vector3.new(0.12, 1, 1)
	part.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	part.Parent = Camera

	local d = Cfg.jumpSize
	local t = Cfg.jumpTime
	TweenService:Create(part, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, d, d),
		Transparency = 1,
	}):Play()
	task.delay(t + 0.2, function()
		pcall(function() part:Destroy() end)
	end)
end

local function hookJump(char)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum then return end
	connect(hum.StateChanged, function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			pcall(spawnJumpCircle, char)
		end
	end)
end

connect(LocalPlayer.CharacterAdded, function(c)
	task.spawn(hookJump, c)
end)
if LocalPlayer.Character then
	task.spawn(hookJump, LocalPlayer.Character)
end

-- ====================================================================
-- Night mode (тёмная атмосфера + шейдерные эффекты)
-- ====================================================================
local function lerpN(a, b, t)
	return a + (b - a) * t
end

local function ensureNightObjects()
	if not night.cc or not night.cc.Parent then
		night.cc = Instance.new("ColorCorrectionEffect")
		night.cc.Name = "NightfallNightCC"
		night.cc.Parent = Lighting
	end
	if not night.bloom or not night.bloom.Parent then
		night.bloom = Instance.new("BloomEffect")
		night.bloom.Name = "NightfallNightBloom"
		night.bloom.Parent = Lighting
	end
	if not night.rays or not night.rays.Parent then
		night.rays = Instance.new("SunRaysEffect")
		night.rays.Name = "NightfallNightRays"
		night.rays.Parent = Lighting
	end
	if not night.dof or not night.dof.Parent then
		night.dof = Instance.new("DepthOfFieldEffect")
		night.dof.Name = "NightfallNightDOF"
		night.dof.Parent = Lighting
	end
end

local function nightCapture()
	night.orig = {
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ExposureCompensation = Lighting.ExposureCompensation,
		FogColor = Lighting.FogColor,
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
	}
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		night.atmo = atmo
		night.atmoCreated = false
		night.atmoOrig = {
			Density = atmo.Density, Offset = atmo.Offset, Color = atmo.Color,
			Decay = atmo.Decay, Glare = atmo.Glare, Haze = atmo.Haze,
		}
	else
		atmo = Instance.new("Atmosphere")
		atmo.Name = "NightfallAtmosphere"
		atmo.Density = 0
		atmo.Parent = Lighting
		night.atmo = atmo
		night.atmoCreated = true
		night.atmoOrig = {
			Density = 0, Offset = 0, Color = Color3.fromRGB(199, 199, 199),
			Decay = Color3.fromRGB(106, 112, 125), Glare = 0, Haze = 0,
		}
	end
end

local function nightApply()
	local t = Cfg.nightIntensity
	local o = night.orig

	-- Освещение карты
	Lighting.Brightness = lerpN(o.Brightness, 0.3, t)
	Lighting.Ambient = o.Ambient:Lerp(Color3.fromRGB(12, 16, 34), t)
	Lighting.OutdoorAmbient = o.OutdoorAmbient:Lerp(Color3.fromRGB(18, 24, 50), t)
	Lighting.ExposureCompensation = lerpN(o.ExposureCompensation, -0.8, t)
	Lighting.FogColor = o.FogColor:Lerp(Color3.fromRGB(8, 12, 28), t)
	local fogTarget = math.min(o.FogEnd, 900)
	Lighting.FogEnd = o.FogEnd * (fogTarget / math.max(o.FogEnd, 1)) ^ t

	-- Время суток
	if Cfg.nightSky then
		if not night.clockSet then
			night.clockOrig = Lighting.ClockTime
			night.clockSet = true
		end
		Lighting.ClockTime = 0
	elseif night.clockSet then
		Lighting.ClockTime = night.clockOrig
		night.clockSet = false
	end

	-- Атмосфера
	local a, ao = night.atmo, night.atmoOrig
	if a and a.Parent then
		a.Density = lerpN(ao.Density, 0.5, t)
		a.Haze = lerpN(ao.Haze, 2.2, t)
		a.Glare = lerpN(ao.Glare, 0, t)
		a.Offset = ao.Offset
		a.Color = ao.Color:Lerp(Color3.fromRGB(40, 55, 95), t)
		a.Decay = ao.Decay:Lerp(Color3.fromRGB(10, 14, 35), t)
	end

	-- Шейдерные эффекты
	ensureNightObjects()
	night.cc.Enabled = true
	night.cc.Brightness = -0.04 * t
	night.cc.Contrast = 0.2 * t
	night.cc.Saturation = -0.2 * t
	night.cc.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(185, 205, 255), t)

	night.bloom.Enabled = true
	night.bloom.Intensity = 0.9 * t
	night.bloom.Size = 30
	night.bloom.Threshold = 0.8

	night.rays.Enabled = not Cfg.nightSky
	night.rays.Intensity = 0.1 * t
	night.rays.Spread = 0.6

	night.dof.Enabled = true
	night.dof.FarIntensity = 0.2 * t
	night.dof.NearIntensity = 0
	night.dof.FocusDistance = 60
	night.dof.InFocusRadius = 80
end

local function nightRestore()
	if not night.applied then return end
	night.applied = false

	if night.orig then
		for k, v in pairs(night.orig) do
			pcall(function() Lighting[k] = v end)
		end
	end
	if night.clockSet then
		pcall(function() Lighting.ClockTime = night.clockOrig end)
		night.clockSet = false
	end
	if night.atmo then
		if night.atmoCreated then
			pcall(function() night.atmo:Destroy() end)
		elseif night.atmo.Parent then
			for k, v in pairs(night.atmoOrig) do
				pcall(function() night.atmo[k] = v end)
			end
		end
		night.atmo = nil
	end
	for _, k in ipairs({ "cc", "bloom", "rays", "dof" }) do
		if night[k] then
			pcall(function() night[k]:Destroy() end)
			night[k] = nil
		end
	end
end

local function nightStep()
	if not Cfg.nightMode then
		nightRestore()
		return
	end
	if not night.applied then
		nightCapture()
		night.applied = true
	end
	nightApply()
end

local Theme = {
	bg = Color3.fromRGB(12, 16, 28),
	side = Color3.fromRGB(8, 11, 20),
	panel = Color3.fromRGB(19, 25, 41),
	text = Color3.fromRGB(215, 224, 240),
	dim = Color3.fromRGB(120, 132, 156),
	accent = Color3.fromRGB(0, 170, 255),
	off = Color3.fromRGB(42, 51, 74),
}

local function make(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end
local function corner(inst, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or 6) }, inst)
end

local refreshers = {}   -- обновляют вид контролов из Cfg (после загрузки конфига)
local function refreshAll()
	for _, fn in ipairs(refreshers) do pcall(fn) end
end

local main = make("Frame", {
	Name = "Main",
	Size = UDim2.new(0, 600, 0, 430),
	Position = UDim2.new(0.5, -300, 0.5, -215),
	BackgroundColor3 = Theme.bg,
	BorderSizePixel = 0,
}, screenGui)
corner(main, 8)

local side = make("Frame", {
	Size = UDim2.new(0, 130, 1, 0),
	BackgroundColor3 = Theme.side,
	BorderSizePixel = 0,
}, main)
corner(side, 8)
-- закрываем скругление справа у сайдбара
make("Frame", {
	Size = UDim2.new(0, 10, 1, 0),
	Position = UDim2.new(1, -10, 0, 0),
	BackgroundColor3 = Theme.side,
	BorderSizePixel = 0,
}, side)

make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
	Text = "NIGHTFALL",
	Font = Enum.Font.GothamBlack,
	TextSize = 17,
	TextColor3 = Theme.accent,
}, side)

make("TextLabel", {
	Size = UDim2.new(1, -16, 0, 22),
	Position = UDim2.new(0, 8, 1, -28),
	BackgroundTransparency = 1,
	Text = LocalPlayer.Name,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextColor3 = Theme.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, side)

local content = make("Frame", {
	Size = UDim2.new(1, -130, 1, 0),
	Position = UDim2.new(0, 130, 0, 0),
	BackgroundTransparency = 1,
}, main)

local topBar = make("Frame", {
	Size = UDim2.new(1, 0, 0, 28),
	BackgroundTransparency = 1,
	Active = true,
}, content)
local topLabel = make("TextLabel", {
	Size = UDim2.new(1, -16, 1, 0),
	Position = UDim2.new(0, 12, 0, 0),
	BackgroundTransparency = 1,
	Text = "",
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = Theme.text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, topBar)

-- Перетаскивание окна
local dragging, dragStart, startPos
local function makeDraggable(handle)
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
end
makeDraggable(topBar)
makeDraggable(side)

-- Слайдеры: общая логика перетаскивания
local activeDrag
connect(UserInputService.InputChanged, function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if dragging then
			local d = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		elseif activeDrag then
			activeDrag(input.Position.X)
		end
	end
end)
connect(UserInputService.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
		activeDrag = nil
	end
end)

-- Полоса слайдера
local function bar(parent, yOffset, minV, maxV, step, init, cb)
	local back = make("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 0, yOffset),
		BackgroundColor3 = Theme.off,
		BorderSizePixel = 0,
	}, parent)
	corner(back, 3)
	local fill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Theme.accent,
		BorderSizePixel = 0,
	}, back)
	corner(fill, 3)
	local function visual(v)
		fill.Size = UDim2.new(math.clamp((v - minV) / (maxV - minV), 0, 1), 0, 1, 0)
	end
	visual(init)
	local hit = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 0, yOffset - 4),
		BackgroundTransparency = 1,
		Text = "",
	}, parent)
	local function fromX(x)
		local rel = math.clamp((x - back.AbsolutePosition.X) / math.max(back.AbsoluteSize.X, 1), 0, 1)
		local v = minV + (maxV - minV) * rel
		v = math.clamp(math.floor(v / step + 0.5) * step, minV, maxV)
		visual(v)
		cb(v)
	end
	hit.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			activeDrag = fromX
			fromX(i.Position.X)
		end
	end)
	return visual
end

-- Вкладки и секции
local tabs = {}
local tabButtons = {}

local function selectTab(name)
	for n, t in pairs(tabs) do
		t.page.Visible = (n == name)
		local b = tabButtons[n]
		b.TextColor3 = (n == name) and Theme.text or Theme.dim
		b.Bar.Visible = (n == name)
	end
	topLabel.Text = name
end

local tabCount = 0
local function addTab(name)
	tabCount = tabCount + 1
	local btn = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.new(0, 0, 0, 44 + (tabCount - 1) * 34),
		BackgroundTransparency = 1,
		Text = "   " .. name,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, side)
	make("Frame", {
		Name = "Bar",
		Size = UDim2.new(0, 3, 0.6, 0),
		Position = UDim2.new(0, 0, 0.2, 0),
		BackgroundColor3 = Theme.accent,
		BorderSizePixel = 0,
		Visible = false,
	}, btn)
	tabButtons[name] = btn

	local page = make("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -36),
		Position = UDim2.new(0, 8, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, content)

	local function column(xScale, xOff)
		local f = make("Frame", {
			Size = UDim2.new(0.5, -4, 0, 0),
			Position = UDim2.new(xScale, xOff, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, page)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, f)
		return { frame = f, n = 0 }
	end

	local t = { page = page, left = column(0, 0), right = column(0.5, 4) }
	tabs[name] = t
	btn.MouseButton1Click:Connect(function() selectTab(name) end)
	return t
end

local function newSection(col, title)
	col.n = col.n + 1
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
		LayoutOrder = col.n,
	}, col.frame)
	corner(frame, 6)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10),
	}, frame)
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Theme.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
	}, frame)

	local sec = { frame = frame, n = 0 }

	local function nextOrder()
		sec.n = sec.n + 2
		return sec.n
	end

	-- Переключатель (+ необязательный выбор цвета)
	function sec.Toggle(text, key, colorKey)
		local order = nextOrder()
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, frame)
		make("TextLabel", {
			Size = UDim2.new(1, -70, 1, 0),
			BackgroundTransparency = 1,
			Text = text,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = Theme.text,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		local back = make("Frame", {
			Size = UDim2.new(0, 32, 0, 16),
			Position = UDim2.new(1, -32, 0.5, -8),
			BackgroundColor3 = Theme.off,
			BorderSizePixel = 0,
		}, row)
		corner(back, 8)
		local knob = make("Frame", {
			Size = UDim2.new(0, 12, 0, 12),
			Position = UDim2.new(0, 2, 0.5, -6),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
		}, back)
		corner(knob, 6)
		local function refresh()
			local on = Cfg[key]
			back.BackgroundColor3 = on and Theme.accent or Theme.off
			knob.Position = on and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
		end
		refresh()
		table.insert(refreshers, refresh)
		local btn = make("TextButton", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
		}, row)
		btn.MouseButton1Click:Connect(function()
			Cfg[key] = not Cfg[key]
			refresh()
		end)

		if colorKey then
			local swatch = make("TextButton", {
				Size = UDim2.new(0, 20, 0, 12),
				Position = UDim2.new(1, -58, 0.5, -6),
				BackgroundColor3 = Cfg[colorKey],
				BorderSizePixel = 0,
				Text = "",
				ZIndex = 3,
			}, row)
			corner(swatch, 3)

			local popup = make("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Visible = false,
				LayoutOrder = order + 1,
			}, frame)
			make("UIListLayout", { Padding = UDim.new(0, 2) }, popup)

			local setters = {}
			local channels = { "R", "G", "B" }
			local function current()
				local c = Cfg[colorKey]
				return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
			end
			for idx, ch in ipairs(channels) do
				local r = make("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = idx }, popup)
				make("TextLabel", {
					Size = UDim2.new(0, 14, 1, 0),
					BackgroundTransparency = 1,
					Text = ch,
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextColor3 = Theme.dim,
				}, r)
				local holder = make("Frame", {
					Size = UDim2.new(1, -20, 1, 0),
					Position = UDim2.new(0, 20, 0, 0),
					BackgroundTransparency = 1,
				}, r)
				setters[idx] = bar(holder, 6, 0, 255, 1, current()[idx], function(v)
					local c = current()
					c[idx] = v
					Cfg[colorKey] = Color3.fromRGB(c[1], c[2], c[3])
					swatch.BackgroundColor3 = Cfg[colorKey]
				end)
			end
			swatch.MouseButton1Click:Connect(function()
				popup.Visible = not popup.Visible
			end)
			table.insert(refreshers, function()
				swatch.BackgroundColor3 = Cfg[colorKey]
				local c = current()
				for i2 = 1, 3 do setters[i2](c[i2]) end
			end)
		end
	end

	-- Слайдер
	function sec.Slider(text, key, minV, maxV, step)
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			LayoutOrder = nextOrder(),
		}, frame)
		make("TextLabel", {
			Size = UDim2.new(1, -50, 0, 14),
			BackgroundTransparency = 1,
			Text = text,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = Theme.text,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		local valLabel = make("TextLabel", {
			Size = UDim2.new(0, 50, 0, 14),
			Position = UDim2.new(1, -50, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = Theme.dim,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, row)
		local function fmt(v)
			return step < 1 and string.format("%.2f", v) or tostring(math.floor(v))
		end
		valLabel.Text = fmt(Cfg[key])
		local setVisual = bar(row, 22, minV, maxV, step, Cfg[key], function(v)
			Cfg[key] = v
			valLabel.Text = fmt(v)
		end)
		table.insert(refreshers, function()
			setVisual(Cfg[key])
			valLabel.Text = fmt(Cfg[key])
		end)
	end

	-- Выбор из списка (по клику листает варианты)
	function sec.Cycle(text, key, options)
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			LayoutOrder = nextOrder(),
		}, frame)
		make("TextLabel", {
			Size = UDim2.new(0.5, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = text,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = Theme.text,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		local btn = make("TextButton", {
			Size = UDim2.new(0, 80, 0, 20),
			Position = UDim2.new(1, -80, 0.5, -10),
			BackgroundColor3 = Theme.off,
			BorderSizePixel = 0,
			Text = tostring(Cfg[key]),
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = Theme.text,
		}, row)
		corner(btn, 4)
		btn.MouseButton1Click:Connect(function()
			local idx = table.find(options, Cfg[key]) or 0
			Cfg[key] = options[idx % #options + 1]
			btn.Text = Cfg[key]
		end)
		table.insert(refreshers, function() btn.Text = tostring(Cfg[key]) end)
	end

	-- Кнопка
	function sec.Button(text, cb)
		local btn = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = Theme.off,
			BorderSizePixel = 0,
			Text = text,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = Theme.text,
			LayoutOrder = nextOrder(),
		}, frame)
		corner(btn, 5)
		btn.MouseButton1Click:Connect(cb)
		return btn
	end

	-- Поле ввода
	function sec.TextBox(placeholder, default)
		local box = make("TextBox", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = Theme.off,
			BorderSizePixel = 0,
			PlaceholderText = placeholder,
			Text = default or "",
			ClearTextOnFocus = false,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = Theme.text,
			PlaceholderColor3 = Theme.dim,
			LayoutOrder = nextOrder(),
		}, frame)
		corner(box, 5)
		return box
	end

	-- Текст
	function sec.Label(text)
		return make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 16),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = text,
			TextWrapped = true,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = Theme.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = nextOrder(),
		}, frame)
	end

	return sec
end

-- ====================================================================
-- Вкладка Visuals
-- ====================================================================
local visuals = addTab("Visuals")

local sGeneral = newSection(visuals.left, "GENERAL")
sGeneral.Toggle("Enable ESP", "enabled")
sGeneral.Toggle("Team check", "teamCheck")
sGeneral.Slider("Max distance", "maxDist", 100, 5000, 50)
sGeneral.Slider("Text size", "textSize", 10, 20, 1)
if not hasDrawing then
	sGeneral.Label("Твой executor не поддерживает Drawing: боксы, текст и линии недоступны, работают только Chams.")
end

local sBox = newSection(visuals.left, "BOX")
sBox.Toggle("Box", "box", "boxColor")
sBox.Cycle("Style", "boxStyle", { "Full", "Corner" })
sBox.Toggle("Box fill", "boxFill", "boxFillColor")
sBox.Slider("Fill opacity", "boxFillAlpha", 0, 1, 0.05)

local sInfo = newSection(visuals.right, "INFO")
sInfo.Toggle("Name", "name", "nameColor")
sInfo.Toggle("Distance", "distance", "distColor")
sInfo.Toggle("Health bar", "health")
sInfo.Toggle("Skeleton", "skeleton", "skelColor")

local sLines = newSection(visuals.right, "TRACERS")
sLines.Toggle("Tracers", "tracers", "tracerColor")
sLines.Cycle("Origin", "tracerOrigin", { "Bottom", "Center", "Mouse" })

local sChams = newSection(visuals.right, "CHAMS")
sChams.Toggle("Chams", "chams", "chamsFill")
sChams.Slider("Fill transparency", "chamsTransp", 0, 1, 0.05)
sChams.Toggle("Outline", "chamsOutlineOn", "chamsOutline")

-- ====================================================================
-- Вкладка Misc
-- ====================================================================
local misc = addTab("Misc")
local sUi = newSection(misc.left, "INTERFACE")
sUi.Toggle("Watermark", "watermark")
sUi.Label("Меню открывается и закрывается клавишей Insert.")

local sScreen = newSection(misc.right, "SCREEN")
sScreen.Toggle("Stretch screen", "stretch")
sScreen.Slider("Width (X)", "stretchX", 0.3, 1.5, 0.01)
sScreen.Slider("Height (Y)", "stretchY", 0.3, 1.5, 0.01)
sScreen.Label("Y меньше 1 растягивает картинку по горизонтали (как растянутое разрешение в CS). X меньше 1 сужает её.")

-- ====================================================================
-- Вкладка Config
-- ====================================================================
local aimTab = addTab("Aimbot")

local sAim = newSection(aimTab.left, "AIMBOT")
sAim.Toggle("Enable", "aimbot")
sAim.Cycle("Aim key", "aimKey", { "RMB", "LMB", "Always" })
sAim.Cycle("Target", "aimPart", { "Head", "Chest", "Root" })
sAim.Toggle("Wall check", "wallCheck")
sAim.Slider("Aim speed", "aimSpeed", 1, 100, 1)
sAim.Label("PageUp / PageDown меняют скорость на 5 прямо в игре. 100 = мгновенная наводка.")

local sFov = newSection(aimTab.right, "FOV")
sFov.Toggle("Show FOV circle", "showFov", "fovColor")
sFov.Slider("FOV radius", "aimFov", 20, 600, 5)
sFov.Label("Team check берётся из вкладки Visuals (General).")

local snowTab = addTab("Визуал")

local sSnow = newSection(snowTab.left, "SNOWFALL")
sSnow.Toggle("Enable snow", "snow")
sSnow.Slider("Amount", "snowAmount", 10, 500, 10)
sSnow.Slider("Size", "snowSize", 0.1, 2, 0.05)
sSnow.Slider("Fall speed", "snowSpeed", 2, 40, 1)
sSnow.Slider("Wind", "snowWind", -20, 20, 1)
sSnow.Label("Home / End меняют количество снежинок на 20 прямо в игре.")

local sGlow = newSection(snowTab.right, "GLOW")
sGlow.Slider("Glow", "snowGlow", 0, 3, 0.1)
sGlow.Toggle("Tint color", "snowTint", "snowColor")
sGlow.Toggle("Hide indoors", "snowIndoor")
local texBox = sGlow.TextBox("ID картинки снежинки (необязательно)", "")
texBox.FocusLost:Connect(function()
	local id = texBox.Text:match("%d+")
	Cfg.snowTexture = id and ("rbxassetid://" .. id) or ""
end)
table.insert(refreshers, function()
	texBox.Text = (Cfg.snowTexture or ""):match("%d+") or ""
end)
sGlow.Label("Без ID берётся встроенная звёздочка Roblox. Нужен ID изображения (Image), не Decal. Glow добавляет свечение и Bloom на весь экран.")

local sJump = newSection(snowTab.left, "JUMP CIRCLE")
sJump.Toggle("Jump circle", "jumpCircle", "jumpColor")
sJump.Slider("Size", "jumpSize", 3, 25, 1)
sJump.Slider("Duration (sec)", "jumpTime", 0.3, 4, 0.1)
sJump.Label("При прыжке под тобой остаётся круг, который расходится и затухает.")

local sNight = newSection(snowTab.right, "NIGHT MODE")
sNight.Toggle("Night mode", "nightMode")
sNight.Slider("Intensity", "nightIntensity", 0, 1, 0.05)
sNight.Toggle("Night sky", "nightSky")
sNight.Label("Затемняет карту, добавляет туман, Bloom, цветокоррекцию и глубину резкости. Свечение снега и круга при этом усиливается.")

local cfgTab = addTab("Config")

local function colorToTable(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local sCfg = newSection(cfgTab.left, "CONFIGS")
local nameBox = sCfg.TextBox("Название конфига", "default")
local statusLabel = sCfg.Label("")

local function setStatus(text)
	statusLabel.Text = text
end

sCfg.Button("Save", function()
	local name = nameBox.Text:gsub("[^%w_%-]", "")
	if name == "" then return setStatus("Введи название конфига") end
	if not writefile then return setStatus("Executor не поддерживает writefile") end
	pcall(function()
		if makefolder and isfolder and not isfolder(DIR) then makefolder(DIR) end
	end)
	local out = {}
	for k, v in pairs(Cfg) do
		if typeof(v) == "Color3" then
			out[k] = { c = colorToTable(v) }
		else
			out[k] = v
		end
	end
	local ok = pcall(writefile, DIR .. "/" .. name .. ".json", HttpService:JSONEncode(out))
	setStatus(ok and ("Сохранено: " .. name) or "Не удалось сохранить")
end)

sCfg.Button("Load", function()
	local name = nameBox.Text:gsub("[^%w_%-]", "")
	if name == "" then return setStatus("Введи название конфига") end
	if not (readfile and isfile) then return setStatus("Executor не поддерживает readfile") end
	local path = DIR .. "/" .. name .. ".json"
	if not isfile(path) then return setStatus("Конфиг не найден") end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(path))
	end)
	if not ok or type(data) ~= "table" then return setStatus("Файл повреждён") end
	for k, v in pairs(data) do
		local cur = Cfg[k]
		if cur ~= nil then
			if typeof(cur) == "Color3" and type(v) == "table" and type(v.c) == "table" then
				Cfg[k] = Color3.fromRGB(v.c[1] or 255, v.c[2] or 255, v.c[3] or 255)
			elseif type(cur) == type(v) then
				Cfg[k] = v
			end
		end
	end
	refreshAll()
	setStatus("Загружено: " .. name)
end)

local sScript = newSection(cfgTab.right, "SCRIPT")

-- ====================================================================
-- Watermark
-- ====================================================================
local wm = make("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.new(0, 0, 0, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Theme.bg,
	BorderSizePixel = 0,
}, screenGui)
corner(wm, 5)
make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, wm)
make("Frame", {
	Size = UDim2.new(1, 20, 0, 2),
	Position = UDim2.new(0, -10, 0, 0),
	BackgroundColor3 = Theme.accent,
	BorderSizePixel = 0,
}, wm)
local wmLabel = make("TextLabel", {
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Text = "nightfall",
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = Theme.text,
}, wm)

-- ====================================================================
-- Выгрузка
-- ====================================================================
local function unload()
	running = false
	pcall(function() RunService:UnbindFromRenderStep("NightfallMain") end)
	if fovCircle then pcall(function() fovCircle:Remove() end) end
	if snowPart then pcall(function() snowPart:Destroy() end) end
	if snowBloom then pcall(function() snowBloom:Destroy() end) end
	pcall(nightRestore)
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	connections = {}
	for p in pairs(esp) do removeESP(p) end
	for p in pairs(chams) do removeESP(p) end
	pcall(function() chamsFolder:Destroy() end)
	pcall(function() screenGui:Destroy() end)
	if getgenv then getgenv().Nightfall_Unload = nil end
end
if getgenv then getgenv().Nightfall_Unload = unload end

sScript.Button("Unload", unload)
sScript.Label("Полностью убирает меню и всё ESP.")

-- ====================================================================
-- Главный цикл
-- ====================================================================
local fps = 60
local wmTimer = 0

RunService:BindToRenderStep("NightfallMain", Enum.RenderPriority.Camera.Value + 1, function(dt)
	Camera = Workspace.CurrentCamera

	pcall(aimbotStep, dt)
	pcall(nightStep)
	pcall(snowStep, dt)

	-- Растягивание экрана (масштабируем матрицу камеры)
	if Cfg.stretch and Camera then
		Camera.CFrame = Camera.CFrame * CFrame.new(0, 0, 0, Cfg.stretchX, 0, 0, 0, Cfg.stretchY, 0, 0, 0, 1)
	end
	fps = fps + (1 / math.max(dt, 0.001) - fps) * 0.1

	wm.Visible = Cfg.watermark
	wmTimer = wmTimer + dt
	if wmTimer > 0.5 then
		wmTimer = 0
		wmLabel.Text = string.format("nightfall  |  %s  |  %d fps", LocalPlayer.Name, math.floor(fps + 0.5))
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local ok = pcall(updatePlayer, player)
			if not ok and esp[player] then hideAll(esp[player]) end
		end
	end
end)

connect(Players.PlayerRemoving, removeESP)

connect(UserInputService.InputBegan, function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Insert then
		main.Visible = not main.Visible
	elseif input.KeyCode == Enum.KeyCode.PageUp then
		Cfg.aimSpeed = math.min(100, Cfg.aimSpeed + 5)
		refreshAll()
	elseif input.KeyCode == Enum.KeyCode.PageDown then
		Cfg.aimSpeed = math.max(1, Cfg.aimSpeed - 5)
		refreshAll()
	elseif input.KeyCode == Enum.KeyCode.Home then
		Cfg.snowAmount = math.min(500, Cfg.snowAmount + 20)
		refreshAll()
	elseif input.KeyCode == Enum.KeyCode.End then
		Cfg.snowAmount = math.max(10, Cfg.snowAmount - 20)
		refreshAll()
	end
end)

selectTab("Visuals")
