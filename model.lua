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
		__error = {},
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
	else
		table.insert(tq, ti)
		table.insert(self.__command_queue, func)
	end
end

local function do_command(self, i, queue_name)
	local ok, err = pcall(self.__command_queue[i], self[queue_name], self.__command_time[i])
	if ok then
		return
	else
		local ti = self.__command_time[i]
		self.__error[ti] = err
		return true	-- failed
	end
end

local function remove_error(self)
	local time = self.__command_time
	local queue = self.__command_queue
	for ti in pairs(self.__error) do
		for i=1,#time do
			if time[i] == ti then
				table.remove(time, i)
				table.remove(queue, i)
				break
			end
		end
	end
end

local function rollback_state(self)
	local tq = self.__command_time
	local command = self.__command_queue
	deepcopy(self.__base, self.__state)
	local err
	for i=1, #tq do
		if tq[i] > self.__current then
			return
		end
		err = do_command(self, i, "__state") or err
	end
	if err then
		remove_error(self)
	end
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

function model:advance(ti)
	local last = self.__current
	local command = self.__command_queue
	local tq = self.__command_time
	assert(ti > last)
	if ti > self.__basetime + TIME_ROLLBACK then
		-- erase expired command
		local basetime = ti - TIME_ROLLBACK
		while tq[1] and tq[1] < basetime do
			do_command(self, 1, "__base")
			table.remove(tq,1)
			table.remove(command,1)
		end
	end
	local err
	for i=1, #tq do
		local t = tq[i]
		if t > ti then
			break
		elseif t > last then
			err = do_command(self, i, "__state") or err
		end
	end
	if err then
		remove_error(self)
	end
	self.__current = ti
end

function model:state()
	return self.__state
end

function model:clear_error()
	local err = self.__error
	for k,v in pairs(err) do
		-- todo: handle the error command
		print("clear error", k, v)
		err[k] = nil
	end
end

return model

