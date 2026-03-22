--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local PollerParent = ServerScriptService.polling

local PollerRef = PollerParent.main
local PollerClass = require(PollerRef)

local config = require(ServerScriptService.polling.configs.config)
local commands_folder = PollerParent.commands

local poller = PollerClass.new(config)

-- Initializing commands from the commands folder

-- you could honestly have commands in standalone
-- modules scripts, but this is how discordjs does it,
-- so i'll be doing the same

type command = {
	topic: string,
	execute: PollerClass.callback,
	global_check: PollerClass.callback?,
}

for _, category: Folder in commands_folder:GetChildren() do
	for _, command: ModuleScript? in category:GetChildren() do
		if not command:IsA("ModuleScript") then
			continue
		end

		local module: command = require(command)
		poller:on(module.topic, module.execute, module.global_check)

		print(`Registered command: {module.topic}`)
	end
end

poller:init()
