local Players = game:GetService("Players")
-- Returns a player instance from either the player's id or username.

function search_players(username: string)
	for _, player: Player in Players:GetChildren() do
		if player.Name == username then
			return player
		end
	end
end

return function(username: string, id: number)
	local player

	if id then
		player = Players:GetPlayerByUserId(id)
	end

	if not player and username then
		player = search_players(username)
	end

	return player
end
