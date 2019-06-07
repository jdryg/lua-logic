require("hdl/hdl");
local class = require("util/middleclass");

-- Optimizer
Optimizer = class("Optimizer");

function Optimizer:initialize()
	self.visitedNodes = {};
	self.nodes = {};
	self.nextNewNodeUID = -1;
end

function Optimizer:getNodeOperandUIDs(node)
	local uids = {};
	for pinID, operand in pairs(node.operands) do
		local uid = self:flattenNode(operand);
		uids[pinID] = uid;
	end
	return uids;
end

function Optimizer:flattenNode(node)
	if(node._uid == nil) then
		node._uid = self.nextNewNodeUID;
		self.nextNewNodeUID = self.nextNewNodeUID - 1;
	end

	if(self.visitedNodes[node]) then
		return node._uid;
	end

	self.visitedNodes[node] = 1;

	node.operandIDs = self:getNodeOperandUIDs(node);
	self.nodes[node._uid] = node;

	return node._uid;
end

function Optimizer:foldNot(node)
	assert(isNode(node) and node.type == kNodeTypeNot);
	local operandID = node.operandIDs[1];
	if(operandID == nil) then
		return node;
	end

	local operand = self.nodes[operandID];
	if(operand == nil) then
		return node;
	end

	assert(isNode(operand));
	local operandType = operand.type;
	if(operandType == kNodeTypeConst) then
		-- not(const) = const
		return make_constant_node(node.size, (~operand.params.value) & ((1 << node.size.width) - 1));
	end

	return node;
end

function Optimizer:foldAnd(node)
	assert(isNode(node) and (node.type == kNodeTypeAnd or node.type == kNodeTypeNand));

	local size = node.size;
	assert(isSize(size));

	local operandIDs = node.operandIDs;
	local numOperands = #operandIDs;

	local maxValue = (1 << size.width) - 1;
	local nonConstOperands = {};
	local numConst = 0;
	local constValue = maxValue;

	for pinID, operandID in pairs(operandIDs) do
		local operand = self.nodes[operandID];
		assert(isNode(operand));

		if(operand.type == kNodeTypeConst) then
			numConst = numConst + 1;
			constValue = constValue & operand.params.value;
		else
			nonConstOperands[#nonConstOperands + 1] = operand;
		end
	end

	if(numConst ~= 0) then
		if(constValue == 0 or numOperands == numConst) then
			return make_constant_node(size, node.type == kNodeTypeAnd and constValue or ~constValue);
		else
			assert(numOperands ~= #nonConstOperands);
			if(constValue ~= maxValue) then
				-- Push constant at the end of the new operands list.
				nonConstOperands[#nonConstOperands + 1] = make_constant_node(size, constValue);
			end

			local numNewOperands = #nonConstOperands;
			if(numNewOperands >= 2) then
				if(numConst ~= 1) then
					return make_multi_input_node(node.type, table.unpack(nonConstOperands));
				end
			elseif(numNewOperands == 1) then
				return nonConstOperands[1];
			else
				if(node.type == kNodeTypeAnd) then
					return make_constant_node(size, maxValue);
				else
					return make_constant_node(size, 0);
				end
			end
		end
	end

	return node;
end

function Optimizer:foldOr(node)
	assert(isNode(node) and (node.type == kNodeTypeOr or node.type == kNodeTypeNor));

	local size = node.size;
	assert(isSize(size));

	local operandIDs = node.operandIDs;
	local numOperands = #operandIDs;

	local maxValue = (1 << #size) - 1;
	local nonConstOperands = {};
	local numConst = 0;
	local constValue = 0;

	for pinID, operandID in pairs(operandIDs) do
		local operand = self.nodes[operandID];
		assert(isNode(operand));

		if(operand.type == kNodeTypeConst) then
			numConst = numConst + 1;
			constValue = constValue | operand.params.value;
		else
			nonConstOperands[#nonConstOperands + 1] = operand;
		end
	end

	if(numConst ~= 0) then
		if(constValue == maxValue or numOperands == numConst) then
			return make_constant_node(size, node.type == kNodeTypeOr and constValue or ~constValue);
		else
			assert(numOperands ~= #nonConstOperands);
			if(constValue ~= 0) then
				-- Push constant at the end of the new operands list.
				nonConstOperands[#nonConstOperands + 1] = make_constant_node(size, constValue);
			end

			local numNewOperands = #nonConstOperands;
			if(numNewOperands >= 2) then
				if(numConst ~= 1) then
					return make_multi_input_node(node.type, table.unpack(nonConstOperands));
				end
			elseif(numNewOperands == 1) then
				return nonConstOperands[1];
			else
				if(node.type == kNodeTypeOr) then
					return make_constant_node(size, 0);
				else
					return make_constant_node(size, maxValue);
				end
			end
		end
	end

	return node;
end

function Optimizer:foldXor(node)
	assert(isNode(node) and node.type == kNodeTypeXor);

	local size = node.size;
	assert(isSize(size));

	local operandIDs = node.operandIDs;
	local numOperands = #operandIDs;
	assert(numOperands == 2, "Only 2-input XOR supported");
	
	local maxValue = (1 << size.width) - 1;
	local left = self.nodes[operandIDs[1]];
	local right = self.nodes[operandIDs[2]];
	
	local leftType = left and left.type or nil;
	local rightType = right and right.type or nil;
	if(leftType == kNodeTypeConst) then
		local leftValue = left.params.value;
		if(rightType == kNodeTypeConst) then
			-- Both operands are constants => Constant
			local rightValue = right.params.value;
			return make_constant_node(size, leftValue ~ rightValue);
		else
			if(leftValue == 0) then
				-- Xor'ing with 0 has no effect.
				return right;
			elseif(leftValue == maxValue) then
				-- Xor'ing with 1 inverts the other input.
				return make_unary_node(kNodeTypeNot, right);
			end
		end
	elseif(rightType == kNodeTypeConst) then
		local rightValue = right.params.value;
		if(rightValue == 0) then
			return left;
		elseif(rightValue == maxValue) then
			return make_unary_node(kNodeTypeNot, left);
		end
	elseif(left == right) then
		-- xor(x, x) = 0
		return make_constant_node(size, 0);
	end

	return node;
end

function Optimizer:foldIndex(node)
	assert(isNode(node) and node.type == kNodeTypeIndex);

	local operandIDs = node.operandIDs;
	assert(#operandIDs == 1);
	local operandID = operandIDs[1];

	local operand = self.nodes[operandID];
	local operandType = operand and operand.type or nil;
	if(operandType == kNodeTypeConst) then
		-- index(const) = const
		local value = operand.params.value;
		local index = node.params.index;
		local bitValue = (value >> (index - 1)) & 1;
		return make_constant_node(bit, bitValue);
	end

	return node;
end

function Optimizer:foldSlice(node)
	assert(isNode(node) and node.type == kNodeTypeSlice);

	local operandIDs = node.operandIDs;
	assert(#operandIDs == 1);
	local operandID = operandIDs[1];

	local operand = self.nodes[operandID];
	local operandType = operand and operand.type or nil;
	if(operandType == kNodeTypeConst) then
		-- slice(const) = const
		local value = operand.params.value;
		local start = node.params.start;
		local stop = node.params.stop;
		local mask = (1 << (stop - start)) - 1;
		local sliceValue = (value >> (start - 1)) & mask;
		return make_constant_node(bit, sliceValue);
	end

	return node;
end

function Optimizer:foldTristateBuffer(node)
	assert(isNode(node) and node.type == kNodeTypeTSBuf);

	local operandIDs = node.operandIDs;
	assert(#operandIDs == 2);
	local controlID = operandIDs[2];

	local control = self.nodes[controlID];
	local controlType = control and control.type or nil;
	if(controlType == kNodeTypeConst) then
		if(control.params.value == 1) then
			return self.nodes[operandIDs[1]];
		end
	end

	return node;
end

function Optimizer:foldComparator(node)
    local op = node.params.operator;
    local operandIDs = node.operandIDs;
    local size = node.size;

    assert(#operandIDs == 2, "Invalid number of operands in comparator node");
	local left = self.nodes[operandIDs[1]];
    local right = self.nodes[operandIDs[2]];

    local leftConst = left.type == kNodeTypeConst;
    local rightConst = right.type == kNodeTypeConst;
    if(leftConst and rightConst) then
        -- Both are constants
        return make_constant_node(bit, compareConstants(op, left.params.value, right.params.value));
    elseif(leftConst or rightConst) then
        -- At least one constant. Make sure the constant is the right operand to simplify the code below.
        if(leftConst) then
            local tmp = left;
            left = right;
            right = left;
            op = swapComparisonOp(op);
        end

        -- At this point the right operand is the ConstantNode.
        assert(right.type == kNodeTypeConst, "Right operand expected to be constant");
        assert(left.type ~= kNodeTypeConst, "Left operand expected to be non-constant");
        local maxValue = ((1 << #size) - 1);
        local constValue = right.params.value;
        if(op == "gt" and constValue == maxValue) then
            return make_constant_node(bit, 0);
        elseif(op == "le" and constValue == maxValue) then
            return make_constant_node(bit, 1);
        elseif(op == "lt" and constValue == 0) then
            return make_constant_node(bit, 0);
        elseif(op == "ge" and constValue == 0) then
            return make_constant_node(bit, 1);
        end
    elseif(left == right) then
        -- Both operands are the same. If the operator includes equality produce 1. Otherwise 0.
        if(op == 'eq' or op == 'le' or op == 'ge') then
            return make_constant_node(bit, 1);
        else -- if(op == 'ne' or op == 'lt' or op == 'gt') then
            return make_constant_node(bit, 0);
        end
    end

	return node;
end

function Optimizer:foldShifter(node)
	local operandIDs = node.operandIDs;
    assert(#operandIDs == 2, "Invalid number of operands in shift node");

	local size = node.size;

    local operand = self.nodes[operandIDs[1]];
    local amount = self.nodes[operandIDs[2]];
    assert(amount.type == kNodeTypeConst, "Shift amount should be a constant");

    if(amount.params.value == 0) then
        -- Shifting by 0 doesn't affect the output
        return operand;
    elseif(amount.params.value >= size.width) then
        -- Shifting by a value greater than or equal to the size of the operand
        -- always produces 0.
        return make_constant_node(size, 0);
    end

	return node;
end

function Optimizer:constantFolding()
	local newNodes = {};
	local numChanges = 0;
	for uid, node in pairs(self.nodes) do
		local nodeType = node.type;

		local newNode = node;
		if(nodeType == kNodeTypeNot) then
			newNode = self:foldNot(node);
		elseif(nodeType == kNodeTypeAnd or nodeType == kNodeTypeNand) then
			newNode = self:foldAnd(node);
		elseif(nodeType == kNodeTypeOr or nodeType == kNodeTypeNor) then
			newNode = self:foldOr(node);
		elseif(nodeType == kNodeTypeXor) then
			newNode = self:foldXor(node);
		elseif(nodeType == kNodeTypeIndex) then
			newNode = self:foldIndex(node);
		elseif(nodeType == kNodeTypeSlice) then
			newNode = self:foldSlice(node);
		elseif(nodeType == kNodeTypeTSBuf) then
			newNode = self:foldTristateBuffer(node);
		elseif(nodeType == kNodeTypeComparator) then
			newNode = self:foldComparator(node);
		elseif(nodeType == kNodeTypeShiftLeft or nodeType == kNodeTypeShiftRight) then
			newNode = self:foldShifter(node);
		elseif(nodeType == kNodeTypeAdder) then
			newNode = node.operands[1];
		end

		if(newNode ~= node) then
			newNode.operandIDs = self:getNodeOperandUIDs(newNode);
			newNodes[uid] = newNode;
			numChanges = numChanges + 1;
		else
			newNodes[uid] = node;
		end
	end

	self.nodes = newNodes;

	return numChanges;
end

function Optimizer:mergeNot(node)
	assert(isNode(node) and node.type == kNodeTypeNot);
	local operandID = node.operandIDs[1];
	if(operandID == nil) then
		return node;
	end

	local operand = self.nodes[operandID];
	if(operand == nil) then
		return node;
	end

	assert(isNode(operand));
	local operandType = operand.type;
	if(operandType == kNodeTypeAnd) then
		-- not(and(...)) = nand(...)
		local newNodeOperands = {};
		for i, suboperandID in pairs(operand.operandIDs) do
			newNodeOperands[#newNodeOperands + 1] = self.nodes[suboperandID];
		end
		return make_multi_input_node(kNodeTypeNand, table.unpack(newNodeOperands));
	elseif(operandType == kNodeTypeOr) then
		-- not(or(...)) = nor(...)
		local newNodeOperands = {};
		for i, suboperandID in pairs(operand.operandIDs) do
			newNodeOperands[#newNodeOperands + 1] = self.nodes[suboperandID];
		end
		return make_multi_input_node(kNodeTypeNor, table.unpack(newNodeOperands));
	elseif(operandType == kNodeTypeNand) then
		-- not(nand(...)) = and(...)
		local newNodeOperands = {};
		for i, suboperandID in pairs(operand.operandIDs) do
			newNodeOperands[#newNodeOperands + 1] = self.nodes[suboperandID];
		end
		return make_multi_input_node(kNodeTypeAnd, table.unpack(newNodeOperands));
	elseif(operandType == kNodeTypeNor) then
		-- not(nor(...)) == or(...)
		local newNodeOperands = {};
		for i, suboperandID in pairs(operand.operandIDs) do
			newNodeOperands[#newNodeOperands + 1] = self.nodes[suboperandID];
		end
		return make_multi_input_node(kNodeTypeOr, table.unpack(newNodeOperands));
	elseif(operandType == kNodeTypeNot) then
		-- not(not(x)) = x
		return self.nodes[operand.operandIDs[1]];
	end

	return node;
end

function Optimizer:mergeAnd(node)
	assert(isNode(node) and (node.type == kNodeTypeAnd or node.type == kNodeTypeNand));
	local operandIDs = node.operandIDs;
	local numOperands = #operandIDs;
	
	for pinID, operandID in pairs(operandIDs) do
		local operand = self.nodes[operandID];
		assert(isNode(operand));

		if(operand.type == kNodeTypeAnd) then
			-- and(and, ...) = and(...)
			local newNodeOperands = {};
			for i, suboperandID in pairs(operand.operandIDs) do
				newNodeOperands[#newNodeOperands + 1] = self.nodes[suboperandID];
			end
			for i, suboperandID in pairs(operandIDs) do
				if(i ~= pinID) then
					newNodeOperands[#newNodeOperands + 1] = self.nodes[suboperandID];
				end
			end

			return make_multi_input_node(node.type, table.unpack(newNodeOperands));
		end
	end

	return node;
end

function Optimizer:mergeOr(node)
	assert(isNode(node) and (node.type == kNodeTypeOr or node.type == kNodeTypeNor));
	local operandIDs = node.operandIDs;
	local numOperands = #operandIDs;
	
	for pinID, operandID in pairs(operandIDs) do
		local operand = self.nodes[operandID];
		assert(isNode(operand));

		if(operand.type == kNodeTypeOr) then
			-- or(or, ...) = or(...)
			local newNodeOperands = {};
			for i, suboperandID in pairs(operand.operandIDs) do
				newNodeOperands[#newNodeOperands + 1] = self.nodes[suboperandID];
			end
			for i, suboperandID in pairs(operandIDs) do
				if(i ~= pinID) then
					newNodeOperands[#newNodeOperands + 1] = self.nodes[suboperandID];
				end
			end

			return make_multi_input_node(node.type, table.unpack(newNodeOperands));
		end
	end

	return node;
end

function Optimizer:mergeMux(node)
	assert(isNode(node) and node.type == kNodeTypeMux);
	local operandIDs = node.operandIDs;
	local numOperands = #operandIDs;
	
	local firstOperand = nil
	for pinID, operandID in pairs(operandIDs) do
		if(pinID ~= numOperands) then
			local operand = self.nodes[operandID];
			assert(isNode(operand));

			if(firstOperand == nil) then
				firstOperand = operand;
			else
				if(firstOperand ~= operand) then
					return node;
				end
			end
		end
	end

	return firstOperand and firstOperand or node;
end

function Optimizer:nodeMerging()
	local newNodes = {};
	local numChanges = 0;
	for uid, node in pairs(self.nodes) do
		local nodeType = node.type;

		local newNode = node;
		if(nodeType == kNodeTypeNot) then
			newNode = self:mergeNot(node);
		elseif(nodeType == kNodeTypeAnd or nodeType == kNodeTypeNand) then
			newNode = self:mergeAnd(node);
		elseif(nodeType == kNodeTypeOr or nodeType == kNodeTypeNor) then
			newNode = self:mergeOr(node);
		elseif(nodeType == kNodeTypeMux) then
			newNode = self:mergeMux(node);
		end

		if(newNode ~= node) then
			newNode.operandIDs = self:getNodeOperandUIDs(newNode);
			newNodes[uid] = newNode;
			numChanges = numChanges + 1;
		else
			newNodes[uid] = node;
		end
	end

	self.nodes = newNodes;

	return numChanges;
end

function Optimizer:rebuild()
	for uid, node in pairs(self.nodes) do
		local operandIDs = node.operandIDs or {};
		node.operandIDs = nil;

		for pinID, operandUID in pairs(operandIDs) do
			local operand = self.nodes[operandUID];
			node.operands[pinID] = operand;
		end
	end
end

function optimize(module)
	while(true) do
		local opt = Optimizer:new();
		for i, output in ipairs(module.outputs) do
			opt:flattenNode(output);
		end

		if(opt:constantFolding() == 0) then
			if(opt:nodeMerging() == 0) then
				break;
			end
		end

		opt:rebuild();
		module.nodes = collectNodes(module);
	end

	return module;
end

Simplifier = class("Simplifier");

function Simplifier:initialize()
	self.visitedNodes = {};
end

function Simplifier:process(node)
	local nodeType = node.type;
	if(nodeType == kNodeTypeInput) then
		return node;
	end

	if(self.visitedNodes[node]) then
		return self.visitedNodes[node];
	end

	if(nodeType == kNodeTypeRegister) then
		self.visitedNodes[node] = node;

		local newOperands = {};
		for pinID, operand in pairs(node.operands) do
			newOperands[pinID] = self:process(operand);
		end
		node.operands = newOperands;
	else
		local wire = Node:new(node.size, nil, kNodeTypeWire, 1, 1, nil, nil);
		self.visitedNodes[node] = wire;

		local newOperands = {};
		for pinID, operand in pairs(node.operands) do
			newOperands[pinID] = self:process(operand);
		end

		local newNode = findOrCreateNode(node.size, node.name, nodeType, node.numInputs, node.numOutputs, newOperands, node.params);
		wire.operands[1] = newNode;
		self.visitedNodes[node] = newNode;
		return newNode;
	end

	return node;
end

function simplify(module)
	local simplifier = Simplifier:new();

	for i, output in ipairs(module.outputs) do
		local operand = output.operands[1];
		if(operand) then
			output.operands[1] = simplifier:process(operand);
		end
	end

	local nodes = collectNodes(module);

	-- Remove wires
	for i, node in ipairs(nodes) do
		local newOperands = {};
		for pinID, operand in pairs(node.operands) do
			local operandType = operand.type;
			if(operandType == kNodeTypeWire) then
				operand = operand.operands[1];
			end
			newOperands[pinID] = operand;
		end
		node.operands = newOperands;
	end

	module.nodes = collectNodes(module);

	return module;
end

g_NodeCache = {};

local function cache_get(cache, params)
	local node = cache
	for i=1, #params do
		node = node.children and node.children[params[i]]
		if not node then return nil end
	end
	return node.results
end
  
local function cache_put(cache, params, results)
	local node = cache
	local param
	for i=1, #params do
		param = params[i]
		node.children = node.children or {}
		node.children[param] = node.children[param] or {}
		node = node.children[param]
	end
	node.results = results
end

UNCONNECTED_PIN = {};

function findOrCreateNode(size, name, type, numInputs, numOutputs, operands, nodeParams)
	local params = {};
	params[1] = size.width;
	params[2] = name or "";
	params[3] = type;
	params[4] = numInputs;
	params[5] = numOutputs;
	for i=1,numInputs do
		params[5 + i] = operands[i] or UNCONNECTED_PIN;
	end
	for name, nodeParam in pairs(nodeParams) do
		params[#params + 1] = name .. "=" .. nodeParam;
	end

	local node = cache_get(g_NodeCache, params);
	if not node then
		node = Node:new(size, name, type, numInputs, numOutputs, operands, nodeParams);
		cache_put(g_NodeCache, params, node);
	end

	return node;
end

function hdlProcessModule(module)
	assert(module ~= nil, "hdlProcessModule(): nil module passed");
	
	local processed = module;
	for i = 1,2 do
		local opt = optimize(processed);
		assert(opt ~= nil, "hdlProcessModule(): Optimization pass #" .. i .. " failed.");

		local simple = simplify(opt);
		assert(simple ~= nil, "hdlProcessModule(): Simplification pass # " .. i .. " failed.");

		processed = simple;
	end

	return processed;
end

-- TODO: Check if this works correctly (probably not for large/negative integers
-- because it needs unsigned comparison to handle all possible values)
function compareConstants(op, l, r)
	assert(isInteger(l) and isInteger(r), "Expected integers");

	if(op == 'eq')      then return ((l ~ r) == 0) and 1 or 0;
	elseif(op == 'ne')  then return ((l ~ r) ~= 0) and 1 or 0;
	elseif(op == 'lt')  then return (l < r)  and 1 or 0;
	elseif(op == 'le')  then return (l <= r) and 1 or 0;
	elseif(op == 'gt')  then return (l > r)  and 1 or 0;
	elseif(op == 'ge')  then return (l >= r) and 1 or 0;
	end

	return 0;
end

-- Returns a new comparison operator when operands in a comparator switch places.
function swapComparisonOp(op)
	if(op == "lt")     then return "gt";
	elseif(op == "le") then return "ge";
	elseif(op == "gt") then return "lt";
	elseif(op == "ge") then return "le";
	end

	return op;
end

