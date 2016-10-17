local model = require "model"
local print_r = require "print_r"

local method = {}

function method.dec(obj, ti)
	obj.a = obj.a - 1
	assert(obj.a >= 0)

	print("Time =", ti)
	print("a = a - 1", obj.a)
end

function method.add(obj, ti, n)
	obj.a = obj.a + n

	print("Time =", ti)
	print("a = a + ", n, obj.a)
end

local client1 = model.new ( { a = 1 } , method)
local client2 = model.new ({ a = 1 } , method)
local server = model.new ({ a = 1 }, method)

client1:queue_command(10, "dec")
client1:queue_command(20, "add", 2)
assert(server:apply_command(10, "dec"))
assert(server:apply_command(20, "add", 2))


client2:queue_command(11, "dec")
client2:queue_command(21, "add", 2)
assert(server:apply_command(11, "dec") == false)
assert(server:apply_command(21, "add", 2))

local ti, state = server:current_state()
print("--- Server time:", ti)
print_r(state)

client1:queue_command(21, "add", 2)
print("--- Client1 time:", 30)
print_r(client1:snapshot(30))

client2:queue_command(10, "dec")
client2:queue_command(20, "add", 2)
client2:remove_command(11)
print("--- Client2 time:", 30)
print_r(client2:snapshot(30))
