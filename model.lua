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

function model.new(obj, method, step)
	local self = {
		__base = deepcopy(obj),
		__state = deepcopy(obj),
		__command_time = {},
		__command_queue = {},
		__snapshot = 0,
		__snapinvalid = true,
		__method = method,
		__step = step or 1000,
	}
	return setmetatable(self, model)
end

function model:timestamp(id, ti)
	local step = self.__step
	assert(id < step)
	return ti * step + id
end

function model:time(ti)
	return (ti + 1) * self.__step - 1
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

local function insert_before(self, mode, idx, ti, method, ...)
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
	if mode == "replace" then
		idx = idx + 1
	end
	for i = idx, #tq do
		local f = cq[i]
		if not xpcall(m[f[1]], traceback, state, tq[i], tunpack(f, 2, f.n)) then
			rollback(self)
			return false, "Can't insert command"
		end
	end
	if mode == "insert" then
		table.insert(tq, idx, ti)
		table.insert(cq, idx, tpack(method, ...))
	else
		-- assert( mode == "replace" )
		idx = idx - 1
		tq[idx] = ti
		cq[idx] = tpack(method, ...)
	end
	return ti
end

-- call by server. mode can be "insert" "replace" "unique"
-- return false, err_message when failed ;
-- return timestamp, insert done, no error.
function model:apply_command(ti, mode, method, ...)
	local tq = self.__command_time
	local qlen = #tq
	if qlen >= QUEUE_LENGTH then
		local timeline = self.__command_time[1]
		if ti < timeline then
			return false, "command expired"
		end
		local f = self.__command_queue[1]
		f[1](self.__base, timeline, tunpack(f, 2, f.n))
		table.remove(tq,1)
		table.remove(self.__command_queue,1)
		qlen = qlen - 1
	end

	for i = 1, qlen do
		if ti == tq[i] then
			if mode == "unique" then
				return false, "command duplicate"
			elseif mode == "insert" then
				ti = ti + self.__step
			elseif mode == "replace" then
				return insert_before(self, "replace", i, ti, method, ...)
			else
				error("Invalid mode : " .. mode)
			end
		end
		if ti < tq[i] then
			return insert_before(self, "insert", i, ti, method, ...)
		end
	end
	local ok, err = xpcall(self.__method[method], traceback, self.__state, ti, ...)
	if ok then
		table.insert(tq, ti)
		table.insert(self.__command_queue, tpack(method, ...))
		return ti
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

-- call by client. mode can be "insert" "replace" "unique"
function model:queue_command(ti, mode, method, ...)
	local tq = self.__command_time
	local cq = self.__command_queue
	local m = self.__method
	for i = 1, #tq do
		if ti == tq[i] then
			if mode == "unique" then
				return false
			elseif mode == "insert" then
				ti = ti + self.__step
			elseif mode == "replace" then
				tq[i] = ti
				cq[i] = tpack(method,...)
				touch_snapshot(self, ti)
				return ti
			else
				error ("Invalid mode : " .. mode)
			end
		end
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
			return ti
		end
	end
	table.insert(tq, ti)
	table.insert(cq, tpack(method,...))
	touch_snapshot(self, ti)
	return ti
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

