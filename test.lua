local model = require "model"
local print_r = require "print_r"

local function foo1(obj, ti)
	assert(obj.a < 5 , string.format("a=%d b=%d ti=%d", obj.a,obj.b, ti))
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

print_r(m:state())	-- a=1, b=2
m:advance(2)
print_r(m:state())	-- a=3, b=3
m:advance(3)
print_r(m:state())	-- a=4, b=12
m:command(1, foo1)

for ti, msg in m:error() do
	print("ERR:",ti,msg)	-- a=10 b=5 ti=3
end

m:remove(2)
m:advance(4)
print_r(m:state())

m:dump()

m:command(2000, foo2)
m:command(2001, foo1)
m:advance(2000)
print_r(m:state())

m:advance(2001)
for ti, msg in m:error() do
	print("ERR:",ti,msg)
end


