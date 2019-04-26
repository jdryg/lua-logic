require('logic/sop');

-- TODO: Tests before performing division
-- 
-- G is not an algebraic divisor of F if:
-- 1. G contains a literal not in F.
-- 3. For any literal, its count in G exceeds that in F.
-- 4. F is in the transitive fanin of G.
function sopWeakDiv(F, G)
	assert(F.desc == G.desc);
	local desc = F.desc;
	local ni = desc.ni;
	local no = desc.no;

	local fnr = F.n;
	local gnr = G.n;

	-- G is not an algebraic divisor of F if:
	-- 2. G has more terms than F.
	if(gnr > fnr) then
		return nil, F;
	end

	local H = nil;
	for i=1,gnr do
		local gi = G[i];
		local Vgi = sopNew(ni, no);

		for j=1,fnr do
			local fj = F[j];
			
			-- check if fj contains all literals of gi
			local containsAll = true;
			local vij = cubeCopy(fj);
			for k=1,ni do
				local gik = gi[k];
				if(gik ~= 3) then
					if(fj[k] ~= gik) then
						containsAll = false;
						break;
					else
						vij[k] = 3;
					end
				end
			end

			if(containsAll) then
				if(sopHasCube(Vgi, vij) == 0) then
					sopInsert(Vgi, vij);
				end
			end
		end

		if(H == nil) then
			H = Vgi;
		else
			-- Keep all common cubes between H and Vgi
			-- i.e. check which cubes of H is in Vgi; if not found remove from H
			for j=H.n,1,-1 do
				if(sopHasCube(Vgi, H[j]) == 0) then
					sopRemove(H, j);
				end
			end
		end

		if(H.n == 0) then
			return nil, F;
		end
	end

	local GH = sopAnd(G, H);
	local R = sopNew(ni, no);
	for i=F.n,1,-1 do
		if(sopHasCube(GH, F[i]) == 0) then
			sopInsert(R, F[i]);
		end
	end

	return H, R;
end

-- TODO: Alters cubes in matrix F
function sopMakeCubeFree(F)
	local desc = F.desc;
	local ni = desc.ni;
	local nr = F.n;
	if(nr == 0) then
		return F;
	end

	for j=1,ni do
		local val = F[1][j];
		if(val ~= 3) then
			for i=2,nr do
				if(val ~= F[i][j]) then
					val = 3;
					break;
				end
			end

			if(val ~= 3) then
				for i=1,nr do
					F[i][j] = 3;
				end
			end
		end
	end

	return F;
end

function sopIsCubeFree(F)
	local desc = F.desc;
	local ni = desc.ni;
	local nr = F.n;

	if(nr == 0) then
		return true;
	end

	for j=1,ni do
		local val = F[1][j];
		if(val ~= 3) then
			for i=2,nr do
				if(val ~= F[i][j]) then
					val = 3;
					break;
				end
			end

			if(val ~= 3) then
				return false;
			end
		end
	end

	return true;
end

function sopCommonCube(F)
	local ni = F.desc.ni;
	local literals = getLiteralFrequency(F);

	local nrows = F.n;
	local commonInputs = {};
	local hasCommon = false;
	for i=1,ni do
		local literalID = i << 1;
		if(literals[literalID] == nrows) then
			hasCommon = true;
			commonInputs[i] = 2;
		elseif(literals[literalID - 1] == nrows) then
			hasCommon = true;
			commonInputs[i] = 1;
		else
			commonInputs[i] = 3;
		end
	end

	return hasCommon and cube(commonInputs) or nil;
end

-- Returns the first Kernel-0 divisor
function sopQuickDivisor(F)
	local k0 = kernel0(0, F);
	return k0.n == 0 and nil or k0[1];
end

function sopQuickFactor(F)
	return gfactor(F, sopQuickDivisor, sopWeakDiv);
end

function kernel(j, G)
	local desc = G.desc;
	local ni = desc.ni;
	local no = desc.no;

	local R = set();

	local literals = getLiteralFrequency(G);

	local numLiterals = ni * 2;
	for i=j+1,numLiterals do
		local freq = literals[i];
		if(freq > 1) then
			local id = i - 1;
			local inputID = (id >> 1) + 1;
			local complement = (id & 1) == 0;

			local li = complement and cube_xj0(ni, no, inputID) or cube_xj1(ni, no, inputID);
			local Q = sopWeakDiv(G, sop({ li }));
			if(Q ~= nil and Q.n > 0) then
				-- if there exists k <= i such as lk belongs to all cubes of Q, continue;
				local common_lk = true;
				for k=1,i do
					local lkFreq = literals[k];
					if(lkFreq >= 1) then
						local lkInput = ((k - 1) >> 1) + 1;
						local lkVal = ((k - 1) & 1) == 0 and 1 or 2;

						for c=1,Q.n do
							local Qc = Q[c];
							if(Qc[lkInput] ~= lkVal) then
								common_lk = false;
								break;
							end
						end

						if(not common_lk) then
							break;
						end
					end
				end

				if(not common_lk) then
					local RQ = kernel(i, sopMakeCubeFree(Q), literals);
					setUnion(R, RQ);
				end
			end
		end
	end

	-- G is supposed to be cube free so it's a kernel of itself (co-kernel = 1).
	setAdd(R, G);
	return R;
end

-- Same as kernel() but returns the first found 0-level kernel
function kernel0(j, G, literals)
	local desc = G.desc;
	local ni = desc.ni;
	local no = desc.no;

	local R = set();

	local literals = getLiteralFrequency(G);

	local numLiterals = ni * 2;
	for i=j+1,numLiterals do
		local freq = literals[i];
		if(freq > 1) then
			local id = i - 1;
			local inputID = (id >> 1) + 1;
			local complement = (id & 1) == 0;

			local li = complement and cube_xj0(ni, no, inputID) or cube_xj1(ni, no, inputID);
			local Q = sopWeakDiv(G, sop({ li }));
			if(Q ~= nil and Q.n > 0) then
				-- if there exists k <= i such as lk belongs to all cubes of Q, continue;
				local common_lk = true;
				for k=1,i do
					local lkFreq = literals[k];
					if(lkFreq >= 1) then
						local lkInput = ((k - 1) >> 1) + 1;
						local lkVal = ((k - 1) & 1) == 0 and 1 or 2;

						for c=1,Q.n do
							local Qc = Q[c];
							if(Qc[lkInput] ~= lkVal) then
								common_lk = false;
								break;
							end
						end

						if(not common_lk) then
							break;
						end
					end
				end

				if(not common_lk) then
					local RQ = kernel0(i, sopMakeCubeFree(Q), literals);
					if(RQ.n > 0) then
						return RQ;
					end
				end
			end
		end
	end

	-- G is supposed to be cube free so it's a kernel of itself (co-kernel = 1).
	setAdd(R, G);
	return R;
end

-- Returns an array with size 2*n where n is the number of inputs of F
-- { freq_x0b, freq_x0, freq_x1b, freq_x1, ..., freq_xnb, freq_xn }
function getLiteralFrequency(F)
	local ni = F.desc.ni;

	local literals = {};
	for j=1,ni do
		local n = { 0, 0, 0 };
		for i=1,F.n do
			local Fij = F[i][j];
			n[Fij] = n[Fij] + 1;
		end

		local id = j << 1;
		literals[id] = n[2];
		literals[id - 1] = n[1];
	end

	return literals;
end

function gfactor(F, divisor, divide)
	if(F.n == 0) then 
		return nodeSOP(F);
	end

	if(sopHasDontCareRow(F)) then
		return nil;
	end

	local D = divisor(F);
	if(D == nil) then
		return nodeSOP(F);
	end

	local Q = divide(F, D);
	if(Q.n == 1) then
		return cubeIsUniverse(Q[1]) and nodeSOP(F) or lf(F, Q[1], divisor, divide);
	end

	Q = sopMakeCubeFree(Q);
	local R;
	D,R = divide(F, Q);
	local c = sopCommonCube(D);
	if(c == nil) then
		Q = gfactor(Q, divisor, divide);
		D = gfactor(D, divisor, divide);
		R = gfactor(R, divisor, divide);

		-- Q*D + R
		return nodeOr2(nodeAnd2(Q, D), R);
	else
		return lf(F, c, divisor, divide);
	end
end

function lf(F, c, divisor, divide)
	local l = bestLiteral(F, c);
	local Q, R = divide(F, sop({ l }));
	local cc = sopCommonCube(Q);
	if(cc ~= nil) then
		Q = sopMakeCubeFree(Q);
	end
	local nodeQ = gfactor(Q, divisor, divide);
	local nodeR = gfactor(R, divisor, divide);

	-- l*cc*Q + R
	if(cc ~= nil) then
		return nodeOr2(nodeAnd3(nodeCube(l), nodeCube(cc), nodeQ), nodeR);
	end		
	return nodeOr2(nodeAnd2(nodeCube(l), nodeQ), nodeR);
end

function bestLiteral(F, c)
	local literals = getLiteralFrequency(F);

	local maxFreq = 0;
	local best = 0;
	local ni = F.desc.ni;
	for i=1,ni do
		local ci = c[i];
		if(ci ~= 3) then
			local literalID = ((i - 1) << 1) + ci;
			local literalFreq = literals[literalID];
			assert(literalFreq ~= 0);
			if(literalFreq > maxFreq) then
				maxFreq = literalFreq;
				best = i;
			end
		end
	end

	local no = F.desc.no;
	return c[best] == 1 and cube_xj0(ni, no, best) or cube_xj1(ni, no, best);
end

kAlgNodeTypeCube = "cube";
kAlgNodeTypeMatrix = "matrix";
kAlgNodeTypeAnd = "and";
kAlgNodeTypeOr = "or";

function nodeCube(c)
	if(cubeIsUniverse(c)) then
		return nil;
	end

	return {
		type = kAlgNodeTypeCube,
		c = c
	};
end

function nodeSOP(m)
	if(m.n == 0) then
		return nil;
	elseif(m.n == 1) then
		return nodeCube(m[1]);
	end

	return {
		type = kAlgNodeTypeMatrix,
		m = m
	};
end

function nodeAnd2(n1, n2)
	if(n1 == nil) then
		return n2;
	elseif(n2 == nil) then
		return n1;
	end

	return {
		type = kAlgNodeTypeAnd,
		operands = { n1, n2 }
	};
end

function nodeAnd3(n1, n2, n3)
	if(n1 == nil) then
		return nodeAnd2(n2, n3);
	elseif(n2 == nil) then
		return nodeAnd2(n1, n3);
	elseif(n3 == nil) then
		return nodeAnd2(n1, n2);
	end

	return {
		type = kAlgNodeTypeAnd,
		operands = { n1, n2, n3 }
	};
end

function nodeOr2(n1, n2)
	if(n1 == nil) then
		return n2;
	elseif(n2 == nil) then
		return n1;
	end

	return {
		type = kAlgNodeTypeOr,
		operands = { n1, n2 }
	};
end

function nodeOr3(n1, n2, n3)
	if(n1 == nil) then
		return nodeOr2(n2, n3);
	elseif(n2 == nil) then
		return nodeOr2(n1, n3);
	elseif(n3 == nil) then
		return nodeOr2(n1, n2);
	end

	return {
		type = kAlgNodeTypeOr,
		operands = { n1, n2, n3 }
	};
end

function nodeToString(n, varNames)
	local str = "";
	local type = n.type;
	if(type == kAlgNodeTypeCube) then
		local c = n.c;
		local desc = c.desc;
		local ni = desc.ni;
		local literals = {};
		for i=1,ni do
			local ci = c[i];
			if(ci ~= 3) then
				literals[#literals + 1] = (ci == 1 and "\\" or "") .. varNames[i];
			end
		end
		str = table.concat(literals, "*");
	elseif(type == kAlgNodeTypeMatrix) then
		local m = n.m;
		local desc = m.desc;
		local ni = desc.ni;
		local products = {};
		for i=1,m.n do
			local mi = m[i];
			local literals = {};
			for j=1,ni do
				local mij = mi[j];
				if(mij ~= 3) then
					literals[#literals + 1] = (mij == 1 and "\\" or "") .. varNames[j];
				end
			end
			products[#products + 1] = table.concat(literals, "*");
		end
		str = "(" .. table.concat(products, " + ") .. ")";
	elseif(type == kAlgNodeTypeAnd) then
		local operands = n.operands;
		local operandStrs = {};
		for i=1,#operands do
			operandStrs[#operandStrs + 1] = nodeToString(operands[i], varNames);
		end
		str = table.concat(operandStrs, "*");
	elseif(type == kAlgNodeTypeOr) then
		local operands = n.operands;
		local operandStrs = {};
		for i=1,#operands do
			operandStrs[#operandStrs + 1] = nodeToString(operands[i], varNames);
		end
		str = "(" .. table.concat(operandStrs, " + ") .. ")";
	end

	return str;
end

function set(comparator)
	return { 
		n = 0,
		compare = comparator or setDefaultEqCompare
	};
end

function setUnion(a, b)
	for i=1,b.n do
		a[a.n + i] = b[i];
	end
	a.n = a.n + b.n;
end

-- Add element without checking if it exists
function setAdd(S, v)
	S[S.n + 1] = v;
	S.n = S.n + 1;
end

-- Add element only if it doesn't already exists
function setInsert(S, v)
	local comp = S.compare;
	for i=1,S.n do
		if(comp(S[i], v)) then
			return;
		end
	end

	setAdd(S, v);
end
