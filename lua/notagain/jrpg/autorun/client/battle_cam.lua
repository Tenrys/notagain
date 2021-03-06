local prettytext = requirex("pretty_text")

local function FrameTime()
	return math.Clamp(_G.FrameTime(), 0, 0.1)
end

battlecam = battlecam or {}

local joystick_remap = {
	[KEY_XBUTTON_A] = IN_JUMP,
	[KEY_XBUTTON_X] = IN_SPEED,
	[KEY_XBUTTON_B] = IN_USE,

	[KEY_XBUTTON_STICK1] = IN_DUCK,

	[KEY_XSTICK1_UP] = IN_FORWARD,
	[KEY_XSTICK1_DOWN] = IN_BACK,
	[KEY_XSTICK1_LEFT] = IN_MOVELEFT,
	[KEY_XSTICK1_RIGHT] = IN_MOVERIGHT,

	[KEY_XBUTTON_RTRIGGER] = IN_ATTACK,
	[KEY_XBUTTON_RIGHT_SHOULDER] = IN_ATTACK2,
}

local mouse_buttons = {
	[MOUSE_MIDDLE] = true,
}

local name_to_key = {}

for i = 1, 256 do
	local name = input.GetKeyName(i)
	if name then
		name_to_key[name] = i
	end
end

function battlecam.IsKeyDown(key)
	if key == "target" then
		return input.IsButtonDown(KEY_XBUTTON_STICK2) or input.IsMouseDown(MOUSE_MIDDLE)
	elseif key == "select_target_left" then
		return input.IsButtonDown(KEY_XBUTTON_LEFT)
	elseif key == "select_target_right" then
		return input.IsButtonDown(KEY_XBUTTON_RIGHT)
	elseif key == "select_prev_weapon" then
		if battlecam.select_prev_weapon then
			return true
		end
		return input.IsKeyDown(KEY_UP) or input.IsButtonDown(KEY_XBUTTON_UP)
	elseif key == "select_next_weapon" then
		if battlecam.select_next_weapon then
			return true
		end
		return input.IsKeyDown(KEY_DOWN) or input.IsButtonDown(KEY_XBUTTON_DOWN)
	elseif key == "attack" then
		return input.IsButtonDown(KEY_XBUTTON_RTRIGGER) or input.IsButtonDown(KEY_XBUTTON_LTRIGGER)
	elseif key == "shield" then
		return input.IsButtonDown(KEY_XBUTTON_LTRIGGER) or input.IsKeyDown(KEY_LALT) or LocalPlayer():KeyDown(IN_WALK)
	end
end

local HOOK = function(event) hook.Add(event, "battlecam", battlecam[event]) end
local UNHOOK = function(event) hook.Remove(event, "battlecam") end

function battlecam.LimitAngles(pos, dir, fov, prevpos)
	local a1 = dir:Angle()
	local a2 = (pos - prevpos):Angle()

	fov = fov / 3
	dir = a2:Forward() *-1

	a1.p = a2.p + math.Clamp(math.AngleDifference(a1.p, a2.p), -fov, fov)
	fov = fov / (ScrH()/ScrW())
	a1.y = a2.y + math.Clamp(math.AngleDifference(a1.y, a2.y), -fov, fov)

	a1.p = math.NormalizeAngle(a1.p)
	a1.y = math.NormalizeAngle(a1.y)

	return LerpVector(math.Clamp(Angle(0, a1.y, 0):Forward():DotProduct(dir), 0, 1), a1:Forward(), dir * -1)
end


local cvar = CreateClientConVar("battlecam_enabled", "0", false, true)

function battlecam.Enable()
	RunConsoleCommand("joystick", "0")
	RunConsoleCommand("joy_advanced", "0")

	for _, v in pairs(ents.GetAll()) do
		if v.battlecam_crosshair then
			SafeRemoveEntity(v)
		end
	end

	HOOK("CalcView")
	HOOK("InputMouseApply")
	HOOK("CreateMove")
	HOOK("PlayerBindPress")
	HOOK("ShouldDrawLocalPlayer")
	HOOK("PreDrawHUD")

	battlecam.enabled = true
	battlecam.aim_pos = Vector()
	battlecam.aim_dir = Vector()
	--battlecam.CreateCrosshair()
	--battlecam.CreateHUD()

	battlecam.enemy_visibility = 0
	battlecam.player_visibility = 0

	battlecam.pixvis = util.GetPixelVisibleHandle()
	battlecam.pixvis2 = util.GetPixelVisibleHandle()

	cvar:SetInt(1)
end

function battlecam.Disable()
	UNHOOK("CalcView")
	UNHOOK("InputMouseApply")
	UNHOOK("CreateMove")
	UNHOOK("PlayerBindPress")
	UNHOOK("HUDShouldDraw")
	UNHOOK("ShouldDrawLocalPlayer")
	UNHOOK("PreDrawHUD")

	battlecam.enabled = false

	cvar:SetInt(0)
end

function battlecam.IsEnabled()
	return battlecam.enabled
end

-- hooks

do -- view
	battlecam.cam_speed = 6

	battlecam.cam_pos = Vector()
	battlecam.cam_dir = Vector()
	battlecam.free_cam_dir = Vector()

	local smooth_pos = Vector()
	local smooth_dir = Vector()
	local smooth_roll = 0
	local smooth_fov = 0

	local smooth_visible = 0
	local smooth_visible_offset = 0

	local last_pos = Vector()

	battlecam.last_target_select = 0

	function battlecam.CalcView()
		local ply = LocalPlayer()
		battlecam.aim_pos = ply:GetShootPos()
		battlecam.aim_dir = (ply:EyePos() - battlecam.cam_pos):GetNormalized()

		--if not battlecam.crosshair_ent:IsValid() then
			--battlecam.CreateCrosshair()
		--end

		--battlecam.SetupCrosshair(battlecam.crosshair_ent)

		local delta = FrameTime()
		local target_pos = battlecam.aim_pos * 1
		local target_dir = battlecam.aim_dir * 1
		local target_fov = 60

		-- roll
		local target_roll = 0--math.Clamp(-smooth_dir:Angle():Right():Dot(last_pos - smooth_pos)  * delta * 40, -30, 30)
		last_pos = smooth_pos

		local lerp_thing = 0

		if battlecam.last_target_select < RealTime() then
			if battlecam.IsKeyDown("select_target_left") then
				jtarget.Scroll(-1)
				battlecam.last_target_select = RealTime() + 0.15
			elseif battlecam.IsKeyDown("select_target_right") then
				jtarget.Scroll(1)
				battlecam.last_target_select = RealTime() + 0.15
			end
		end

		-- do a more usefull and less cinematic view if we're holding ctrl
		if battlecam.IsKeyDown("target") then
			battlecam.aim_dir = ply:GetAimVector()
			target_dir = battlecam.aim_dir * 1
			target_pos = target_pos + battlecam.aim_dir * - 175

			delta = delta * 2

			if jtarget then
				jtarget.StartSelection()
			end
		else
			if jtarget then
				jtarget.StopSelection()
			end

			local ent = jtarget.GetEntity(ply)

			if ent:IsValid() then
				local enemy_size = math.min(ent:BoundingRadius() * (ent:GetModelScale() or 1), 200)

				local ply_pos = ply:EyePos()

				local dist = math.min((enemy_size/4)/ent:NearestPoint(ply:GetPos()):Distance(ply:NearestPoint(ent:GetPos())), 1)
				local ent_pos = LerpVector(math.max(dist, 0.5), jrpg.FindHeadPos(ent), ent:NearestPoint(ent:EyePos()))

				local offset = ent_pos - ply_pos

				--offset:Rotate(Angle(smooth_visible*-offset.z/10,0,0))
				offset:Rotate(Angle(0,battlecam.target_cam_rotation.y,0))

				local p = battlecam.target_cam_rotation.p
				offset.z = p


				target_pos = (LerpVector(0.5, ply_pos, ent_pos) - offset/2) + offset:GetNormalized() * (-enemy_size + (smooth_visible*-500))

				lerp_thing = (((target_pos:Distance(ent_pos) - target_pos:Distance(ply_pos)) / offset:Length()) / 1.5) * 0.5 + 0.5
				target_dir = (LerpVector(lerp_thing, ent_pos, ply_pos) - target_pos)

				local visible = (battlecam.player_visibility * battlecam.enemy_visibility) * 2 - 1

				smooth_visible = smooth_visible + ((-visible - smooth_visible) * delta)

				target_fov = target_fov + math.Clamp(smooth_visible*50, -40, 20) - 30
			else
				local inside_sphere = math.max(math.Clamp((smooth_pos:Distance(ply:EyePos()) / 240), 0, 1) ^ 10 - 0.05, 0)
				target_pos = Lerp(inside_sphere, smooth_pos, ply:EyePos())

				local cam_ang = smooth_dir:Angle()
				cam_ang:Normalize()

				if cam_ang.p >= 89 then
					cam_ang.y = math.NormalizeAngle(cam_ang.y + 180)
				end

				local right = cam_ang:Right() * FrameTime() * - battlecam.cam_rotation_velocity.y
				local up = cam_ang:Up() * FrameTime() * battlecam.cam_rotation_velocity.x

				smooth_pos = smooth_pos + right*1500 + up*1500
				smooth_dir = smooth_dir - right*8 - up*8


				do -- trace block
					local data = util.TraceLine({
						start = ply:NearestPoint(smooth_pos),
						endpos = smooth_pos,
						filter = ents.FindInSphere(ply:GetPos(), ply:BoundingRadius()),
						mask =  MASK_VISIBLE,
					})

					if data.Hit and data.Entity ~= ply and not data.Entity:IsPlayer() and not data.Entity:IsVehicle() then
						smooth_pos = data.HitPos--Lerp(inside_sphere, battlecam.cam_pos, data.HitPos)
					end
				end

				do
					local hack = math.min((battlecam.cam_pos * Vector(1,1,0)):Distance(ply:EyePos() * Vector(1,1,0)) / 300, 1) ^ 1.5
					battlecam.last_flip_walk = battlecam.last_flip_walk or 0
					if hack < 0.01 and not battlecam.flip_walk and battlecam.last_flip_walk < RealTime() and ply:GetVelocity():Length() > 190 then
						battlecam.flip_walk = true
						battlecam.last_flip_walk = RealTime() + 0.1
					end
				end
			end
		end

		-- smoothing
		smooth_pos = smooth_pos + ((target_pos - smooth_pos) * delta * battlecam.cam_speed)
		smooth_dir = smooth_dir + ((target_dir - smooth_dir) * delta * battlecam.cam_speed)
		smooth_fov = smooth_fov + ((target_fov - smooth_fov) * delta * battlecam.cam_speed)
		smooth_roll = smooth_roll + ((target_roll - smooth_roll) * delta * battlecam.cam_speed)

		if jtarget.GetEntity(ply):IsValid() then
			local data = util.TraceLine({
				start = ply:NearestPoint(smooth_pos),
				endpos = smooth_pos,
				filter = ents.FindInSphere(ply:GetPos(), ply:BoundingRadius()),
				mask =  MASK_VISIBLE,
			})

			if data.Hit and data.Entity ~= ply and not data.Entity:IsPlayer() and not data.Entity:IsVehicle() then
				smooth_pos = data.HitPos
				--battlecam.target_cam_rotation.y = battlecam.target_cam_rotation.y - (lerp_thing*2-1)*0.1
			end
		end

		battlecam.cam_pos = smooth_pos
		battlecam.cam_dir = smooth_dir

		battlecam.cam_rotation_velocity:Zero()

		-- return
		local params = {}

		params.origin = smooth_pos
		params.angles = smooth_dir:Angle()
		params.angles.r = smooth_roll
		params.fov = smooth_fov
		params.znear = 20

		return params
	end
end

battlecam.weapon_i = 1
battlecam.last_select = 0

function battlecam.GetWeapons()
	local ply = LocalPlayer()
	battlecam.weapons = table.ClearKeys(ply:GetWeapons())
	table.sort(battlecam.weapons, function(a, b)return a:EntIndex() < b:EntIndex() end)
	return battlecam.weapons
end

function battlecam.GetWeaponIndex()
	return battlecam.weapon_i%#battlecam.GetWeapons() + 1
end

do
	local smooth_dir = Vector()
	battlecam.target_cam_rotation = Angle()
	battlecam.cam_rotation_velocity = Vector()

	local buttons = {}
	for k, v in pairs(_G) do
		if type(k) == "string" and type(v) == "number" then
			if k:StartWith("KEY_") then
				buttons[k] = v
			end
		end
	end

	function battlecam.PlayerBindPress(ply, bind, press)
		for a, b in pairs(joystick_remap) do
			if input.IsButtonDown(a) then
				return true
			end
		end

		for a, b in pairs(mouse_buttons) do
			if input.IsMouseDown(a) then
				return true
			end
		end
	end

	local smooth_x = 0
	local smooth_y = 0
	local last_select = 0

	function battlecam.InputMouseApply(ucmd, x, y, ang)
		smooth_x = smooth_x + ((x - smooth_x) * FrameTime() * 10)
		smooth_y = smooth_y + ((y - smooth_y) * FrameTime() * 10)

		battlecam.cam_rotation_velocity.y = smooth_x / 60
		battlecam.cam_rotation_velocity.x = smooth_y / 60

		return true
	end

	local smooth_forward = 0
	local reset_forward = false

	function battlecam.CreateMove(ucmd)
		local ply = LocalPlayer()

		do -- joystick bindings
			--for key, val in pairs(buttons) do if input.IsButtonDown(val) then print(key) end end

			for a, b in pairs(joystick_remap) do
				if input.IsButtonDown(a) then
					ucmd:SetButtons(bit.bor(ucmd:GetButtons(), b))

					if jtarget.GetEntity(ply):IsValid() then
						if b == IN_MOVELEFT then
							ucmd:SetSideMove(-1000)
						elseif b == IN_MOVERIGHT then
							ucmd:SetSideMove(1000)
						end

						if b == IN_FORWARD then
							ucmd:SetForwardMove(1000)
						elseif b == IN_BACK then
							ucmd:SetForwardMove(-1000)
						end
					end
				end
			end
		end

		do
			if input.IsButtonDown(KEY_PAD_5) or input.IsButtonDown(KEY_XBUTTON_STICK2) then
				battlecam.target_cam_rotation = Angle(-30,0,0)
			end

			if input.IsButtonDown(KEY_XSTICK2_RIGHT) or input.IsButtonDown(KEY_PAD_6) then
				battlecam.target_cam_rotation.y = battlecam.target_cam_rotation.y - FrameTime()*20
				battlecam.cam_rotation_velocity.y = FrameTime()*15
			elseif input.IsButtonDown(KEY_XSTICK2_LEFT) or input.IsButtonDown(KEY_PAD_4) then
				battlecam.target_cam_rotation.y = battlecam.target_cam_rotation.y + FrameTime()*20
				battlecam.cam_rotation_velocity.y = -FrameTime()*15
			end

			if input.IsButtonDown(KEY_XSTICK2_UP) or input.IsButtonDown(KEY_PAD_8) then
				battlecam.target_cam_rotation.p = battlecam.target_cam_rotation.x - FrameTime()*20
				battlecam.cam_rotation_velocity.x = FrameTime()*8
			elseif input.IsButtonDown(KEY_XSTICK2_DOWN) or input.IsButtonDown(KEY_PAD_2) then
				battlecam.target_cam_rotation.p = battlecam.target_cam_rotation.x + FrameTime()*40
				battlecam.cam_rotation_velocity.x = -FrameTime()*8
			end

			battlecam.target_cam_rotation:Normalize()
		end

		if battlecam.IsKeyDown("attack") and not ucmd:KeyDown(IN_ATTACK) then
			ucmd:SetButtons(bit.bor(ucmd:GetButtons(), IN_ATTACK))
		end

		if battlecam.IsKeyDown("shield") then
			if not ply:GetNWEntity("shield"):IsValid() then
				RunConsoleCommand("+jshield")
			end
		else
			if ply:GetNWEntity("shield"):IsValid() then
				RunConsoleCommand("-jshield")
			end
		end

--[[
		if ucmd:KeyDown(IN_SPEED) and ply:GetVelocity() == vector_origin then
			ucmd:SetButtons(bit.bor(ucmd:GetButtons(), IN_USE))
		end
]]
		if not ply:Alive() or vgui.CursorVisible() then return end

		if battlecam.last_select < RealTime() then
			if battlecam.IsKeyDown("select_prev_weapon") then
				battlecam.weapon_i = battlecam.weapon_i + 1
				battlecam.last_select = RealTime() + 0.15
			elseif battlecam.IsKeyDown("select_next_weapon") then
				battlecam.weapon_i = battlecam.weapon_i - 1
				battlecam.last_select = RealTime() + 0.15
			end
		else
			local wep = battlecam.GetWeapons()[battlecam.GetWeaponIndex()]

			if wep then
				ucmd:SelectWeapon(wep)
			end
		end

		local ent = jtarget.GetEntity(ply)

		if not ucmd:KeyDown(IN_ATTACK) and not ply:KeyDown(IN_DUCK) and not ucmd:KeyDown(IN_ATTACK2) and (not ent:IsValid() or ucmd:KeyDown(IN_SPEED)) then

			local dir = Vector()
			local pos = ply:GetPos()

			if ucmd:KeyDown(IN_MOVELEFT) then
				dir = (pos - battlecam.cam_pos):Angle():Right() * -1
			elseif ucmd:KeyDown(IN_MOVERIGHT) then
				dir = (pos - battlecam.cam_pos):Angle():Right()
			end

			if battlecam.flip_walk then
				dir = dir * -1
			end

			if ucmd:KeyDown(IN_FORWARD) then
				dir = dir + (pos - battlecam.cam_pos):Angle():Forward()
			elseif ucmd:KeyDown(IN_BACK) then
				dir = dir + (pos - battlecam.cam_pos):Angle():Forward() * -1
			else
				battlecam.flip_walk = nil
			end

			if battlecam.flip_walk then
				dir = dir * -1
			end

			dir.z = 0

			if dir ~= Vector(0,0,0) then
				smooth_dir = smooth_dir + ((dir - smooth_dir) * FrameTime() * 10)
				ucmd:SetViewAngles(smooth_dir:Angle())

				ucmd:SetForwardMove(10000)
				ucmd:SetSideMove(0)

				if pac and pac.CreateMove then pac.CreateMove(ucmd) end

				return true
			end
		end

		if pac and pac.CreateMove then pac.CreateMove(ucmd) end
	end
end

function battlecam.ShouldDrawLocalPlayer()
	return true
end

function battlecam.PreDrawHUD()
	battlecam.player_visibility = util.PixelVisible(LocalPlayer():EyePos(), LocalPlayer():BoundingRadius()*3, battlecam.pixvis)

	local ent = jtarget.GetEntity(LocalPlayer())
	if ent:IsValid() then
		battlecam.enemy_visibility = util.PixelVisible(ent:EyePos(), ent:BoundingRadius()*6, battlecam.pixvis2)
	end
end

concommand.Add("battlecam", function()
	if battlecam.IsEnabled() then
		battlecam.Disable()
	else
		battlecam.Enable()
	end
end)

if battlecam.IsEnabled() then
	battlecam.Disable()
	battlecam.Enable()
end
