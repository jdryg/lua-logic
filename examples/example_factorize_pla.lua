require('../logic/sop');
require('../logic/algorithms');
require('../logic/factorization');

function loadPLA(filename)
	local numInputs = 0;
	local numOutputs = 0;
	local numProducts = 0;

	local products = {};
	for line in io.lines(filename) do
		local cmd = line:sub(1, 2);
		if(cmd == ".i") then
			numInputs = tonumber(line:match(".i (%d+)"));
		elseif(cmd == ".o") then
			numOutputs = tonumber(line:match(".o (%d+)"));
		elseif(cmd == ".p") then
			numProducts = tonumber(line:match(".p (%d+)"));
		elseif(cmd == ".e") then
			break;
		else
			local inputs, outputs = line:match("([01%-]+) ([01~]+)");
			if(inputs ~= nil and outputs ~= nil) then
				local c = cubeFromStrings(inputs, outputs);
				products[#products + 1] = c;
			end
		end
	end

	return sop(products);
end

--local pla = loadPLA("examples/pla/alu4.pla");
local pla = loadPLA("examples/pla/9sym.pla");
--local pla = loadPLA("examples/pla/5xp1.pla");

local plaDesc = pla.desc;

outputs = {};

local tS = os.clock();
for oid=1,plaDesc.no do
	local outputSOP = sopExtract(pla, nil, oid);
	local factoredSOP = sopQuickFactor(outputSOP);
	outputs[oid] = {
		original = outputSOP,
		factored = factoredSOP
	};
end
local tE = os.clock();
print("Total time: " .. (tE - tS));

local plaVars = {};
for iid=1,plaDesc.ni do
	local varName = string.format("x%d", iid - 1);
	plaVars[iid] = varName;
end

for i=1,plaDesc.no do
	print("O[" .. i .. "] = " .. nodeToString(nodeSOP(outputs[i].original), plaVars));
	print("<=>");
	print("O[" .. i .. "] = " .. nodeToString(outputs[i].factored, plaVars));
	print("");
end
