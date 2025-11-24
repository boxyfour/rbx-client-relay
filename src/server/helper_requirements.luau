local Players = game:GetService("Players")
local requirements = {
	user_exists = function(arguments: { any })
		local target_id = arguments[1]
		local target_username = arguments[2]

		if target_id then
			return not not Players:GetPlayerByUserId(tonumber(target_id))
		end

		for _, player in Players:GetChildren() do
			if player.Name == target_username then
				return true
			end
		end
	end,
}

return requirements
