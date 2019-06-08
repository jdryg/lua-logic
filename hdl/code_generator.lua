require("hdl/hdl");
local class = require("util/middleclass");

-- CodeGenerator
CodeGenerator = class("CodeGenerator");

function CodeGenerator:initialize()
	self.lines = {};
	self.visitedNodes = {};
end

function CodeGenerator:line(str)
	self.lines[#self.lines + 1] = str;
end

function CodeGenerator:generateNode(node)
	local existingNode = self.visitedNodes[node];
	if(existingNode ~= nil) then
		assert(existingNode.done, "Cannot generate code for a module with cyclic dependencies.");
		return existingNode.name;
	end

	local nodeType = node.type;

	local nodeName = nil;
	if(nodeType == kNodeTypeOutput or nodeType == kNodeTypeInput) then
		nodeName = node.name;
	elseif(nodeType == kNodeTypeConst) then
		nodeName = string.format("c%d", node._uid);
	else
		nodeName = string.format("n%d", node._uid);
	end
	self.visitedNodes[node] = {
		name = nodeName,
		done = false
	};

	local operands = {};
	for i, operand in ipairs(node.operands) do
		local input = nil;
		input = self:generateNode(operand);
		operands[#operands + 1] = input;
	end

	local f = self.nodeFuncs[nodeType];
	f(self, node, nodeName, operands);

	self.visitedNodes[node].done = true;

	return nodeName;
end

-- LuaLogic3Inline
function luaLogic3Inline_input(cg, node, nodeName, operands)
	cg:line(string.format("\tlocal %s1 = %s[1];", nodeName, nodeName));
	cg:line(string.format("\tlocal %s2 = %s[2];", nodeName, nodeName));
end

function luaLogic3Inline_const(cg, node, nodeName, operands)
	-- logic3.lua: signalFromInt()
	local constMask = (1 << node.size.width) - 1;
	local constValue = node.params.value;
	local x0 = constMask - constValue;
	local x1 = constValue;
	cg:line(string.format("\tlocal %s1 = %d;", x0));
	cg:line(string.format("\tlocal %s2 = %d;", x1));
end

function luaLogic3Inline_not(cg, node, nodeName, operands)
	-- logic3.lua: not1()
	cg:line(string.format("\tlocal %s1 = %s2;", nodeName, operands[1]));
	cg:line(string.format("\tlocal %s2 = %s1;", nodeName, operands[1]));
end

function luaLogic3Inline_passthrough(cg, node, nodeName, operands)
	cg:line(string.format("\tlocal %s1 = %s1;", nodeName, operands[1]));
	cg:line(string.format("\tlocal %s2 = %s2;", nodeName, operands[1]));
end

function luaLogic3Inline_output(cg, node, nodeName, operands)
	cg:line(string.format("\tlocal %s = { %s1, %s2 };", nodeName, operands[1], operands[1]));
end

function luaLogic3Inline_and(cg, node, nodeName, operands)
	-- logic3.lua: andn()
	local x0 = string.format("%s1", operands[1]);
	local x1 = string.format("%s2", operands[1]);
	for i=2,#operands do
		x0 = string.format("%s | %s1", x0, operands[i]);
		x1 = string.format("%s & %s2", x1, operands[i]);
	end
	cg:line(string.format("\tlocal %s1 = %s;", nodeName, x0));
	cg:line(string.format("\tlocal %s2 = %s;", nodeName, x1));
end

function luaLogic3Inline_or(cg, node, nodeName, operands)
	-- logic3.lua: orn()
	local x0 = string.format("%s1", operands[1]);
	local x1 = string.format("%s2", operands[1]);
	for i=2,#operands do
		x0 = string.format("%s & %s1", x0, operands[i]);
		x1 = string.format("%s | %s2", x1, operands[i]);
	end
	cg:line(string.format("\tlocal %s1 = %s;", nodeName, x0));
	cg:line(string.format("\tlocal %s2 = %s;", nodeName, x1));
end

function luaLogic3Inline_nand(cg, node, nodeName, operands)
	-- logic3.lua: nandn()
	local x0 = string.format("%s1", operands[1]);
	local x1 = string.format("%s2", operands[1]);
	for i=2,#operands do
		x0 = string.format("%s | %s1", x0, operands[i]);
		x1 = string.format("%s & %s2", x1, operands[i]);
	end
	cg:line(string.format("\tlocal %s1 = %s;", nodeName, x1));
	cg:line(string.format("\tlocal %s2 = %s;", nodeName, x0));
end

function luaLogic3Inline_nor(cg, node, nodeName, operands)
	-- logic3.lua: norn()
	local x0 = string.format("%s1", operands[1]);
	local x1 = string.format("%s2", operands[1]);
	for i=2,#operands do
		x0 = string.format("%s & %s1", x0, operands[i]);
		x1 = string.format("%s | %s2", x1, operands[i]);
	end
	cg:line(string.format("\tlocal %s1 = %s;", nodeName, x1));
	cg:line(string.format("\tlocal %s2 = %s;", nodeName, x0));
end

function luaLogic3Inline_xor(cg, node, nodeName, operands)
	-- logic3.lua: xor2()
	local x0 = string.format("(%s2 & %s2) | (%s1 & %s1)", operands[1], operands[2], operands[1], operands[2]);
	local x1 = string.format("(%s1 & %s2) | (%s2 & %s1)", operands[1], operands[2], operands[1], operands[2]);
	cg:line(string.format("\tlocal %s1 = %s;", nodeName, x0));
	cg:line(string.format("\tlocal %s2 = %s;", nodeName, x1));
end

function luaLogic3Inline_index(cg, node, nodeName, operands)
	-- logic3.lua: index()
	local shiftAmount = node.params.index - 1;
	local x0 = "";
	local x1 = "";
	if(shiftAmount ~= 0) then
		x0 = string.format("(%s1 >> %d) & 1", operands[1], shiftAmount);
		x1 = string.format("(%s2 >> %d) & 1", operands[1], shiftAmount);
	else
		x0 = string.format("%s1 & 1", operands[1], shiftAmount);
		x1 = string.format("%s2 & 1", operands[1], shiftAmount);
	end
	cg:line(string.format("\tlocal %s1 = %s;", nodeName, x0));
	cg:line(string.format("\tlocal %s2 = %s;", nodeName, x1));
end

function luaLogic3Inline_concat(cg, node, nodeName, operands)
	-- logic3.lua: concat()
	-- TODO: Concat larger signals (currently assumes all signals are 1 bit wide)
	local x0 = string.format("(%s1 & 1)", operands[1]);
	local x1 = string.format("(%s2 & 1)", operands[1]);
	for i=2,#operands do
		x0 = string.format("%s | ((%s1 & 1) << %d)", x0, operands[i], i - 1);
		x1 = string.format("%s | ((%s2 & 1) << %d)", x1, operands[i], i - 1);
	end
	cg:line(string.format("\tlocal %s1 = %s;", nodeName, x0));
	cg:line(string.format("\tlocal %s2 = %s;", nodeName, x1));
end

function luaLogic3Inline_dummy(cg, node, nodeName, operands)
	assert(false, "Not implemented yet");
end

LuaLogic3Inline = class("LuaLogic3Inline", CodeGenerator);

LuaLogic3Inline.nodeFuncs = {
	[kNodeTypeInput] = luaLogic3Inline_input,
	[kNodeTypeConst] = luaLogic3Inline_const,
	[kNodeTypeNot] = luaLogic3Inline_not,
	[kNodeTypeBuffer] = luaLogic3Inline_passthrough,
	[kNodeTypeWire] = luaLogic3Inline_passthrough,
	[kNodeTypeOutput] = luaLogic3Inline_output,
	[kNodeTypeAnd] = luaLogic3Inline_and,
	[kNodeTypeOr] = luaLogic3Inline_or,
	[kNodeTypeNand] = luaLogic3Inline_nand,
	[kNodeTypeNor] = luaLogic3Inline_nor,
	[kNodeTypeXor] = luaLogic3Inline_xor,
	[kNodeTypeIndex] = luaLogic3Inline_index,
	[kNodeTypeConcat] = luaLogic3Inline_concat,
	[kNodeTypeSlice] = luaLogic3Inline_dummy,
	[kNodeTypeShiftLeft] = luaLogic3Inline_dummy,
	[kNodeTypeShiftRight] = luaLogic3Inline_dummy,
	[kNodeTypePull] = luaLogic3Inline_dummy,
	[kNodeTypeTSBuf] = luaLogic3Inline_dummy,
	[kNodeTypeBus] = luaLogic3Inline_dummy,
	[kNodeTypeMux] = luaLogic3Inline_dummy,
	[kNodeTypeComparator] = luaLogic3Inline_dummy,
	[kNodeTypeAdder] = luaLogic3Inline_dummy,
	[kNodeTypeRegister] = luaLogic3Inline_dummy,
};

function generate_lua_sim(module, funcName)
	local gen = LuaLogic3Inline:new();
	
	local inputArgs = {};
	for i, input in ipairs(module.inputs) do
		inputArgs[#inputArgs + 1] = input.name;
	end

	local funcSignature = string.format("function %s(%s)", funcName, table.concat(inputArgs, ", "));
	gen:line(funcSignature);
	
	local outputs = {};
	for i, output in ipairs(module.outputs) do
		outputs[#outputs + 1] = output.name;
		gen:generateNode(output);
	end

	gen:line(string.format("\treturn %s;", table.concat(outputs, ", ")));
	gen:line("end");

	return table.concat(gen.lines, '\n');
end
