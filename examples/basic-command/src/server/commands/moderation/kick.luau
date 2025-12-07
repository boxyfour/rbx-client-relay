local ServerScriptService = game:GetService("ServerScriptService")
local helper_requirements = require(ServerScriptService.helpers.requirements)

local helpers = ServerScriptService.helpers
local get_player = require(helpers.get_player)

local command = {}
command.topic = script.Name -- what topic the poller should listen for
command.global_check = helper_requirements.user_exists

function command.execute(arguments)
	-- Arguments are stored in arrays.
	-- You can control how arguments are handled in the discord bot itself.
	-- Check out the discord-bot counterpart to see how this would work

	local target_id = arguments[1]
	local target_username = arguments[2]
	local reason = arguments[3]

	local player = get_player(target_username, tonumber(target_id))

	-- no reason to verify the reason, since it doesn't matter if its nil or not
	-- if being nil DOES matter, please add guard clauses
	player:Kick(reason)
end

return command
