local Players = game:GetService("Players")
return {
	-- Assumes arguments is an array containg:
	-- [1] - the target id as an integer
	-- [2] - the target username
	user_exists = function(arguments)
		local id = arguments[1]
		local username = arguments[2]

		local exists = Players:GetPlayerByUserId(id)

		if username and not exists then
			for player: Player in Players:GetPlayers() do
				if player.Name == username then
					return true
				end
			end
		end

		return exists
	end,
}
