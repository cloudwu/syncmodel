local model = require "model"
local print_r = require "print_r"

local function sub1(obj, ti)
	obj.a = obj.a - 1
	assert(obj.a >= 0)

	print("Time =", ti)
	print("a = a - 1", obj.a)
end

local function add2(obj, ti)
	obj.a = obj.a + 2

	print("Time =", ti)
	print("a = a + 2", obj.a)
end

local client1 = model.new { a = 1 }
local client2 = model.new { a = 1 }
local server = model.new { a = 1 }

client1:queue_command(10, sub1)
client1:queue_command(20, add2)
assert(server:apply_command(10, sub1))
assert(server:apply_command(20, add2))


client2:queue_command(11, sub1)
client2:queue_command(21, add2)
assert(server:apply_command(11, sub1) == false)
assert(server:apply_command(21, add2))

local ti, state = server:current_state()
print("--- Server time:", ti)
print_r(state)

client1:queue_command(21, add2)
print("--- Client1 time:", 30)
print_r(client1:snapshot(30))

client2:queue_command(10, sub1)
client2:queue_command(20, add2)
client2:remove_command(11)
print("--- Client2 time:", 30)
print_r(client2:snapshot(30))
