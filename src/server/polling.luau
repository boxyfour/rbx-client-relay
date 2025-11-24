--!strict
-- TODO:
--- TIMED REQUESTS

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local poller = {
	servers = {},
	commands = {
		status = "in_progress",
		action = "test",
	},
}
poller.__index = poller

local pollers = 0

-- helpers
-- wrapper for a pcall, times out after specified time
local function pcall_timeout(callback: () -> (), timeout: number)
	local success, result
	local finished = false
	local thread = task.spawn(function()
		local succ, res = pcall(callback)

		finished = true
		success, result = succ, res
	end)

	local start = os.clock()
	while not finished do
		-- stepping in somewhat small increments, doesn't need to be exact.
		task.wait(0.05)

		if os.clock() - start >= timeout then
			task.cancel(thread)
			return false, "Timed out"
		end
	end

	if not success then
		return success, result
	end

	return success, result
end

local function generate_name()
	pollers += 1
	return `poller {pollers}`
end

local function join_threads(callbacks: { () -> () })
	local completed_count = 0
	local completed_target = #callbacks
	local interval = 500 -- ms

	local threads = {}

	for _, callback in callbacks do
		table.insert(
			threads,
			task.spawn(function()
				callback()
				completed_count += 1
			end)
		)
	end

	while completed_count ~= completed_target do
		task.wait(interval)
	end
end

-- types

type server = { server_id: string, uptime: number, player_count: number }

type Config = {
	ip_address: string,
	port: number,
	secret: string?,

	-- seconds
	polling_delay: number,
	heartbeat_delay: number,
	timeout: number,

	verbose_logging: boolean?,
	verbose_errors: boolean?,
	name: string?,
}

type request = {
	topic: string,
	arguments: { any },
}

type action = {
	topic: string,
	arguments: { [number]: any },
	taken: boolean?,
	id: string,
}

function poller:error(text: string)
	local config = self.config

	if config.verbose_errors then
		warn(`{config.name}: {text}`)
	end
end

function poller:log(text: string)
	local config = self.config

	if config.verbose_logging then
		print(`{config.name}: {text}`)
	end
end

-- shorthand function to return a body
function poller:get_body(params, timeout)
	local pcall_closure = function()
		local request = HttpService:RequestAsync(params)

		return request.Body
	end

	local success, failure

	if not params then
		success, failure = pcall(pcall_closure)
	else
		success, failure = pcall_timeout(pcall_closure, timeout)
	end

	if not success then
		self:error("Get body failure")
		self:error(failure)
		return
	end

	-- if success, returns data
	return failure
end

-- deletes server
function poller:delete()
	if not self._poller_id then
		return
	end

	local parameters = {
		Url = `{self.ip}/servers/{self._poller_id}`,
		Method = "DELETE",
		Headers = self.headers,
	}

	local data = self:get_body(parameters, 1)

	if data then
		self:log("deleted server from pool")
		self:log(data)
	end
end

-- Registers the poller with the backend
function poller:register(): (boolean, string?)
	local parameters = {
		Url = `{self.ip}/servers`,
		Method = "POST",
		Body = HttpService:JSONEncode({
			player_count = #Players:GetChildren(),
			job_id = game.JobId,
		}),
		Headers = self.headers,
	}

	return self:get_body(parameters, self.config.timeout)
end

function poller:claim_action(action: action): boolean
	local parameters = {
		Url = `{self.ip}/servers/global/{self._poller_id}`,
		Method = "POST",
		Headers = self.headers,
		Body = HttpService:JSONEncode({
			id = action.id,
		}),
	}

	print("Trying to claim global action:", action)

	local body = self:get_body(parameters, 1)

	if not body then
		return
	end

	return HttpService:JSONDecode(body).success
end

-- returns servers
function poller:get_servers(): { server }?
	local parameters = {
		Url = `{self.ip}/servers`,
		Method = "GET",
		Headers = self.headers,
	}
	-- returns and errors anyway
	local data = self:get_body(parameters, 1)

	if not data then
		return
	end

	local servers = HttpService:JSONDecode(data)
	local valid = {}

	for _, server: server in servers do
		if server.server_id == self._poller_id then
			continue
		end

		table.insert(valid, server)
	end

	return servers
end

function poller:reregister()
	local parameters = {
		Url = `{self.ip}/servers`,
		Method = "POST",
		Body = HttpService:JSONEncode({
			player_count = #Players:GetChildren(),
			job_id = game.JobId,
			uptime = os.clock(),
			server_id = self._poller_id,
		}),
		Headers = self.headers,
	}

	return self:get_body(parameters, self.config.timeout)
end

-- updates server statistics
function poller:heartbeat()
	local parameters = {
		Url = `{self.ip}/servers/{self._poller_id}`,
		Method = "PATCH",
		Headers = self.headers,
		Body = HttpService:JSONEncode({
			server_id = self._poller_id,
			uptime = os.clock(),
			player_count = #Players:GetChildren(),
		}),
	}

	local data = self:get_body(parameters, 1)

	if not data then
		self:error(`failed to update server data on heartbeat`)

		if os.clock() - self.last_fail > self.reset_counter_interval then
			self.failed_counter = 0
		end

		self.failed_counter += 1
	end

	if self.failed_counter > self.maximum_fails then
		local success = self:reregister()

		if success then
			self.failed_counter = 0
		end
	end

	self.servers = self:get_servers()
end

-- polls the server for new commands
function poller:poll()
	local closure = function()
		local function handle_request(request: action)
			if request.id and not self:claim_action(request) then
				print("already claimed action!")
				return
			end

			local listeners = self._listeners[request.topic]
			local requirements = self._requirements

			if requirements then
				for _, requirement in requirements do
					if not requirement(request.arguments) then
						return
					end
				end
			end

			if not listeners then
				return
			end

			task.spawn(function()
				for _, listener in listeners do
					listener(request.arguments)
				end
			end)
		end

		local parameters = {
			Url = `{self.ip}/servers/{self._poller_id}/messages`,
			Method = "GET",
			Headers = self.headers,
		}
		local global_params = {
			Url = `{self.ip}/servers/global/messages`,
			Method = "GET",
			Headers = self.headers,
		}

		local thread_2 = function()
			local global_messages = self:get_body(global_params, self.config.timeout)
			if global_messages then
				local global_messages = HttpService:JSONDecode(global_messages).data

				for _, request in global_messages do
					handle_request(request)
				end
			end
		end

		local thread_1 = function()
			local server_messages = self:get_body(parameters, self.config.timeout)
			if server_messages then
				local server_messages = HttpService:JSONDecode(server_messages).data

				for _, request in server_messages do
					handle_request(request)
				end
			end
		end

		local threads = { thread_1, thread_2 }
		join_threads(threads)

		return true
	end

	local success, data = pcall_timeout(function()
		return closure()
	end, self.config.timeout)

	if not success then
		self:error(`polling failed, likely no messages: {data}`)
	end
end

-- continuously polls
function poller:listen()
	self._heartbeat = task.spawn(function()
		while true do
			self:heartbeat()

			task.wait(self.config.heartbeat_delay)
		end
	end)

	self._poll = task.spawn(function()
		while true do
			if self._listening then
				self:poll()
			end
			task.wait(self.config.polling_delay)
		end
	end)
end

-- registers & polls
function poller:init()
	local start_reg = os.clock()
	local body = self:register()
	local end_reg = os.clock()

	if not body then
		self:error("Failed to get an id / response from the server.")
		self:error(`Error: {tostring(body)}`)
		return
	end

	body = HttpService:JSONDecode(body)

	self._poller_id = tostring(body.id)

	self:log(`successfully registered, with id: {body.id} in {math.round((end_reg - start_reg) * 100) / 100} seconds`)
	self:listen()
end

function poller.new(config: Config)
	config.name = config.name or generate_name()

	local self = setmetatable({}, poller)
	self.config = config
	self.ip = `http://{self.config.ip_address}:{tostring(self.config.port)}`
	self._listeners = {}
	self._requirements = {}

	self._listening = true
	self.headers = {
		["Content-Type"] = "application/json",
		["Authentication"] = self.config.secret,
	}

	-- failsafes if the server goes down
	self.maximum_fails = 3
	self.failed_counter = 0
	self.last_fail = 0

	-- after 100 heartbeats
	self.reset_counter_interval = config.heartbeat_delay * 100 * 1000

	game:BindToClose(function()
		self:delete()
	end)

	return self
end

-- Listens on the servers' "/servers/:id/messages" for any commands. Returns the callback count
function poller:on(topic: string, callback: (arguments: { any }) -> any): number
	self._listeners[topic] = self._listeners[topic] or {}
	table.insert(self._listeners[topic], callback)

	return #self._listeners[topic]
end

--[[
poller:on_global functions very similarly to poller:on.
The only difference is, it requires you to pass a "requirements" callback.
The callback determines whether or not the server can run the callback. If it can, it'll true. Otherwise, the callback will return false.

Differences include:
* There can only be one requirement per topic. (allowing multiple would assume only that requirement applies for that listener)
]]
function poller:on_global(topic: string, callback: (arguments: { any }) -> any, server_can_run: () -> ()): number
	self._listeners[topic] = self._listeners[topic] or {}
	self._requirements[topic] = server_can_run
	table.insert(self._listeners[topic], callback)

	return #self._listeners[topic]
end

return poller
