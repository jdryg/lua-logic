local class = require("util/middleclass");
local memoize = require("util/memoize");

local MAX_BITS = 16;

kFlagConstCompareExpand = 1 << 0;
kFlagSwitchTristateBus  = 1 << 1;

kNodeTypeInput      = "input";
kNodeTypeOutput     = "output";
kNodeTypeConst      = "const";
kNodeTypeNot        = "gate_not";
kNodeTypeAnd        = "gate_and";
kNodeTypeOr         = "gate_or";
kNodeTypeXor        = "gate_xor";
kNodeTypeNand       = "gate_nand";
kNodeTypeNor        = "gate_nor";
kNodeTypeIndex      = "index";
kNodeTypeSlice      = "slice";
kNodeTypeConcat     = "concat";
kNodeTypeShiftLeft  = "shl";
kNodeTypeShiftRight = "shr";
kNodeTypeRegister   = "reg";
kNodeTypeBuffer     = "buffer";
kNodeTypePull       = "pull";
kNodeTypeTSBuf      = "tsbuf";
kNodeTypeBus        = "bus";
kNodeTypeMux        = "mux";
kNodeTypeComparator = "compare";
kNodeTypeWire       = "wire";
kNodeTypeAdder      = "adder";

kRegInputID_next  = 1;
kRegInputID_clk   = 2;
kRegInputID_rst_n = 3;
kRegInputID_set_n = 4;

function isInteger(x)  return type(x) == "number" and math.type(x) == "integer"; end
function isClass(x)    return type(x) == "table" and type(x["isInstanceOf"]) == "function"; end
function isNode(x)     return isClass(x) and x:isInstanceOf(Node); end
function isSlice(x)    return isClass(x) and x:isInstanceOf(Slice); end
function isSize(x)     return isClass(x) and x:isInstanceOf(SizeType); end
function isInput(x)    return isNode(x) and x.type == kNodeTypeInput; end
function isOutput(x)   return isNode(x) and x.type == kNodeTypeOutput; end
function isRegister(x) return isNode(x) and x.type == kNodeTypeRegister; end
function isWire(x)     return isNode(x) and x.type == kNodeTypeWire; end

-- http://leafo.net/guides/setfenv-in-lua52-and-above.html
local function setfenv(fn, env)
	local i = 1;
	while(true) do
		local name = debug.getupvalue(fn, i);
		if(name == "_ENV") then
			debug.upvaluejoin(fn, i, (function()
				return env;
			end), 1);
			break;
		elseif(not name) then
			break;
		end
  
		i = i + 1;
	end
  
	return fn;
end

function bit_length(x)
	assert(isInteger(x) or type(x) == "boolean", "x must be boolean or integer");
	if(type(x) == "boolean" or x == 0) then
		return 1;
	end
	
	local numBits = 0;
	local test = 16;
	while(test >= 1) do
		if(x >= (1 << test)) then
			numBits = numBits + test;
			x = x >> test;
		end

		test = test >> 1;
	end

	return numBits + x;
end

-- https://graphics.stanford.edu/~seander/bithacks.html#RoundUpPowerOf2
function nextPow2(x)
	assert(isInteger(x), "x must be an integer");
	x = x - 1;
	x = x | (x >> 1);
	x = x | (x >> 2);
	x = x | (x >> 4);
	x = x | (x >> 8);
	x = x | (x >> 16);
	x = x + 1;
	return x;
end

local function wrap_index(i, n)
	if(i < 0 and i >= -n) then
		return i + n + 1;
	end

	return i;
end

local function map(func, array)
	local new_array = {};
	for i=1,#array do
		new_array[i] = func(array[i]);
	end
	return new_array;
end

-- Module
Module = class("Module");

function Module:initialize(name, func)
	self.name = name;
	self.func = func;
	self.inputs = {};
	self.outputs = {};

	local nextInputID = 1;
	local nextOutputID = 1;
	local funcEnv = setmetatable({
		input = function (type, name)
			local i = input(type, name);
			i._id = nextInputID;
			nextInputID = nextInputID + 1;
			return i;
		end,
		output = function (arg)
			local o = output(arg);
			o._id = nextOutputID;
			nextOutputID = nextOutputID + 1;
			return o;
		end
	}, {
		__index = _G
	});

	setfenv(self.func, funcEnv);
	self.func();

	for name, node in pairs(funcEnv) do
		if(isNode(node)) then
			if(node.name == nil) then
				node.name = name;
			end

			if(isInput(node)) then
				self.inputs[node._id] = node;
			elseif(isOutput(node)) then
				self.outputs[node._id] = node;
			end
		end
	end

	self.nodes = collectNodes(self);
end

function Module:__call(...)
	local instance = make_module_instance(self);
	if(...) then
		for name, node in pairs(...) do
			instance:connectInput(name, node);
		end
	end

	return instance;
end

function module(name)
	return function (moduleFunc)
		return Module:new(name, moduleFunc);
	end
end

-- ModuleInstance
ModuleInstance = class("ModuleInstance");

function ModuleInstance:initialize(module)
	self.module = module;
	self.inputs = {};
	self.outputs = {};
	self.nodes = {};
end

function ModuleInstance:addInput(uid, name, size)
	self.inputs[name] = {
		uid = uid,
		size = size,
		connections = {}
	};
end

function ModuleInstance:addOutput(uid, name, size, sourceNodeUid)
	self.outputs[name] = {
		uid = uid,
		size = size,
		source = sourceNodeUid,
	};
end

function ModuleInstance:addNode(uid, name, size, type, numInputs, numOutputs, params)
	self.nodes[uid] = Node:new(size, name, type, numInputs, numOutputs, nil, params);
end

function ModuleInstance:connect(srcNodeUid, dstNodeUid, dstOperandID)
	local dstNode = self.nodes[dstNodeUid];
	assert(dstNode ~= nil, "Node not found");

	local srcNode = self.nodes[srcNodeUid];
	if(srcNode == nil) then
		-- Source must be an input pin.
		local input = self:findInputByUid(srcNodeUid);
		assert(input ~= nil, "Input node not found");
		input.connections[#input.connections + 1] = {
			uid = dstNodeUid,
			operandID = dstOperandID
		};
	else
		dstNode.operands[dstOperandID] = srcNode; 
	end
end

function ModuleInstance:connectInput(name, srcNode)
	local input = self.inputs[name];
	assert(input ~= nil, "Input node not found");
	
	for i, connection in ipairs(input.connections) do
		local dstNode = self.nodes[connection.uid];
		assert(dstNode ~= nil, "Node not found");
		dstNode.operands[connection.operandID] = as_node(srcNode);
	end
end

function ModuleInstance:findInputByUid(uid)
	for name, input in pairs(self.inputs) do
		if(input.uid == uid) then
			return input;
		end
	end

	return nil;
end

function ModuleInstance:__index(key)
	local outputs = rawget(self, "outputs");
	if(outputs) then
		local output = outputs[key];
		if(output ~= nil) then
			local nodes = rawget(self, "nodes");
			if(nodes) then
				local node = nodes[output.source];
				assert(node ~= nil, "Node not found");
				return node;
			end
		end
	end

	return rawget(self, key);
end

function ModuleInstance:__newindex(key, value)
	local inputs = rawget(self, "inputs");
	if(inputs) then
		local input = inputs[key];
		if(input ~= nil) then
			self:connectInput(key, as_node(value, input.size));
			return;
		end
	end

	rawset(self, key, value);
end

function make_module_instance(module)
	local instance = ModuleInstance:new(module);

	for i, node in ipairs(module.nodes) do
		if(isInput(node)) then
			instance:addInput(node._uid, node.name, node.size);
		elseif(isOutput(node)) then
			local operand = node.operands[1];
			local operandUid = operand and operand._uid or nil;
			instance:addOutput(node._uid, node.name, node.size, operandUid);
		else 
			instance:addNode(node._uid, node.name, node.size, node.type, node.numInputs, node.numOutputs, node.params);
		end
	end

	for i, node in ipairs(module.nodes) do
		if(not isInput(node) and not isOutput(node)) then
			for j, operand in ipairs(node.operands) do
				instance:connect(operand._uid, node._uid, j);
			end
		end
	end

	return instance;
end

-- Slice
Slice = class("Slice");

function Slice:initialize(start, stop)
	self.start = start;
	self.stop = stop;
end

-- SizeType
SizeType = class("SizeType");

function SizeType:initialize(width)
	self.width = width or 1;
end

function SizeType:__tostring()
	return self.width == 1 and "bit" or string.format("bit[%d]", self.width);
end

function SizeType:__len()
	return self.width;
end

function SizeType:__index(key)
	if(not isInteger(key)) then
		return rawget(self, key);
	end

	return bitvector(key);
end

bit = SizeType:new(1);

bitvector = memoize(function (width) 
	assert(isInteger(width), "SizeType width not an integer");
	if(width <= 0) then
		return nil;
	end

	return SizeType:new(width);
end);

-- Node
Node = class("Node");

function Node:initialize(sizeType, name, type, numInputPins, numOutputPins, operands, params)
	assert(isSize(sizeType), "Invalid Node size");
	assert(type ~= nil, "Cannot create Node without a proper type");

	self.size = sizeType;
	self.name = name;
	self.numInputs = numInputPins;
	self.numOutputs = numOutputPins;
	self.operands = operands or {};
	self.params = params or {};
	self.type = type;
end

function Node:__index(index)
	if(isInteger(index)) then
		return make_index_node(self, index);
	elseif(isSlice(index)) then
		return make_slice_node(self, index.start, index.stop);
	else
		local type = rawget(self, "type");
		if(type == kNodeTypeRegister) then
			if(index == "next") then
				return rawget(self, "operands")[kRegInputID_next];
			elseif(index == "clk") then
				return rawget(self, "operands")[kRegInputID_clk];
			elseif(index == "rst_n") then
				return rawget(self, "operands")[kRegInputID_rst_n];
			elseif(index == "set_n") then
				return rawget(self, "operands")[kRegInputID_set_n];
			end
		elseif(type == kNodeTypeWire) then
			if(index == "next") then
				return rawget(self, "operands")[1];
			end
		end
	end

	return rawget(self, index);
end

function Node:__newindex(key, value)
	local type = rawget(self, "type");
	if(type == kNodeTypeRegister) then
		if(key == "next") then
			self.operands[kRegInputID_next] = as_node(value);
			return;
		elseif(key == "clk") then
			self.operands[kRegInputID_clk] = as_node(value);
			return;
		elseif(key == "rst_n") then
			self.operands[kRegInputID_rst_n] = as_node(value);
			return;
		elseif(key == "set_n") then
			self.operands[kRegInputID_set_n] = as_node(value);
			return;
		end
	elseif(type == kNodeTypeWire) then
		if(key == "next") then
			self.operands[1] = as_node(value);
			return;
		end
	end

	rawset(self, key, value);
end

function Node:__len()             return self.size.width; end
function Node:__concat(other)     return make_concat_node({self, as_node(other)}); end
function Node:__call(start, stop) return make_slice_node(self, start, stop); end
function Node:__bnot()            return make_unary_node(kNodeTypeNot, self); end
function Node:__band(other)       return make_binary_node(kNodeTypeAnd, self, other); end
function Node:__bor(other)        return make_binary_node(kNodeTypeOr, self, other); end
function Node:__bxor(other)       return make_binary_node(kNodeTypeXor, self, other); end
function Node:__shl(other)        return make_shift_node(kNodeTypeShiftLeft, self, other); end
function Node:__shr(other)        return make_shift_node(kNodeTypeShiftRight, self, other); end
function Node:slice(start, stop)  return make_slice_node(self, start, stop); end
function Node:__add(other)        return make_adder_node(self, other, 0); end
function Node:__sub(other)        return make_adder_node(self, ~as_node(other), 1); end

-- Constructor functions
function input(sizeType, name)
	sizeType = sizeType or bit;
	assert(#sizeType <= MAX_BITS);
	return Node:new(sizeType, name, kNodeTypeInput, 0, 1, nil, nil);
end

function output(arg)
	arg = arg or bit;

	local operand = nil;
	local sizeType = nil;
	if(isSize(arg)) then
		sizeType = arg;
	else
		operand = as_node(arg);
		sizeType = operand.size;
	end

	assert(#sizeType <= MAX_BITS);
	return Node:new(sizeType, nil, kNodeTypeOutput, 1, 0, { operand }, nil);
end

function bits(x)
	if(isNode(x) and x.size == bit) then
		return bit[1](x);
	elseif(type(x) == "table") then
		return make_concat_node(map(as_node, x));
	end

	assert(false, "bits(): Invalid operand type");
end

function make_constant_node(size, value)
	assert(isSize(size), "Constant size not a SizeType");
	assert(size.width <= MAX_BITS);
	assert(isInteger(value), "Constant value should be an integer");
	value = value & ((1 << size.width) - 1);
	return Node:new(size, nil, kNodeTypeConst, 0, 1, nil, { value = value });
end

function make_unary_node(op, operand)
	return Node:new(operand.size, nil, op, 1, 1, { operand }, nil);
end

function make_binary_node(op, left, right)
	left, right = as_node(left, get_size(right)), as_node(right, get_size(left));
	check_same_size(left, right);
	return Node:new(left.size, nil, op, 2, 1, { left, right }, nil);
end

function make_adder_node(a, b, cin)
	a, b = as_node(a, get_size(b)), as_node(b, get_size(a));
	check_same_size(a, b);
	cin = as_node(cin, bit);
	check_size(cin, bit);
	return Node:new(a.size, nil, kNodeTypeAdder, 3, 1, { a, b, cin }, nil);
end

function make_slice_node(operand, start, stop)
	assert(isNode(operand), "Operand not a Node");
	local size = operand.size.width;
	local start = wrap_index(start and start or 1, size);
	local stop = wrap_index(stop and stop or (size + 1), size);

	assert(stop > start, "Slice stop must be greater than slice start");
	assert(start > 0, "Slice start must be greater than 0");
	assert(stop <= operand.size.width + 1, "Slice stop must be less than or equal to 1 past the operand width");

	if(operand.type == kNodeTypeSlice) then
		-- slice(slice(node)) = slice(node)
		return Node:new(bit[stop-start], nil, kNodeTypeSlice, 1, 1, { operand.operands[1] }, { start = start + operand.params.start - 1, stop = stop + operand.params.start - 1 });
	end

	if(start == 1 and stop == #operand + 1) then
		-- slice(node, 1, size) = node;
		return operand;
	elseif(stop - start == 1) then
		-- slice(node, x, x + 1) = index(node, x);
		return make_index_node(operand, start);
	end

	return Node:new(bit[stop-start], nil, kNodeTypeSlice, 1, 1, { operand }, { start = start, stop = stop});
end

function make_shift_node(op, left, right)
	left, right = as_node(left), as_node(right);
	assert(right.type == kNodeTypeConst, "Shift amount must be a constant");
	return Node:new(left.size, nil, op, 2, 1, { left, right }, nil);
end

function make_index_node(operand, index)
	assert(isInteger(index), "Only integers may be used as indices");
	assert(index ~= 0, "Indices start at 1");

	local operandType = operand.type;
	local operandWidth = operand.size.width;

	if(operandType == kNodeTypeAdder) then
		index = wrap_index(index, operandWidth + 1);
		assert(index > 0 and index <= operandWidth + 1, string.format("Index should be in the range [1, %d], was %d", operandWidth + 1, index));
		if(index <= 0 or index > operandWidth + 1) then
			return nil;
		end

		return Node:new(bit, nil, kNodeTypeIndex, 1, 1, { operand }, { index = index });
	elseif(operandType == kNodeTypeSlice) then
		index = wrap_index(index, operandWidth);
		if(index <= 0 or index > operandWidth) then
			return nil;
		end
		return make_index_node(operand.operands[1], index - 1 + operand.params.start);
	elseif(operandType == kNodeTypeConcat) then
		index = wrap_index(index, operandWidth);
		if(index <= 0 or index > operandWidth) then
			return nil;
		end

		local offset = 1;
		for i, suboperand in pairs(operand.operands) do
			local suboperandSize = suboperand.size.width;
			if(suboperandSize == 1) then
				if(offset == index) then
					return suboperand;
				end
			else
				if(offset <= index and index < offset + suboperandSize) then
					return make_index_node(suboperand, index - offset + 1);
				end
			end
			offset = offset + suboperandSize;
		end
	end

	index = wrap_index(index, operandWidth);
	if(index <= 0 or index > operandWidth) then
		-- NOTE: This should have been an assert. Problem is that if it asserts here, 
		-- we cannot iterate over bits of a node with ipairs...
		return nil;
	end
	return Node:new(bit, nil, kNodeTypeIndex, 1, 1, { operand }, { index = index });
end

function make_concat_node(operands)
	if(#operands == 1) then
		-- Nothing to merge
		return operands[1];
	end

	local new_operands = {};
	for i=1,#operands do
		local operand = as_node(operands[i]);
		if(operand.size ~= bit[0]) then
			new_operands[#new_operands + 1] = operand;
		end
	end

	local width = 0;
	for i, operand in ipairs(new_operands) do
		local operandSize = operand.size.width;
		width = width + operandSize;
	end

	return Node:new(bit[width], nil, kNodeTypeConcat, #new_operands, 1, new_operands, nil);
end

function make_buffer_node(operand, delay)
	assert(isInteger(delay), "Buffer delay should be an integer");
	assert(delay >= 1, "Buffer delay must be greater than or equal to 1");
	assert(isNode(operand), "Buffer operand should be a node");
	return Node:new(operand.size, nil, kNodeTypeBuffer, 1, 1, { operand }, { delay = delay });
end

function make_tristate_buffer_node(operand, control)
	assert(isNode(operand), "Tristate buffer operand should be a node");
	control = as_node(control, bit);
	check_size(control, bit);
	return Node:new(operand.size, nil, kNodeTypeTSBuf, 2, 1, { operand, control }, nil);
end

function make_pull_node(operand, value)
	assert(isInteger(value), "Pull value should be an integer");
	assert(isNode(operand), "Pull operand should be a node");
	return Node:new(operand.size, nil, kNodeTypePull, 1, 1, { operand }, { value = value });
end

function make_compare_node(op, left, right)
	if(isInteger(right)) then
		if(isInteger(left)) then
			local leftLen = bit_length(left);
			local rightLen = bit_length(right);
			local constLen = leftLen > rightLen and leftLen or rightLen;
			left = make_constant_node(bit[constLen], left);
			right = make_constant_node(bit[constLen], right);
		else
			assert(isNode(left), "Left operand is neither a node nor an integer");
			right = make_constant_node(left.size, right);
		end
	else
		if(isInteger(left)) then
			assert(isNode(right), "Right operand is neither a node nor an integer");
			left = make_constant_node(right.size, left);
		else
			assert(left.size.width == right.size.width, "Cannot compare " .. tostring(left.size) .. " with " .. tostring(right.size));
		end
	end
	check_same_size(left, right);

	-- Special case: Equality comparison with constant (most commonly generated by switch() blocks)
	if(hdlIsFlagSet(HDLF_CONST_COMPARE_EXPAND)) then
		if((op == 'eq' or op == 'ne') and (left.type == kNodeTypeConst or right.type == kNodeTypeConst)) then
			-- Instead of generating a comparator, generate an AND/NAND gate
			local constValue = left.type == kNodeTypeConst and left.params.value or right.params.value;
			local x = left.type == kNodeTypeConst and right or left;

			local nodes = {};
			for i=1,#x do
				local bit_i = (constValue >> (i - 1)) & 1;
				if(bit_i == 1) then
				nodes[#nodes + 1] = buffer(x[i], 1);
				elseif(bit_i == 0) then
				nodes[#nodes + 1] = ~x[i];
				else
					assert(false, "Invalid constant value " .. tostring(constValue));
				end
			end

			local func = op == 'eq' and andn or nandn;
			return func(table.unpack(nodes));
		end
	end

	return Node:new(bit, nil, kNodeTypeComparator, 2, 1, { left, right }, { operator = op });
end

function make_multi_input_node(op, ...)
	local operands = {...};
	assert(#operands >= 2, "Expected at least 2 operands");

	local size = as_node(operands[1]).size;

	local nodes = {};
	for i=1, #operands do
		local node = as_node(operands[i], size);
		check_size(node, size);
		nodes[i] = node;
	end

	return Node:new(size, nil, op, #nodes, 1, nodes, nil);
end

function make_multiplexer_node(sel, ...)
	local cases = {...};
	local numCases = #cases;
	assert(numCases >= 2, "Multiplexers should have at least 2 cases");

	local selSize = bit[math.max(1, bit_length(numCases-1))];
	sel = as_node(sel, selSize);
	check_size(sel, selSize);

	local requiredCases = 1 << selSize.width;
	assert(requiredCases == numCases, string.format("Multiplexer should have %d cases", requiredCases));

	local caseSize = as_node(cases[1]).size;
	local caseNodes = {};
	for i=1,numCases do
		caseNodes[i] = as_node(cases[i], caseSize);
	end
	caseNodes[numCases + 1] = sel;

	return Node:new(caseSize, nil, kNodeTypeMux, numCases + 1, 1, caseNodes, nil);
end

function make_register_node(size, clk, rst_n, set_n, next)
	assert(isSize(size), "Register size is not a size object");
	assert(clk ~= nil, "Register input 'clk' must be connected");
	assert(not rst_n or (isNode(rst_n) and rst_n.size.width == 1), "Register input 'rst_n' should either be left unconnected or connected to a 1-bit signal");
	assert(not set_n or (isNode(set_n) and set_n.size.width == 1), "Register input 'set_n' should either be left unconnected or connected to a 1-bit signal");

	rst_n = rst_n or make_constant_node(bit, 1);
	set_n = set_n or make_constant_node(bit, 1);
	
	local reg = Node:new(size, nil, kNodeTypeRegister, 4, 1, nil, nil);

	check_size(clk, bit);
	check_size(rst_n, bit);
	check_size(set_n, bit);
	reg.clk = clk;
	reg.rst_n = rst_n;
	reg.set_n = set_n;

	if(next ~= nil) then
		next = as_node(next, size);
		check_size(next, size);
		reg.next = next;
	else
		reg.next = reg;
	end

	return reg;
end

function make_wire_node(size)
	assert(isSize(size), "Wire size is not a size object");
	return Node:new(size, nil, kNodeTypeWire, 1, 1, nil, nil);
end

function eq(left, right) return make_compare_node('eq', left, right); end
function ne(left, right) return make_compare_node('ne', left, right); end
function le(left, right) return make_compare_node('le', left, right); end
function lt(left, right) return make_compare_node('lt', left, right); end
function ge(left, right) return make_compare_node('ge', left, right); end
function gt(left, right) return make_compare_node('gt', left, right); end
function bus(...)        return make_multi_input_node(kNodeTypeBus, ...); end
function andn(...)       return make_multi_input_node(kNodeTypeAnd, ...); end
function orn(...)        return make_multi_input_node(kNodeTypeOr, ...); end
function nandn(...)      return make_multi_input_node(kNodeTypeNand, ...); end
function norn(...)       return make_multi_input_node(kNodeTypeNor, ...); end
function merge(...)      return make_concat_node({...}); end
function mux2(case0, case1, sel) return make_multiplexer_node(sel, case0, case1); end
function mux4(case0, case1, case2, case3, sel) return make_multiplexer_node(sel, case0, case1, case2, case3); end
function mux8(case0, case1, case2, case3, case4, case5, case6, case7, sel) return make_multiplexer_node(sel, case0, case1, case2, case3, case4, case5, case6, case7); end
function when(cond, then_node, else_node) return make_multiplexer_node(cond, else_node, then_node); end

function muxn(cases, sel)
	assert(#cases == (1 << #sel), "The number of Mux cases should be a power of 2 and equal to 2 to the power of the sel signal size");
	return make_multiplexer_node(sel, table.unpack(cases));
end

const = make_constant_node;
buffer = make_buffer_node;
tristate_buffer = make_tristate_buffer_node;
pull = make_pull_node;
register = make_register_node;
wire = make_wire_node;

function slice(start, stop)
	return Slice:new(start, stop);
end

-- Switch/case/assign
local DEFAULT_CASE_VALUE = {};

CaseBlock = class("CaseBlock");

function CaseBlock:initialize(caseValue, assigments)
	self.value = caseValue;
	self.assignments = assigments;
end

Assignment = class("Assignment");

function Assignment:initialize(reg, value)
	self.reg = reg;
	self.value = value;
end

function switch(node)
	hdl_OnSwitchEnter();

	return function (cases)
		local regs = {};

		-- Collect all registers referenced by all cases
		for i, case in ipairs(cases) do
			assert(case:isInstanceOf(CaseBlock), "Invalid case block in switch()");

			for j, assignment in ipairs(case.assignments) do
				assert(assignment:isInstanceOf(Assignment), "Invalid assignment in case block");
				local r = assignment.reg;
				local v = assignment.value;
				if(not regs[r]) then
					regs[r] = {};
				end

				regs[r][case.value] = v;
			end
		end

		-- Generate the mux tree for each register
		for r, cases in pairs(regs) do
			local nextRegValue = cases[DEFAULT_CASE_VALUE] or r.next;
			cases[DEFAULT_CASE_VALUE] = nil;

			if(hdlIsFlagSet(HDLF_SWITCH_TRISTATE_BUS)) then
				local nodes = {};
				local comps = {};
				for caseValue, regValue in pairs(cases) do
					local c = eq(node, caseValue);
					comps[#comps + 1] = c;
					nodes[#nodes + 1] = tristate_buffer(regValue, c);
				end

				if(nextRegValue) then
					if(#nodes == 1) then
						r.next = when(comps[1], nodes[1], nextRegValue);
					else
						local selDefaultValue = #comps == 1 and comps[1] or orn(table.unpack(comps));
						r.next = when(selDefaultValue, bus(table.unpack(nodes)), nextRegValue);
					end
				else
					r.next = bus(table.unpack(nodes));
				end
			else
				for caseValue, regValue in pairs(cases) do
					nextRegValue = when(eq(node, caseValue), regValue, nextRegValue);
				end
				r.next = nextRegValue;
			end
		end

		hdl_OnSwitchExit();
	end
end

function case(val)
	assert(hdl_IsInsideSwitch(), "case() can only be called inside a switch() block");
	hdl_OnCaseEnter();
	return function (assignments) 
		hdl_OnCaseExit();
		return CaseBlock:new(val, assignments);
	end
end

function default()
	assert(hdl_IsInsideSwitch(), "default() can only be called inside a switch() block");
	hdl_OnCaseEnter();
	return function (assignments)
		hdl_OnCaseExit();
		return CaseBlock:new(DEFAULT_CASE_VALUE, assignments);
	end
end

function assign(dst, src)
	assert(isRegister(dst) or isWire(dst), "Only register() or wire() nodes can be assign()'d")

	src = as_node(src, dst.size);
	check_same_size(dst, src);
	if(hdl_IsInsideCase()) then
		return Assignment:new(dst, src);
	end

	-- assign called outside of a case block.
	dst.next = src;
end

-- Helpers
function as_node(x, astype)
	if(isNode(x)) then
		if(astype) then
			assert(x.size.width == astype.width, "Expected " .. tostring(astype) .. ", got " .. tostring(get_size(x)));
		end
		return x;
	elseif(isInteger(x) or type(x) == "boolean") then
		if(not astype) then
			local n = math.max(1, bit_length(x));
			astype = n == 1 and bit or bit[n];
		end
		return make_constant_node(astype, x)
	elseif(type(x) == "table") then
		return bits(x);
	end

	assert(false, "Cannot convert to node");
end

function get_size(x)
	return (isNode(x) and x.size) or nil;
end

function check_size(node, size)
	assert(isNode(node) and isSize(size) and node.size.width == size.width, string.format("Inconsistent sizes: %s and %s", node.size, size));
end

function check_same_size(node1, node2)
	check_size(node1, node2.size)
end

-- NodeCollector
-- NOTE: Walks the graph and assigns unique IDs to every node it encounters.
NodeCollector = class("NodeCollector");

function NodeCollector:initialize()
	self.nodes = {};
	self.nextNodeID = 1;
	self.visitedNodes = {};
end

function NodeCollector:collectNode(node)
	if(self.visitedNodes[node] ~= nil) then
		return;
	end

	local uid = self.nextNodeID;
	self.nextNodeID = self.nextNodeID + 1;
	self.nodes[uid] = node;
	self.visitedNodes[node] = 1;
	node._uid = uid;

	for i, operand in ipairs(node.operands) do
		self:collectNode(operand);
	end
end

function collectNodes(module)
	local collector = NodeCollector:new();

	for i, output in ipairs(module.outputs) do
		collector:collectNode(output);
	end

	return collector.nodes;
end

-- HDL API
local g_State = {
	isInsideSwitch = false,
	isInsideCase = false,
	flags = 0;
};

function hdlRegisterAdder(func)
	g_State.adderFunc = func;
end

function hdlSetFlag(f)
	g_State.flags = g_State.flags | f;
end

function hdlResetFlag(f)
	g_State.flags = g_State.flags & (~f);
end

function hdlSetAllFlags(f)
	g_State.flags = f;
end

function hdlIsFlagSet(f)
	return (g_State.flags & f) == f;
end

function hdl_OnSwitchEnter()
	assert(not g_State.isInsideSwitch, "Already inside switch()");
	g_State.isInsideSwitch = true;
end

function hdl_OnSwitchExit()
	assert(g_State.isInsideSwitch, "Not inside switch()");
	g_State.isInsideSwitch = false;
end

function hdl_OnCaseEnter()
	assert(not g_State.isInsideCase, "Already inside case() or default()");
	g_State.isInsideCase = true;
end

function hdl_OnCaseExit()
	assert(g_State.isInsideCase, "Not inside case() or default()");
	g_State.isInsideCase = false;
end

function hdl_IsInsideCase()
	return g_State.isInsideCase;
end

function hdl_IsInsideSwitch()
	return g_State.isInsideSwitch;
end
