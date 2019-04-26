require('logic/sop');

-- Fig. 3.6.1
function sopSimplify(F)
	local j = binateSelect(F);
	if(j == 0) then
		-- F is unate.
		return sopUnateSimplify(F);
	end

	local desc = F.desc;
	local ni = desc.ni;
	local no = desc.no;

	local xj0, xj1 = cube_xj(ni, no, j);

	local Fxj0 = sopCofactor(F, xj0);
	local Fxj1 = sopCofactor(F, xj1);

	local Fxj0_simple = sopSimplify(Fxj0);
	local Fxj1_simple = sopSimplify(Fxj1);

	local Fprime = mergeWithContainment(xj0, Fxj0_simple, xj1, Fxj1_simple, 1);
	return Fprime.n < F.n and Fprime or F;
end

function sopUnateSimplify(F)
	local desc = F.desc;
	local Fprime = sopNew(desc.ni, desc.no);

	local n = F.n;
	for i=1,n do
		local Fi = F[i];
		local contained = false;
		for j=1,n do
			if(i ~= j) then
				if(cubeContains(F[j], Fi)) then
					contained = true;
					break;
				end
			end
		end

		if(not contained) then
			sopInsert(Fprime, Fi);
		end
	end

	return Fprime;
end

-- Fig. 4.2.1
function sopIsTautology(F)
	-- Special case #1: rows of DCs => tautology
	if(sopHasDontCareRow(F)) then
		return true;
	end

	-- Special case #2: column of all 1s or all 0s  => no tautology
	if(sopHas01Column(F)) then
		return false;
	end

	-- Special case #3: deficient vertex count => no tautology
	-- Calculate an upper bound of the number of minterms covered by F (sum of 2^number_of_DCs for each cube)
	local ni = F.desc.ni;
	local nrows = F.n;
	local maxMinterms = 0;
	for i=1,nrows do
		local ci = F[i];
		local numDCs = 0;
		for j=1,ni do
			numDCs = numDCs + (ci[j] == 3 and 1 or 0);
		end
		maxMinterms = maxMinterms + (1 << numDCs);
	end
	if(maxMinterms < (1 << ni)) then
		return false;
	end

	-- TODO: Special case #4: If n <= 7 map to truth table and check if it covers all cases.

	-- TODO: unateReduction(F);
	-- TODO: componentReduction(F);

	local j = binateSelect(F);
	if(j == 0) then
		-- From: http://www.cs.columbia.edu/~cs6861/handouts/tautology-handout.pdf
		-- For a single-output function, if the cover is unate, and the cover does not include 
		-- the universal cube, then the function is not a tautology.
		-- 
		-- We already tested for the universal cube and there's no binate variable so
		-- the function is unate and thus not a tautology.
		return false;
	end

	local xj0, xj1 = cube_xj(F.desc.ni, F.desc.no, j);

	local Fxj0 = sopCofactor(F, xj0);
	if(not sopIsTautology(Fxj0)) then
		return false;
	end

	local Fxj1 = sopCofactor(F, xj1);
	if(not sopIsTautology(Fxj1)) then
		return false;
	end

	return true;
end

-- In case F has multiple outputs, replicates each cube to have only one 1 in its
-- output part.
function sopUnwrap(F)
	local desc = F.desc;
	local ni = desc.ni;
	local no = desc.no;

	if(no == 1) then
		return F;
	end

	-- unwrap multiple outputs
	local nrows = F.n;
	local unwrapped = sopNew(ni, no);
	for i=1,nrows do
		local ci = F[i];
		for j=1,no do
			if(ci[ni + j] == 1) then
				local copy_ci = cubeCopy(ci);
				for k=1,no do
					copy_ci[ni + k] = 0;
				end
				copy_ci[ni + j] = 1;
				sopInsert(unwrapped, copy_ci);
			end
		end
	end

	return unwrapped;
end

-- Fig 4.1.1
function sopComplement(F, D)
	local desc = F.desc;
	local ni = desc.ni;
	local no = desc.no;
	
	local R = sopNew(ni, no);

	for i=1,no do
		local uj = cube_uj(ni, no, i);
		local ujOutputs = cubeGetOutputs(uj);

		local FiuDi = sopExtract(F, D, i);
		local Ri = comp1(FiuDi);

		for j=1,Ri.n do
			sopInsert(R, cube(cubeGetInputs(Ri[j]), ujOutputs));
		end
	end

	return R;
end

-- NOTE: Instead of returning 2 matrices this function
-- returns their union.
function sopExtract(F, D, outputID)
	local desc = F.desc;
	local ni = desc.ni;
	local no = desc.no;

	local m = sopNew(ni, 1);

	local nrowsF = F.n;
	for i=1,nrowsF do
		local ci = F[i];
		local output = ci[ni + outputID];
		if(output == 1) then
			sopInsert(m, cube(cubeGetInputs(ci)));
		end
	end

	if(D ~= nil) then
		assert(D.desc == desc);

		local nrowsD = D.n;
		for i=1,nrowsD do
			local ci = D[i];
			local output = ci[ni + outputID];
			if(output == 1) then
				matrixInsert(m, cube(cubeGetInputs(ci)));
			end
		end
	end

	return m;
end

-- Fig. 4.1.2
function comp1(F)
	local desc = F.desc;
	local ni = desc.ni;
	local no = desc.no;

	if(sopHasDontCareRow(F)) then
		-- F is a tautology; its complement is empty
		return sopNew(ni, no);
	end

	if(sopIsUnate(F)) then
		return unateComplement(F);
	end

	local nr = F.n;
	local c = cubeCopy(F[1]);
	for i=1,ni do
		local ci = c[i];
		if(ci ~= 3) then
			for j=2,nr do
				if(ci ~= F[j][i]) then
					c[i] = 3;
					break;
				end
			end
		end
	end

	-- TODO: DeMorgan's law to avoid calling unateComplement()
	-- TODO: Check if c is the universal cube to avoid both unateComplement() and matrixCofactor()
	local R = unateComplement(sop({ c }));
	F = sopCofactor(F, c);

	local j = binateSelect(F);
	local xj0, xj1 = cube_xj(ni, no, j);

	local Fxj0 = sopCofactor(F, xj0);
	local Fxj1 = sopCofactor(F, xj1);

	local Fbxj0 = comp1(Fxj0);
	local Fbxj1 = comp1(Fxj1);

	local R2 = mergeWithContainment(xj0, Fbxj0, xj1, Fbxj1, 0);
	return sopMerge(R, R2);
end

-- Fig. 3.2.1
function mergeWithContainment(x0, H0, x1, H1, CONTAIN)
	assert(H0.desc == H1.desc);
	local desc = H0.desc;

	local k = H0.n;
	local p = H1.n;
	local H2 = sopNew(desc.ni, desc.no);

	local i = 1;
	while(i <= k) do
		local h0i = H0[i];

		local j = 1;
		while(j <= p) do
			if(cubeEqual(h0i, H1[j])) then
				sopInsert(H2, h0i);
				sopRemove(H0, i);
				sopRemove(H1, j);

				i = i - 1;
				p = p - 1;
				k = k - 1;
				break;
			end

			j = j + 1;
		end

		i = i + 1;
	end

	if(not CONTAIN) then
		local x0H0 = sopCubeAnd(H0, x0);
		local x1H1 = sopCubeAnd(H1, x1);
		return sopOr(H2, sopOr(x0H0, x1H1));
	end

	k = H0.n;
	p = H1.n;
	i = 1;
	while(i <= k) do
		local h0i = H0[i];

		local j = 1;
		while(j <= p) do
			local h1j = H1[j];

			if(cubeContains(h0i, h1j)) then
				sopInsert(H2, h1j);
				sopRemove(H1, j);

				p = p - 1;
			elseif(cubeContains(h1j, h0i)) then
				sopInsert(H2, h0i);
				sopRemove(H0, i);

				i = i - 1;
				k = k - 1;
				break;
			else
				j = j + 1;
			end
		end

		i = i + 1;
	end

	local x0H0 = sopCubeAnd(H0, x0);
	local x1H1 = sopCubeAnd(H1, x1);
	return sopOr(H2, sopOr(x0H0, x1H1));
end

-- Fig. 3.4.1
-- NOTE: Not exactly the same.
-- Find the "most" binate variable.
-- A return value of 0 indicates that C was unate and no variable was selected. 
function binateSelect(C)
	local desc = C.desc;
	local ni = desc.ni;
	local nrows = C.n;

	-- TODO: Reverse inner/outer loops?
	local max = 0;
	local var = 0;
    for j=1,ni do
        local pj = { 0, 0, 0 };
		for i=1,nrows do
            local cij = C[i][j];
            pj[cij] = pj[cij] + 1;
		end

		-- If p01 isn't equal to 0 it means that the variable takes a value
		-- other than DC. In order for it to be considered (i.e. be binate)
		-- p0j and p1j should both be greater than 0 (i.e. the variable
        -- appears both complemented and uncomplemented in at least 1 cube).
        local p0j = pj[1];
        local p1j = pj[2];
		local p01 = p0j + p1j;
		if(p01 ~= 0 and p0j ~= 0 and p1j ~= 0) then
			if(p01 > max) then
				max = p01;
				var = j;
			end
		end
	end

	return var;
end

-- Fig. 3.5.1
function unateComplement(F)
	local M = persMatrix(F);
	local V, invV = monotone(F);
	local Mb = persUnateComplement(M, V);
	local R = translate(Mb, invV);
	return R;
end

function persMatrix(F)
    --assert(F.desc.no == 1, "Cannot construct personality matrix for multi-output cover");

	local ni = F.desc.ni;
	local nrows = F.n;

	local M = {
		nr = nrows,
		nc = ni
	};
	for i=1,nrows do
		local c = F[i];
		local row = {};
		for j=1,ni do
			local cj = c[j];
			row[j] = cj == 3 and 0 or 1;
		end
		M[i] = row;
	end

	return M;
end

-- NOTE: Assumes F is unate. Returns a vector with size equal to the number of inputs
-- where each element represents whether F is monotonically increasing or decreasing 
-- w.r.t. the corresponding input.
function monotone(F)
	local ni = F.desc.ni;
	local nrows = F.n;

	local V = {};
	local invV = {};
	for j=1,ni do
		V[j] = 3;
		invV[j] = 3;
		for i=1,nrows do
			local cij = F[i][j];
			if(cij ~= 3) then
				V[j] = cij;
				invV[j] = cij == 1 and 2 or 1;

				-- Since we know that F is unate we don't expect to find any cube with cij
				-- other than the current value or don't care. So no need to scan the rest
				-- of the cubes.
				break;
			end
		end
	end

	return V, invV;
end

-- Translate a personality matrix M into a cover based on the monotonicity of each
-- variable from V.
function translate(M, V)
	assert(M.nc == #V);
	local ni = M.nc;
	local nrows = M.nr;

	local F = sopNew(ni, 1);
	for i=1,nrows do
		local mi = M[i];
		local row = {};
		for j=1,ni do
			local mij = mi[j];
			row[j] = mij == 0 and 3 or V[j];
		end

		sopInsert(F, cube(row));
	end

	return F;
end

-- Fig. 3.5.2
-- Given M, the personality of a matrix of a unate function computes Mb
-- the personality of a matrix representation of the complement.
function persUnateComplement(M, V)
	assert(M.nr == #M);
	local nrows = M.nr;
	local ni = M.nc;

	-- Special case: M is empty. The complement is a tautology.
	if(nrows == 0) then
		local t = {};
		for i=1,ni do
			t[i] = 0;
		end

		local Mb = { nr = 1, nc = ni };
		Mb[1] = t;
		return Mb;
	end

	-- Special case: Check if there's a row with all 0s (don't cares). =>
	-- The function is a tautology and the complement of the function is empty.
	for i=1,nrows do
		local sum = 0;
		local mi = M[i];
		for j=1,ni do
			sum = sum + mi[j];
		end

		if(sum == 0) then
			local Mb = { nr = 0, nc = ni };
			return Mb;
		end
	end

	-- TODO: Special case: M has only one term => 
	-- The complement is computed by DeMorgan's law. Mb has one row.

	-- No special case found.
	-- Select the splitting variable
	local j = ucompSelect(M);

	-- Compute the personality matrix of the cofactors w.r.t. xj.
	local M1, M0 = persCofactors(M, j, V);

	local M1b = persUnateComplement(M1, V);
	local M0b = persUnateComplement(M0, V);

	-- Reinsert xj into the correct branch
	if(V[j] == 1) then
		-- Monotone decreasing in splitVar.
		local M1b_rows = M1b.nr;
		for i=1,M1b_rows do
			M1b[i][j] = 1;
		end
	else
		-- Monotone increasing in splitVar.
		local M0b_rows = M0b.nr;
		for i=1,M0b_rows do
			M0b[i][j] = 1;
		end
	end

	return persMerge(M1b, M0b);
end

-- Fig. 3.5.3
-- Given a personality matrix M with n columns
-- and k rows. selects a splitting variable j
function ucompSelect(M)
	local nrows = M.nr;
	local ni = M.nc;

	-- Select the largest cube
	-- Count the number of 1s in each row and find the row with the minimum number
	local minTerms = ni + 1;
	local minID = 0;
	for i=1,nrows do
		local mi = M[i];
		local sum = 0;
		for j=1,ni do
			sum = sum + mi[j];
		end

		if(sum < minTerms) then
			minTerms = sum;
			minID = i;
		end
	end

	-- Select the set of variables in the largest cube
	local J = {};
	local largestCube = M[minID];
	for i=1,ni do
		if(largestCube[i] == 1) then
			J[#J + 1] = i;
		end
	end

	-- Select the most frequently appearing variable
	local nvars = #J;
	if(nvars == 1) then
		return J[1];
	end

	local splitVar = 0;
	local maxCubes = 0;
	for i=1,nvars do
		local var = J[i];
		local sum = 0;
		for j=1,nrows do
			sum = sum + M[j][var];
		end
		if(sum > maxCubes) then
			maxCubes = sum;
			splitVar = var;
		end
	end

	return splitVar;
end

-- Merges 2 personality matrices. Only identical rows are identified.
-- NOTE: Merges b into a and returns a. 
function persMerge(a, b)
	assert(a.nr == #a);
	assert(b.nr == #b);
	assert(a.nc == b.nc);
	local ni = a.nc;
	local arows = a.nr;
	local brows = b.nr;

	local M = a;

	-- Insert all rows from b into M only if the rows doesn't already exists in a
	for j=1,brows do
		local br = b[j];
		local found = false;
		for i=1,arows do
			local ar = a[i];

			local equal = true;
			for k=1,ni do
				if(ar[k] ~= br[k]) then
					equal = false;
					break;
				end
			end

			if(equal) then
				found = true;
				break;
			end
		end

		if(not found) then
			M[M.nr + 1] = br;
			M.nr = M.nr + 1;
		end
	end

	return M;
end

function persCofactors(M, var, V)
	local nrows = M.nr;
	local ni = M.nc;
	local M0 = { nr = 0, nc = ni };
	local M1 = { nr = 0, nc = ni };

	local varValue = V[var];

	for i=1,nrows do
		local mi = M[i];
		local mi_var = mi[var];
		if(mi_var == 0) then
			-- Cube does not depend on the specified variable (dont care). Add it to both
			-- cofactors.
			M0[M0.nr + 1] = { table.unpack(mi) };
			M0.nr = M0.nr + 1;

			M1[M1.nr + 1] = { table.unpack(mi) };
			M1.nr = M1.nr + 1;
		else
			-- Cube depends on the specified variable. Add it to the cofactor based on V.
			if(varValue == 1) then
				local m0_row = { table.unpack(mi) };
				m0_row[var] = 0;
				M0[M0.nr + 1] = m0_row;
				M0.nr = M0.nr + 1;
			else
				assert(varValue == 2);
				local m1_row = { table.unpack(mi) };
				m1_row[var] = 0;
				M1[M1.nr + 1] = m1_row;
				M1.nr = M1.nr + 1;
			end
		end
	end

	return M1, M0;
end
