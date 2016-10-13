local function _copy(obj, target)
	local n = 0
	for k,v in pairs(target) do
		if type(v) == "table" then
			v.__del = true
			n = n + 1
		else
			target[k] = nil
		end
	end
	for k,v in pairs(obj) do
		if type(v) == "table" then
			local t = target[k]
			if t then
				t.__del = nil
				n = n - 1
			else
				t = {}
				target[k] = t
			end
			_copy(v, t)
		else
			target[k] = v
		end
	end
	if n > 0 then
		for k,v in pairs(target) do
			if type(v) == "table" and v.__del then
				target[k] = nil
			end
		end
	end
end

local function deepcopy(obj, target)
	target = target or {}
	_copy(obj, target)
	return target
end

--------------------

local model = {} ; model.__index = model
local TIME_ROLLBACK = 1000

function model.new(obj)
	local self = {
		__base = deepcopy(obj),
		__state = deepcopy(obj),
		__basetime = 0,	-- the time before __basetime can't be rollback
		__current = 0,	-- the time before __current ( == __current) is already apply to __state
		__command_time = {},
		__command_queue = {},
		__command_error = {},	-- mark the error command
	}
	return setmetatable(self, model)
end

local function queue_command(self, ti, func)
	local tq = self.__command_time
	local idx
	for i=1,#tq do
		local t = tq[i]
		if t > ti then
			idx = i
			break
		end
		assert (t < ti , "the timestamp never the same")
	end
	if idx then
		table.insert(tq, idx, ti)
		table.insert(self.__command_queue, idx, func)
		table.insert(self.__command_error, idx, false)
	else
		table.insert(tq, ti)
		table.insert(self.__command_queue, func)
		table.insert(self.__command_error, false)
	end
end

local function do_command(self, i, queue_name)
	if self.__command_error[i] then
		return false -- skip
	end
	local ok, err = pcall(self.__command_queue[i], self[queue_name], self.__command_time[i])
	if ok then
		return
	else
		self.__command_error[i] = err
		return true	-- failed
	end
end

local function apply_command(self)
	local tq = self.__command_time
	for i=1, #tq do
		if tq[i] > self.__current then
			return
		end
		if do_command(self, i, "__state") then
			deepcopy(self.__base, self.__state)
			return apply_command(self) -- error, again
		end
	end
end

local function rollback_state(self)
	local command = self.__command_queue
	deepcopy(self.__base, self.__state)
	apply_command(self)
end

function model:command(ti, func)
	if ti < self.__basetime then
		return false	-- expired
	end
	queue_command(self, ti, func)
	if ti <= self.__current then
		rollback_state(self)
	end
	return true
end

local function advance_command(self, from)
	local tq = self.__command_time
	local ti = self.__current
	for i=from, #tq do
		local t = tq[i]
		if t > ti then
			break
		end
		if do_command(self, i, "__state") then
			deepcopy(self.__base, self.__state)
			return advance_command(self, from)
		end
	end
end

function model:advance(ti)
	assert(ti > self.__current)
	if ti > self.__basetime + TIME_ROLLBACK then
		-- erase expired command
		local basetime = ti - TIME_ROLLBACK
		local tq = self.__command_time
		local err = self.__command_error
		local command = self.__command_queue
		while tq[1] and tq[1] < basetime do
			do_command(self, 1, "__base")	-- ignore error
			table.remove(tq,1)
			table.remove(command,1)
			table.remove(err, 1)
		end
	end
	local tq = self.__command_time
	local last = self.__current
	self.__current = ti
	for i=1, #tq do
		local t = tq[i]
		if t > last then
			return advance_command(self, i)
		end
	end
end

function model:remove(ti)
	local tq = self.__command_time
	for i=1,#tq do
		if tq[i] == ti then
			table.remove(tq, i)
			table.remove(self.__command_queue, i)
			table.remove(self.__command_error, i)
			if ti <= self.__current then
				local err = self.__command_error
				-- reset error command, apply again
				for j=1,i do
					err[j] = false
				end
				rollback_state(self)
				return true	-- state change
			end
			return
		end
	end
end

function model:state()
	return self.__state
end

local function model_error(self, ti)
	local tq = self.__command_time
	local err = self.__command_error
	for i=1,#tq do
		if err[i] then
			if ti == nil or ti > tq[i] then
				return tq[i], err[i]
			end
		end
	end
end

function model:error()
	return model_error, self
end

function model:dump() -- debug use
	print(string.format("base time = %d , current time = %d", self.__basetime, self.__current))
	local tq = self.__command_time
	for i=1,#tq do
		print(i, tq[i], self.__command_queue[i], self.__command_error[i])
	end
end

return model

