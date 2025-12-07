local ServerScriptService = game:GetService("ServerScriptService")

local helper_requirements = require(ServerScriptService.helpers.requirements)
local helpers = ServerScriptService.helpers
local get_player = require(helpers.get_player)

local command = {}
command.topic = script.Name -- what topic the poller should listen for
command.global_check = helper_requirements.user_exists
print(command.topic)

-- what should happen once everything's verified
-- seperated just for readability
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

function command.execute(arguments)
	-- Arguments are stored in arrays.
	-- You can control how arguments are handled in the discord bot itself.
	-- Check out the discord-bot counterpart to see how this would work

	local target_id = arguments[1]
	local target_username = arguments[2]

	local player = get_player(target_username, tonumber(target_id))
	fling(player)
end

return command
