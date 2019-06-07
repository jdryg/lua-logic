require('hdl/hdl');
local class = require('util/middleclass');

local kNodeTypeLabel = {
	[kNodeTypeAnd] = "and",
	[kNodeTypeOr] = "or",
	[kNodeTypeXor] = "xor",
	[kNodeTypeShiftLeft] = "shl",
	[kNodeTypeShiftRight] = "shr",
	[kNodeTypeNot] = "not",
	[kNodeTypeNand] = "nand",
	[kNodeTypeNor] = "nor",
	[kNodeTypeBus] = "bus"
};

-- DotGenerator
DotGenerator = class("DotGenerator");

function DotGenerator:initialize()
	self.lines = {};
	self.visitedNodes = {};
end

function DotGenerator:line(str)
	self.lines[#self.lines + 1] = str;
end

function DotGenerator:writeConnections(node)
	if(self.visitedNodes[node] ~= nil) then
		return;
	end

	self.visitedNodes[node] = 1;

	for i, operand in ipairs(node.operands) do
		local input = nil;
		if(operand.type == kNodeTypeInput) then
			input = string.format("input%d", operand._id);
		else
			input = string.format("n%d:o", operand._uid);
		end

		local output = nil;
		if(node.type == kNodeTypeOutput) then
			output = string.format("output%d", node._id);
		else
			output = string.format("n%d:i%d", node._uid, i);
		end

		assert(input ~= nil);
		assert(output ~= nil);

		self:line(string.format("%s:e -> %s:w", input, output));

		self:writeConnections(operand);
	end
end

function generate_dot_file(module)
	local gen = DotGenerator:new();
	gen:line(string.format('digraph "%s" {', module.name));
	gen:line('graph [ ranksep = 2; rankdir = LR; ]');

	gen:line('subgraph inputs { rank = source;');
	for i, input in ipairs(module.inputs) do
		local label = string.format("%s%s", input.name, input.size.width == 1 and "" or ("," .. input.size.width));
		gen:line(string.format("input%d [ shape = rarrow, label = \"%s\"];", input._id, label));
	end
	gen:line('}');

	gen:line('subgraph outputs { rank = sink;');
	for i, output in ipairs(module.outputs) do
		local label = string.format("%s%s", output.name, output.size.width == 1 and "" or ("," .. output.size.width));
		gen:line(string.format("output%d [ shape = rarrow, label = \"%s\"];", output._id, label));
	end
	gen:line('}');

	gen:line('subgraph nodes {');
	for i, node in pairs(module.nodes) do
		if(node._uid ~= nil and not isInput(node) and not isOutput(node)) then
			local label = nil;
			local nodeType = node.type;
			assert(nodeType ~= kNodeTypeWire, "Remove wires!");

			if(nodeType == kNodeTypeConst) then
				label = string.format("<o> %d|const,%d", node.params.value, node.size.width);
			elseif(nodeType == kNodeTypeIndex) then
				label = string.format("{{<i1>}|[%d]|{<o>}}", node.params.index);
			elseif(nodeType == kNodeTypeSlice) then
				label = string.format("{{<i1>}|[%d:%d]|{<o>}}|bit[%d]", node.params.start, node.params.stop - 1, node.size.width);
			elseif(nodeType == kNodeTypeConcat) then
				local inputLabel = "";
				local numOperands = #node.operands;
				for i=1,numOperands do
					if(i ~= 1) then
						inputLabel = inputLabel .. "|";
					end
					inputLabel = inputLabel .. "<i" .. i .. ">";
				end
				label = string.format("{{%s}|<o>}|bit[%d]", inputLabel, node.size.width);
			elseif(nodeType == kNodeTypeMux) then
				local inputLabel = "";
				local numOperands = #node.operands;
				for i=1,numOperands do
					if(i ~= 1) then
						inputLabel = inputLabel .. "|";
					end
					inputLabel = inputLabel .. "<i" .. i .. ">";
					if(i ~= numOperands) then
						inputLabel = inputLabel .. " case" .. (i - 1);
					else
						inputLabel = inputLabel .. " sel";
					end
				end
				label = string.format("{{%s}|<o>}|mux%d,%d", inputLabel, numOperands - 1, node.size.width);
			elseif(nodeType == kNodeTypeNot 
				or nodeType == kNodeTypeAnd 
				or nodeType == kNodeTypeOr 
				or nodeType == kNodeTypeNand 
				or nodeType == kNodeTypeNor 
				or nodeType == kNodeTypeXor
				or nodeType == kNodeTypeBus) then
				local inputLabel = "";
				local numOperands = #node.operands;
				for i=1,numOperands do
					if(i ~= 1) then
						inputLabel = inputLabel .. "|";
					end
					inputLabel = inputLabel .. "<i" .. i .. ">";
				end
				label = string.format("{{%s}|<o> %s}", inputLabel, kNodeTypeLabel[nodeType]);
			elseif(nodeType == kNodeTypeShiftLeft
				or nodeType == kNodeTypeShiftRight) then
				assert(#node.operands == 2);
				label = string.format("{{<i1> i|<i2> c}|<o> %s}", kNodeTypeLabel[nodeType]);
			elseif(nodeType == kNodeTypeRegister) then
				label = string.format("{{<i%d> next|<i%d> clk|<i%d> rst_n|<i%d> set_n}|<o>}|register,%d", kRegInputID_next, kRegInputID_clk, kRegInputID_rst_n, kRegInputID_set_n, node.size.width);
			elseif(nodeType == kNodeTypeTSBuf) then
				label = string.format("{{<i1> i|<i2> ctrl}|<o>}|tristate buffer,%d", node.size.width);
			elseif(nodeType == kNodeTypePull) then
				label = string.format("{{<i1>}|pull(%d)|{<o>}}", node.params.value);
			elseif(nodeType == kNodeTypeBuffer) then
				label = string.format("{{<i1>}|buffer(%d)|{<o>}}", node.params.delay);
			elseif(nodeType == kNodeTypeComparator) then
                label = string.format("{{<i1>|<i2>}|<o> %s}", node.params.operator);
            elseif(nodeType == kNodeTypeAdder) then
                label = string.format("{{<i1> a|<i2> b|<i3> cin}|<o>}|adder,%d", node.size.width);
			end

			assert(label ~= nil);
			gen:line(string.format("n%d [ shape = record, label = \"%s\"];", node._uid, label));
		end
	end
	gen:line('}');

	for i, output in ipairs(module.outputs) do
		gen:writeConnections(output);
	end

	gen:line('}');

	return table.concat(gen.lines, '\n');
end
