require('../logic/sop');
require('../logic/factorization');

-- Kernel generation example
-- F = ace + bce + de + g
F = sop({
    cubeFromStrings("1-1-1--"),
    cubeFromStrings("-11-1--"),
    cubeFromStrings("---11--"),
    cubeFromStrings("------1"),
});

R = kernel(0, sopMakeCubeFree(F));
assert(R.n == 3);

vars = { "a", "b", "c", "d", "e", "f", "g" };
print("Kernels of F = " .. nodeToString(nodeSOP(F), vars));
for i=1,R.n do
    print("- " .. nodeToString(nodeSOP(R[i]), vars));
end

print("1st 0-level kernel of F is: " .. nodeToString(nodeSOP(sopQuickDivisor(F)), vars));
