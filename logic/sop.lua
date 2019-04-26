local memoize = require('../util/memoize');

local kChar0 = string.byte('0');
local kChar1 = string.byte('1');
local kCharDash = string.byte('-');

local kInputContainment = {
	{ 1, 0, 0 },
	{ 0, 1, 0 },
	{ 2, 2, 1 }
};

local kOutputContainment = {
	[0] = { [0] = 1, [1] = 0 },
	[1] = { [0] = 2, [1] = 1 }
};

cubeDesc = memoize(function (numInputs, numOutputs)
	return {
		ni = numInputs,
		no = numOutputs
	};
end);

function cubeEmpty(numInputs, numOutputs)
	local c = {};
	c.desc = cubeDesc(numInputs, numOutputs);
	for i=1,numInputs + numOutputs do
		c[i] = 0;
	end
	return c;
end

-- Creates a cube representing the total universe (U)
-- X X X ... X | 1 1 ... 1
function cube_U(numInputs, numOutputs)
	local c = {};
	for i=1,numInputs do
		c[i] = 3;
	end

	for i=1,numOutputs do
		c[numInputs + i] = 1;
	end

	c.desc = cubeDesc(numInputs, numOutputs);

	return c;
end

-- Creates a cube representing the universe in the j-th Boolean space (uj)
-- X X X ... X | 0 0 ... 0 1 0 ... 0
function cube_uj(numInputs, numOutputs, j)
	local c = {};
	for i=1,numInputs do
		c[i] = 3;
	end

	for i=1,numOutputs do
		c[numInputs + i] = 0;
	end
	c[numInputs + j] = 1;

	c.desc = cubeDesc(numInputs, numOutputs);

	return c;
end

-- Creates a cube representing the positive half-space of the literal xj
-- X X ... X 1 X ... X | 1 1 ... 1
function cube_xj1(numInputs, numOutputs, j)
	local c = {};
	for i=1,numInputs do
		c[i] = 3;
	end
	c[j] = 2;

	for i=1,numOutputs do
		c[numInputs + i] = 1;
	end

	c.desc = cubeDesc(numInputs, numOutputs);

	return c;
end

-- Creates a cube representing the negative half-space of the literal xj
-- X X ... X 0 X ... X | 1 1 ... 1
function cube_xj0(numInputs, numOutputs, j)
	local c = {};
	for i=1,numInputs do
		c[i] = 3;
	end
	c[j] = 1;

	for i=1,numOutputs do
		c[numInputs + i] = 1;
	end

	c.desc = cubeDesc(numInputs, numOutputs);

	return c;
end

function cube_xj(numInputs, numOutputs, j)
	local desc = cubeDesc(numInputs, numOutputs);

	local c0 = { desc = desc };
	local c1 = { desc = desc };
	for i=1,numInputs do
		c0[i] = 3;
		c1[i] = 3;
	end
	c0[j] = 1;
	c1[j] = 2;

	for i=1,numOutputs do
		c0[numInputs + i] = 1;
		c1[numInputs + i] = 1;
	end

	return c0, c1;
end

function cube(inputs, outputs)
	local ni = #inputs;
	local no = outputs and #outputs or 1;

	local c = { desc = cubeDesc(ni, no) };
	for i=1,ni do
		c[i] = inputs[i];
	end

	if(not outputs) then
		c[ni + 1] = 1;
	else
		for i=1,no do
			c[ni + i] = outputs[i];
		end
	end

	return c;
end

function cubeFromStrings(inputsStr, outputsStr)
	local inputBytes = { inputsStr:byte(1, inputsStr:len()) };
	local inputs = {};
	for i=1,#inputBytes do
		local b = inputBytes[i];
		if(b == kChar0) then
			inputs[i] = 1;
		elseif(b == kChar1) then
			inputs[i] = 2;
		else
			inputs[i] = 3;
		end
	end

	local outputs = {};
	if(not outputsStr) then
		outputs[1] = 1;
	else
		local outputBytes = { outputsStr:byte(1, outputsStr:len()) };
		for i=1,#outputBytes do
			local b = outputBytes[i];
			if(b == kChar1) then
				outputs[i] = 1;
			else
				outputs[i] = 0;
			end
		end
	end

	return cube(inputs, outputs);
end

function cubeToStrings(c)
	local desc = c.desc;
	local ni = desc.ni;
	local no = desc.no;

	local inputChars = {};
	for i=1,ni do
		local ci = c[i];
		if(ci == 1) then
			inputChars[i] = kChar0;
		elseif(ci == 2) then
			inputChars[i] = kChar1;
		else
			inputChars[i] = kCharDash;
		end
	end

	local outputChars = {};
	for i=1,no do
		local ci = c[ni + i];
		if(ci == 0) then
			outputChars[i] = kChar0;
		else
			outputChars[i] = kChar1;
		end
	end

	return string.char(table.unpack(inputChars)), string.char(table.unpack(outputChars));
end

function cubeGetInputs(c)
	return { table.unpack(c, 1, c.desc.ni) };
end

function cubeGetOutputs(c)
	local desc = c.desc;
	local ni = desc.ni;
	local no = desc.no;
	return { table.unpack(c, ni + 1, ni + no) };
end

function cubeCopy(c)
	local copy = { table.unpack(c) };
	copy.desc = c.desc;
	copy.n = nil;
	return copy;
end

function cubeIsUniverse(c)
	local ni = c.desc.ni;
	for i=1,ni do
		if(c[i] ~= 3) then
			return false;
		end
	end
	return true;
end

function cubeIsEmpty(c)
	local desc = c.desc;
	local ni = desc.ni;

	for i=1,ni do
		if(c[i] == 0) then
			return true;
		end
	end

	local numOutputs = 0;
	for i=1,desc.no do
		numOutputs = numOutputs + c[ni + i];
	end

	return numOutputs == 0;
end

function cubeEqual(a, b)
	assert(a.desc == b.desc);

	local desc = a.desc;
	local nf = desc.ni + desc.no;
	for i=1,nf do
		if(a[i] ~= b[i]) then
			return false;
		end
	end

	return true;
end

-- Check if a contains (covers) b
function cubeContains(a, b)
	assert(a.desc == b.desc);

	local desc = a.desc;
	local ni = desc.ni;
	local no = desc.no;

	for i=1,ni do
		local ai = a[i];
		local bi = b[i];
		local containment = kInputContainment[ai][bi];
		if(containment == 0) then
			return false;
		end
	end

	for i=1,no do
		local oid = ni + i;
		local ao = a[oid];
		local bo = a[oid];
		local containment = kOutputContainment[ao][bo];
		if(containment == 0) then
			return false;
		end
	end

	return true;
end

-- returns the intersection cube or empty cube if they don't intersect
function cubeAnd(a, b)
	assert(a.desc == b.desc);
	local desc = a.desc;
	local nf = desc.ni + desc.no;

	local c = { desc = desc };
	for i=1,nf do
		c[i] = a[i] & b[i];
	end

	return c;
end

function cubeDistance(a, b)
	assert(a.desc == b.desc);
	local desc = a.desc;
	local ni = desc.ni;
	local no = desc.no;

	local din = 0;
	for i=1,ni do
		din = din + ((a[i] & b[i]) == 0 and 1 or 0);
	end

	local commonOutputs = 0;
	for i=1,no do
		local oid = ni + i;
		commonOutputs = commonOutputs + (a[oid] & b[oid]);
	end

	local dout = commonOutputs == 0 and 1 or 0;
	return din + dout, din, dout; -- Return all distances in case they are needed by the caller.
end

function cubeConsensus(a, b)
	assert(a.desc == b.desc);
	local desc = a.desc;
	local consensus = { desc = desc };

	local d, din, dout = cubeDistance(a, b);
	if(d == 0) then
		consensus = cubeAnd(a, b);
	elseif(d == 1) then
		local ni = desc.ni;
		local no = desc.no;
		if(din == 1) then
			-- din == 1 and dout == 0
			for i=1,ni do
				local intersection = a[i] & b[i];
				consensus[i] = (intersection == 0 and 3 or intersection);
			end
			for i=1,no do
				local oid = ni + i;
				consensus[oid] = a[oid];
			end
		else
			-- din == 0 and dout == 1
			for i=1,ni do
				consensus[i] = a[i] & b[i];
			end
			for i=1,no do
				local oid = ni + i;
				consensus[oid] = a[oid] | b[oid];
			end
		end
	else
		-- d >= 2
		consensus = cubeEmpty(ni, no);
	end

	return consensus;
end

-- Calculates the cofactor of a w.r.t. b
function cubeCofactor(a, b)
	assert(a.desc == b.desc);
	local desc = a.desc;
	local ni = desc.ni;
	local no = desc.no;

	local c = { desc = desc };

	for i=1,ni do
		local ai = a[i];
		local bi = b[i];

		local intersection = ai & bi;
		if(intersection == 0) then
			return cubeEmpty(ni, no);
		end
		c[i] = bi ~= 3 and 3 or ai;
	end

	local nZeroOutputs = 0;
	for i=1,no do
		local oid = ni + i;
		local ao = a[oid];
		local bo = b[oid];

		nZeroOutputs = nZeroOutputs + ((ao & bo) == 0 and 1 or 0);
		c[oid] = bo == 0 and 1 or ao;
	end

	if(nZeroOutputs == no) then
		-- empty intersection due to outputs
		return cubeEmpty(ni, no);
	end

	return c;
end

function sop(cubes)
	assert(#cubes > 0);
	local ncubes = #cubes;
	local desc = cubes[1].desc;

	local m = { table.unpack(cubes) };
	m.desc = desc;
	m.n = ncubes;
	return m;
end

function sopNew(numInputs, numOutputs)
	return {
		desc = cubeDesc(numInputs, numOutputs),
		n = 0
	};
end

function sopInsert(m, c)
	assert(m.desc == c.desc);
	m[m.n + 1] = cubeCopy(c);
	m.n = m.n + 1;
end

-- TODO: Rename to sopInsertNoCopy
function sopPush(m, c)
	assert(m.desc == c.desc);
	m[m.n + 1] = c;
	m.n = m.n + 1;
end

function sopRemove(m, i)
	table.remove(m, i);
	m.n = m.n - 1;
end

function sopGetInputs(m)
	local G = {};
	local nrows = m.n;
	for i=1,nrows do
		G[i] = cubeGetInputs(m[i]);
	end
	return G;
end

-- TODO: If C is the cover of a single output function we let H be the
-- (empty) matrix of zero columns, since the output part would be redundant
-- in that case.
function sopGetOutputs(m)
	local H = {};
	local nrows = m.n;
	for i=1,nrows do
		H[i] = cubeGetOutputs(m[i]);
	end
	return H;
end

function sopHasDontCareRow(m)
	local desc = m.desc;
	local ni = desc.ni;
	local nr = m.n;

	for i=1,nr do
		local ci = m[i];
		if(cubeIsUniverse(ci)) then
			return true;
		end
	end

	return false;
end

function sopHas01Column(m)
	local desc = m.desc;
	local ni = desc.ni;
	local nr = m.n;
	if(nr == 0) then
		return false;
	end

	-- Find the first input of the first cube which isn't equal to don't care.
	for i=1,ni do
		local m1i = m[1][i];
		if(m1i ~= 3) then
			-- Check the rest of the cubes to see if there's one with a different value.
			local is01 = true;
			for j=2,nr do
				if(m[j][i] ~= m1i) then
					is01 = false;
					break;
				end
			end

			if(is01) then
				return true;
			end

			-- Continue to the next input
		end
	end

	return false;
end

function sopIsUnate(m)
	local desc = m.desc;
	local ni = desc.ni;
	local no = desc.no;
	local nr = m.n;

	local V = cube_U(ni, no);

	for i=1,nr do
		local ci = m[i];

		for j=1,ni do
			local cij = ci[j];
			if(cij ~= 3) then
				if(V[j] == 3) then
					V[j] = cij;
				else
					if(cij ~= V[j]) then
						return false;
					end
				end
			end
		end
	end

	return true;
end

function sopHasCube(m, c)
	local nrows = m.n;
	for i=1,nrows do
		if(cubeEqual(m[i], c)) then
			return i;
		end
	end
	return 0;
end

function sopCofactor(m, p)
	assert(m.desc == p.desc);
	local desc = m.desc;
	local nrows = m.n;

	local c = sopNew(desc.ni, desc.no);
	for i=1,nrows do
		local ci = cubeCofactor(m[i], p);
		if(not cubeIsEmpty(ci)) then
			sopInsert(c, ci);
		end
	end
	
	return c;
end

function sopCubeAnd(m, c)
	assert(m.desc == c.desc);
	local desc = m.desc;
	local nrows = m.n;

	local mandc = sopNew(desc.ni, desc.no);
	for i=1,nrows do
		local intersection = cubeAnd(m[i], c);
		if(not cubeIsEmpty(intersection)) then
			sopInsert(mandc, intersection);
		end
	end

	return mandc;
end

function sopAnd(m1, m2);
	assert(m1.desc == m2.desc);
	local desc = m1.desc;
	local m1nrows = m1.n;
	local m2nrows = m2.n;

	local res = sopNew(desc.ni, desc.no);
	for i=1,m1nrows do
		local m1i = m1[i];
		for j=1,m2nrows do
			local m2j = m2[j];
			local intersection = cubeAnd(m1i, m2j);
			if(not cubeIsEmpty(intersection)) then
				sopInsert(res, intersection);
			end
		end
	end

	return res;
end

function sopOr(m1, m2)
	assert(m1.desc == m2.desc);
	local m = m1.n > 0 and sop(m1) or sopNew(m1.desc.ni, m1.desc.no);

	local nrows2 = m2.n;
	for i=1,nrows2 do
		sopInsert(m, m2[i]);
	end
	return m;
end

-- Inserts the rows of m2 into m1
-- NOTE: This is the same as m1 = sopOr(m1,m2) but avoids duplicating m1
function sopMerge(m1, m2)
	assert(m1.desc == m2.desc);

	local nrows = m2.n;
	for i=1,nrows do
		sopInsert(m1, m2[i]);
	end
	return m1;
end
