require("hdl/hdl");
require("hdl/code_generator");
require("logic/logic3");

Xor = module[[Xor]](
function ()
	a = input(bit);
	b = input(bit);
	o = output((a & ~b) | (~a & b));
end);

-- Calculate (a ~ b) ~ c using the Xor module from above.
Xor3 = module[[Xor3]](
function ()
	a = input(bit);
	b = input(bit);
	c = input(bit);

	xAB = Xor{a = a, b = b};
	xABC = Xor{a = xAB.o, b = c};

	o = output(xABC.o);
end);

local luaCode = generate_lua_sim(Xor3, "xor3");
local luafile = io.open("examples/lua/xor3.lua", "w");
luafile:write(luaCode);
luafile:close();

load(luaCode, "xor3", "t", _ENV)();

local zero = signalFromInt(0, 1);
local one = signalFromInt(1, 1);
assert(signalToInt(xor3(zero, zero, zero), 1) == 0, "xor3(0, 0, 0) failed");
assert(signalToInt(xor3(zero, zero, one), 1) == 1, "xor3(0, 0, 1) failed");
assert(signalToInt(xor3(zero, one, zero), 1) == 1, "xor3(0, 1, 0) failed");
assert(signalToInt(xor3(zero, one, one), 1) == 0, "xor3(0, 1, 1) failed");
assert(signalToInt(xor3(one, zero, zero), 1) == 1, "xor3(1, 0, 0) failed");
assert(signalToInt(xor3(one, zero, one), 1) == 0, "xor3(1, 0, 1) failed");
assert(signalToInt(xor3(one, one, zero), 1) == 0, "xor3(1, 1, 0) failed");
assert(signalToInt(xor3(one, one, one), 1) == 1, "xor3(1, 1, 1) failed");
print("All tests passed");