local LUA_INTEGER = 32;

local kChar0 = string.byte('0');
local kChar1 = string.byte('1');
local kCharDash = string.byte('-');

function signalFromInt(x, size)
	local mask = (1 << size) - 1;
	x = x & mask;
	return { mask - x, x };
end

-- "0" = 01
-- "1" = 10
-- "-" = 11
function signalFromString(str)
	local size = str:len();
	local bytes = { str:byte(1, size) };

	local s0 = 0;
	local s1 = 0;
	for i=1,size do
		local bitID = i - 1;
		local b = bytes[size - bitID];
		if(b == kChar0) then
			s0 = s0 | (1 << bitID);
		elseif(b == kChar1) then
			s1 = s1 | (1 << bitID);
		else
			s0 = s0 | (1 << bitID);
			s1 = s1 | (1 << bitID);
		end
	end

	return { s0, s1 };
end

function signalToInt(x, size)
	local mask = (1 << size) - 1;
	local x0 = x[1] & mask;
	local x1 = x[2] & mask;
	if((x0 & x1) ~= 0) then
		return "U";
	elseif((x0 | x1) == 0) then
		return "-";
	end
	return x1;
end

function signalUndefined(size)
	size = size or LUA_INTEGER;
	local max = (1 << size) - 1;
	return { max, max };
end

function signalUninitialized()
	return { 0, 0 };
end

function signalIsEqual(a, b, size)
	local x0 = a[1] ~ b[1];
	local x1 = a[2] ~ b[2];
	local mask = (1 << size) - 1;
	return ((x0 | x1) & mask) == 0;
end

function signalIsUndefined(a)
	return (a[1] & a[2]) ~= 0;
end

function signalIsUninitialized(a)
	return (a[1] | a[2]) == 0;
end

function not1(a)
	return { 
		a[2],
		a[1]
	};
end

function and2(a, b)
	return {
		a[1] | b[1],
		a[2] & b[2]
	};
end

function or2(a, b)
	return { 
		a[1] & b[1],
		a[2] | b[2]
	};
end

function nand2(a, b)
	return {
		a[2] & b[2],
		a[1] | b[1]
	};
end

function nor2(a, b)
	return {
		a[2] | b[2],
		a[1] & b[1]
	};
end

function xor2(a, b)
	return {
		(a[2] & b[2]) | (a[1] & b[1]),
		(a[1] & b[2]) | (a[2] & b[1])
	};
end

function andn(...)
	local args = { ... };
	assert(#args >= 2);

	local a1 = args[1];
	local r0 = a1[1];
	local r1 = a1[2];
	for i=2,#args do
		local a = args[i];
		r0 = r0 | a[1];
		r1 = r1 & a[2];
	end
	return { r0, r1 };
end

function orn(...)
	local args = { ... };
	assert(#args >= 2);

	local a1 = args[1];
	local r0 = a1[1];
	local r1 = a1[2];
	for i=2,#args do
		local a = args[i];
		r0 = r0 & a[1];
		r1 = r1 | a[2];
	end
	return { r0, r1 };
end

function nandn(...)
	local args = { ... };
	assert(#args >= 2);

	local a1 = args[1];
	local r0 = a1[1];
	local r1 = a1[2];
	for i=2,#args do
		local a = args[i];
		r0 = r0 | a[1];
		r1 = r1 & a[2];
	end
	return { r1, r0 };
end

function norn(...)
	local args = { ... };
	assert(#args >= 2);

	local a1 = args[1];
	local r0 = a1[1];
	local r1 = a1[2];
	for i=2,#args do
		local a = args[i];
		r0 = r0 & a[1];
		r1 = r1 | a[2];
	end
	return { r1, r0 };
end

function index(x, i)
	local shift = i - 1;
	local x0 = (x[1] >> shift) & 1;
	local x1 = (x[2] >> shift) & 1;
	return { x0, x1 };
end

function concat(...)
	local args = {...};

	local x0 = 0;
	local x1 = 0;
	for i=1,#args do
		local ai = args[i];
		local ai0 = ai[1] & 1;
		local ai1 = ai[2] & 1;
		local shift = i - 1;

		x0 = x0 | (ai0 << shift);
		x1 = x1 | (ai1 << shift);
	end
	return { x0, x1 };
end
