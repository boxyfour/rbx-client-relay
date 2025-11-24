local Players = game:GetService("Players")
--!strict

local helper_requirements = require(script.helper_requirements)
local config = require(script.config)
local poller = require(script.polling).new(config)

poller:init()

local function fling(player: Player)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid_root = character.HumanoidRootPart
	local humanoid = character.Humanoid
	humanoid.Sit = true

	local force = Instance.new("VectorForce")
	local attachment = Instance.new("Attachment")
	force.Force = Vector3.new(99999, 99999, 99999)
	force.Attachment0 = attachment
	force.Parent = attachment
	attachment.Parent = humanoid_root
end

poller:on_global("kick", function(arguments)
	local target_id = arguments[1]
	local target_username = arguments[2]

	local reason = arguments[3]

	local player

	if target_id then
		player = Players:GetPlayerByUserId(tonumber(target_id))
	end

	for _, child in Players:GetChildren() do
		if child.Name == target_username then
			player = child
		end
	end

	player:Kick(reason)
end, helper_requirements.user_exists)

poller:on_global("fling", function(arguments)
	print("hi")
	local target_id = arguments[1]
	local target_username = arguments[2]

	local player

	if target_id then
		player = Players:GetPlayerByUserId(tonumber(target_id))
	end

	for _, child in Players:GetChildren() do
		if child.Name == target_username then
			player = child
		end
	end

	fling(player)
end, helper_requirements.user_exists)
