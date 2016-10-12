local model = require "model"
local print_r = require "print_r"

local function foo1(obj, ti)
	obj.a = obj.a + 1
	obj.b = obj.b * obj.a

	print("Time =", ti)
	print("a = a + 1", obj.a)
	print("b = b * a", obj.b)
end

local function foo2(obj, ti)
	obj.b = obj.b + 1
	obj.a = obj.a * obj.b

	print("Time =", ti)
	print("b = b + 1", obj.b)
	print("a = a * b", obj.a)
end

local m = model.new { a = 1, b = 2 }
m:command(3, foo1)
m:command(2, foo2)

print_r(m:state())
m:advance(2)
print_r(m:state())
m:advance(3)
print_r(m:state())
m:command(1, foo1)
m:advance(4)
print_r(m:state())



