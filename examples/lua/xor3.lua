function xor3(a, b, c)
	local a1 = a[1];
	local a2 = a[2];
	local b1 = b[1];
	local b2 = b[2];
	local n71 = b2;
	local n72 = b1;
	local n51 = a1 | n71;
	local n52 = a2 & n72;
	local n101 = a2;
	local n102 = a1;
	local n91 = n101 | b1;
	local n92 = n102 & b2;
	local n41 = n51 & n91;
	local n42 = n52 | n92;
	local c1 = c[1];
	local c2 = c[2];
	local n111 = c2;
	local n112 = c1;
	local n31 = n41 | n111;
	local n32 = n42 & n112;
	local n141 = n42;
	local n142 = n41;
	local n131 = n141 | c1;
	local n132 = n142 & c2;
	local n21 = n31 & n131;
	local n22 = n32 | n132;
	local o = { n21, n22 };
	return o;
end