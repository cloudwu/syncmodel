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
local QUEUE_LENGTH = 100	-- cache max command
local traceback = debug.traceback
local tpack = table.pack
local tunpack = table.unpack

function model.new(obj, method)
	local self = {
		__base = deepcopy(obj),
		__state = deepcopy(obj),
		__command_time = {},
		__command_queue = {},
		__snapshot = 0,
		__snapinvalid = true,
		__method = method
	}
	return setmetatable(self, model)
end

--- for server side

local function rollback(self)
	local state = deepcopy(self.__base, self.__state)
	local tq = self.__command_time
	local cq = self.__command_queue
	local m = self.__method
	for i = 1, #tq do
		local f = cq[i]
		m[f[1]](state, tq[i], tunpack(f, 2, f.n))
	end
end

local function insert_before(self, idx, ti, method, ...)
	local state = deepcopy(self.__base, self.__state)
	local tq = self.__command_time
	local cq = self.__command_queue
	local m = self.__method
	for i = 1, idx-1 do
		local f = cq[i]
		m[f[1]](state, tq[i], tunpack(f, 2, f.n))
	end
	local ok , err = xpcall(m[method], traceback, state, ti, ...)
	if not ok then
		rollback(self)
		return false, err
	end
	for i = idx, #tq do
		local f = cq[i]
		if not xpcall(m[f[1]], traceback, state, tq[i], tunpack(f, 2, f.n)) then
			rollback(self)
			return false, "Can't insert command"
		end
	end
	table.insert(tq, idx, ti)
	table.insert(cq, idx, tpack(method, ...))
	return true
end

-- call by server.
-- return false, err_message when failed ;
-- return true, insert done, no error.
function model:apply_command(ti, method, ...)
	local tq = self.__command_time
	local qlen = #tq
	if qlen >= QUEUE_LENGTH then
		local timeline = self.__command_time[1]
		if ti < timeline then
			return false, "command expired"
		end
		tq[1](self.__base, timeline)
		table.remove(tq,1)
		table.remove(self.__command_queue,1)
	end

	for i = 1, qlen do
		if ti < tq[i] then
			return insert_before(self, i, ti, method, ...)
		end
	end
	local ok, err = xpcall(self.__method[method], traceback, self.__state, ti, ...)
	if ok then
		table.insert(tq, ti)
		table.insert(self.__command_queue, tpack(method, ...))
		return true
	end
	return false, err
end

function model:current_state()
	local tq = self.__command_time
	return tq[#tq] or 0, self.__state
end

function model:base_state()
	return self.__base_state, self.__command_time, self.__command_queue
end

------for client side

local function touch_snapshot(self, ti)
	if ti < self.__snapshot then
		self.__snapinvalid = true
	end
end

function model:queue_command(ti, method, ...)
	local tq = self.__command_time
	local cq = self.__command_queue
	local m = self.__method
	for i = 1, #tq do
		assert(ti ~= tq[i])
		if ti < tq[i] then
			if i > QUEUE_LENGTH and tq[1] < self.__snapshot then
				local f = cq[1]
				if not pcall(m[f[1]], self.__base, tq[1], tunpack(f, 2, f.n)) then
					return false
				end
				table.move(tq, 2, i, 1)
				table.move(cq, 2, i, 1)
				tq[i] = ti
				cq[i] = method
			else
				table.insert(tq, i, ti)
				table.insert(cq, i, tpack(method, ...))
			end
			touch_snapshot(self, ti)
			return true
		end
	end
	table.insert(tq, ti)
	table.insert(cq, tpack(method,...))
	touch_snapshot(self, ti)
	return true
end

function model:remove_command(ti)
	local tq = self.__command_time
	local cq = self.__command_queue
	for i = 1, #tq do
		local t = tq[i]
		if t == ti then
			table.remove(tq, i)
			table.remove(cq, i)
			touch_snapshot(self, ti)
			return true
		end
		if t > ti then
			break
		end
	end
	return false
end

function model:snapshot(ti)
	assert(ti >= self.__snapshot)
	local state = self.__state
	local idx
	local tq = self.__command_time
	local cq = self.__command_queue
	local m = self.__method
	if self.__snapinvalid then
		deepcopy(self.__base, self.__state)
		idx = #tq + 1
		for i=1, #tq do
			local t = tq[i]
			if t > self.__snapshot then
				self.__snapinvalid = false
				idx = i
				break
			end
			local f = cq[i]
			if not pcall(m[f[1]], state, t, tunpack(f, 2, f.n)) then
				return	-- failed
			end
		end
	else
		idx = #tq + 1
		for i=1, idx - 1 do
			if tq[i] > self.__snapshot then
				idx = i
				break
			end
		end
	end
	for i = idx, #tq do
		local t = tq[i]
		if t > ti then
			break
		end
		local f = cq[i]
		if not pcall(m[f[1]], state, t, tunpack(f, 2, f.n)) then
			self.__snapinvalid = true
			return -- failed
		end
	end
	self.__snapshot = ti
	return state
end

return model

