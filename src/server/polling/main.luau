--!strict

-- Romoderator
-- Hello!

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local polling_modules = script.Parent
local heartbeat = require(polling_modules.heartbeat)

local poller = {}
poller.__index = poller

-- TODO: Rewrite this
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
		task.wait(0.05)

		-- checks if the current time passed exceeds the allotted time
		if os.clock() - start >= timeout then
			task.cancel(thread)
			return false, "Timed out"
		end
	end

	return success, result
end

-- Runs callbacks in a thread until each are finished.
local function join_threads(callbacks: { () -> () })
	local completed_count = 0
	local completed_target = #callbacks
	local interval = 0.1

	local threads = {}

	for _, callback in callbacks do
		table.insert(
			threads,
			task.spawn(function()
				callback()
				-- updates the completed thread count, since this thread has finished it's callback
				completed_count += 1
			end)
		)
	end

	while completed_count ~= completed_target do
		task.wait(interval)
	end
end

type server = { server_id: string, uptime: number, player_count: number }

export type callback = (any) -> ()

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

-- Error logging

function poller:error(text: string)
	local config = self.config

	if config.verbose_errors then
		warn(`{config.name}: {text}`)
	end
end

-- Logging

function poller:log(text: string)
	local config = self.config

	if config.verbose_logging then
		print(`{config.name}: {text}`)
	end
end

-- Returns the body of any request.
-- Doesn't decode the JSON body
function poller:get_body(params: { [string]: string }, timeout: number?): string?
	local pcall_closure = function()
		local request = HttpService:RequestAsync(params)

		return request.Body
	end

	local success, failure

	if not timeout then
		success, failure = pcall(pcall_closure)
	else
		success, failure = pcall_timeout(pcall_closure, timeout)
	end

	if not success then
		self:error("Get body failure")
		self:error(failure)
		return
	end

	-- failure is guaranteed to be either a (json decoded) string or nil
	return failure
end

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
	else
		self:error("failed to delete server!")
	end
end

function poller:register(): string?
	local parameters = {
		Url = `{self.ip}/servers`,
		Method = "POST",
		Body = HttpService:JSONEncode({
			player_count = #Players:GetChildren(),
			job_id = game.JobId,
		}),
		Headers = self.headers,
	}

	-- Returns whatever response it gets (or none)
	return self:get_body(parameters, self.config.timeout)
end

-- Attempts to "claim" a global action.
-- Certain operations (like adding currency to a player, or kicking a player) only need to be done once.
-- So, this function tries to claim an action in order to prevent other pollers from doing the same.
function poller:claim_action(action: action): boolean
	local parameters = {
		Url = `{self.ip}/servers/global/{self._poller_id}`,
		Method = "POST",
		Headers = self.headers,
		Body = HttpService:JSONEncode({
			id = action.id,
		}),
	}

	-- get the server's response
	local body = self:get_body(parameters, 1)

	-- server likely didn't reply, or it's down
	if not body then
		return false
	end

	-- the request didn't fail, so we return the "success" field of the json response (which is a bool)
	return HttpService:JSONDecode(body).success
end

-- Re-registers with the backend in the event that the server closes down.
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

-- Updates server statistics, and re-registers with the server in the event it goes down.
function poller:heartbeat()
	local parameters = {
		Url = `{self.ip}/servers/{self._poller_id}`,
		Method = "PATCH",
		Headers = self.headers,
		Body = HttpService:JSONEncode({
			server_id = self._poller_id,
			uptime = os.clock(),
			player_count = #Players:GetChildren(),
			custom = heartbeat(),
		}),
	}

	local data = self:get_body(parameters, 1)

	if not data then
		self:error(`failed to update server data on heartbeat`)

		-- sometimes request fail (which is normal), so we reset the failed counter to avoid re-registering a perfectly alive server
		if os.clock() - self.last_fail > self.reset_counter_interval then
			self.failed_counter = 0
		end

		self.last_fail = os.clock()
		self.failed_counter += 1
	end

	-- re-registers with the backend if the server hasn't replied within self.maximum_fails
	if self.failed_counter > self.maximum_fails then
		local success = self:reregister()

		--  resetting the counter here so we don't re-register on a server that's alive
		if success then
			self.failed_counter = 0
		end
	end
end

--[[
Polls the backend for any new incoming messages and executes them.

Sends a long-poll request to:
 * /servers/:id/messages
 * /servers/global/messages
for requests,

Each endpoint is polled on a seperate thread to avoid blocking, and assumes each endpoint retunrs
a JSON body with the members of type "action".

Every request is then handled, being "claimed" if it's a global action, and ran normally otherwise.

]]
function poller:poll()
	-- set as a local function to act as a priv method
	local function handle_request(request: action)
		-- if we can't claim the global action, then we just don't pursue
		if request.id and not self:claim_action(request) then
			return
		end

		local listeners = self._listeners[request.topic]
		local requirements = self._requirements[request.topic]

		-- loop over all requirements (if they exist)
		-- and execute them with the command arguments.
		-- if we fail ANY requirement, then we don't run the command
		if requirements then
			for _, requirement in requirements do
				if not requirement(request.arguments) then
					return
				end
			end
		end

		-- if there's no listeners, don't need to run them either
		if not listeners then
			return
		end

		-- summons a new thread to run the listeners, as handle_request is ran in a synchronous loop. (meaning every request runs this closure)
		-- this avoids spending unnecessary time on executing commands
		task.spawn(function()
			for _, listener in listeners do
				listener(request.arguments)
			end
		end)
	end

	-- Polls all endpoints, runs functions if there's a message from the server.
	local success, data = pcall_timeout(function()
		-- polls for server-specific actions
		local parameters = {
			Url = `{self.ip}/servers/{self._poller_id}/messages`,
			Method = "GET",
			Headers = self.headers,
		}

		-- polls for global actions
		local global_params = {
			Url = `{self.ip}/servers/global/messages`,
			Method = "GET",
			Headers = self.headers,
		}

		-- each endpoint is polled using seperate threads to avoid blocking each other
		-- it also wraps up very nicely later when we use join_threads

		local thread_2 = function()
			local global_messages = self:get_body(global_params, self.config.timeout)

			-- if we have a response
			if global_messages then
				-- gets all messages returned from the endpoint
				local global_messages = HttpService:JSONDecode(global_messages).data

				-- handles each request individually
				for _, request in global_messages do
					handle_request(request)
				end
			end
		end

		local thread_1 = function()
			local server_messages = self:get_body(parameters, self.config.timeout)

			-- if we have a response
			if server_messages then
				-- gets all messages returned from the endpoint
				local server_messages = HttpService:JSONDecode(server_messages).data

				-- handles each request individually
				for _, request in server_messages do
					handle_request(request)
				end
			end
		end

		-- place each thread in a table for join_threads
		local threads = { thread_1, thread_2 }

		-- waits for each thread to be completed before returning
		join_threads(threads)

		return true
	end, self.config.timeout)

	-- error if the server doesn't reply
	if not success then
		self:error(`polling failed, likely no messages: {data}`)
	end
end

-- Creates threads to continuously poll & send heartbeats
function poller:listen()
	-- we create new threads so that each method can run independently without blocking the other.
	self._heartbeat = task.spawn(function()
		while true do
			-- doesn't check for _listening, since if we don't heartbeat, the server doesn't know we're alive
			self:heartbeat()

			task.wait(self.config.heartbeat_delay)
		end
	end)

	self._poll = task.spawn(function()
		while true do
			-- doesn't poll if _listening is disabled
			if self._listening then
				self:poll()
			end
			task.wait(self.config.polling_delay)
		end
	end)
end

-- Registers the server and listens
function poller:init()
	-- stores when we register, used for seeing how long it took to register with the backend
	local start_reg = os.clock()

	-- what response we got from registering
	local body = self:register()

	-- the time at which we finished regstering
	local end_reg = os.clock()

	-- only runs if we failed to register
	if not body then
		self:error("Failed to get an id / response from the server.")
		self:error(`Error: {tostring(body)}`)
		return
	end

	body = HttpService:JSONDecode(body)
	-- set our poller_id for re-registering the server if the backend goes down, and if we want to delete the server
	self._poller_id = tostring(body.id)

	-- funky math to round seconds to two decimal places
	self:log(`successfully registered, with id: {body.id} in {math.round((end_reg - start_reg) * 100) / 100} seconds`)

	-- continuously poll and update server statistics
	self:listen()
end

-- Creates the poller class
function poller.new(config: Config)
	assert(_G.POLLEREXISTS ~= true, "Only one poller should exist")
	_G.POLLEREXISTS = true

	config.name = config.name or "SingletonPoller"

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

	-- time it takes to reset failures
	self.reset_counter_interval = config.heartbeat_delay * 100

	game:BindToClose(function()
		self:delete()
	end)

	return self
end

--[[
Listens for global / server-specific commands with the same topic, returns the callback count

Callback refers to what's ran after the command is validated by global_check. Global_check should only be used if you're listening for global commands. Otherwise, just check if you can run the command in the callback body.

global_check is called with the action's arguments.

TODO:
* Make global and server-specific actions indistinguishable
]]
function poller:on(topic: string, callback: callback, global_check: callback?): number
	-- creates a table (acting as an array) for all topic callbacks and requirements if it doesn't exist
	self._listeners[topic] = self._listeners[topic] or {}
	self._requirements[topic] = self._requirements[topic] or {}

	-- insert our callback (and requirement) so we can run it, if a command with the same "topic" is received
	table.insert(self._listeners[topic], callback)

	if global_check then
		table.insert(self._requirements[topic], global_check)
	end

	return #self._listeners[topic]
end

return poller
