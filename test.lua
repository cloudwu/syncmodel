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

local command1_c1 = client1:queue_command(client1:timestamp(1,1000), "insert", "dec")
local command2_c1 = client1:queue_command(client1:timestamp(1,2000), "insert", "add", 2)
assert(server:apply_command(command1_c1, "unique", "dec"))
assert(server:apply_command(command2_c1, "unique", "add", 2))


local command1_c2 = client2:queue_command(client2:timestamp(2,1000), "insert", "dec")
local command2_c2 = client2:queue_command(client2:timestamp(2,2000), "insert", "add", 2)
assert(server:apply_command(command2_c1, "unique", "dec") == false)
assert(server:apply_command(command2_c2, "unique", "add", 2))

local ti, state = server:current_state()
print("--- Server time:", ti)
print_r(state)

client1:queue_command(command1_c2, "unique", "add", 2)
print("--- Client1 time:", client1:time(3000))
print_r(client1:snapshot(client1:time(3000)))

client2:queue_command(command1_c1, "unique", "dec")
client2:queue_command(command2_c1, "unique", "add", 2)
client2:remove_command(command1_c1)
print("--- Client2 time:", client2:time(3000))
print_r(client2:snapshot(client2:time(3000)))
