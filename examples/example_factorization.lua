require('../logic/sop');
require('../logic/factorization');

-- QUICK_FACTOR example
-- x = ae + afg + afh + bce + bcfg + bcfh + bde + bdfg + bdfh <=> 
-- x = (b*(c + d) + a)*(f*(g + h) + e)
F = sop({
    cubeFromStrings("1---1---"),
    cubeFromStrings("1----11-"),
    cubeFromStrings("1----1-1"),
    cubeFromStrings("-11-1---"),
    cubeFromStrings("-11--11-"),
    cubeFromStrings("-11--1-1"),
    cubeFromStrings("-1-11---"),
    cubeFromStrings("-1-1-11-"),
    cubeFromStrings("-1-1-1-1"),
});
tree = sopQuickFactor(F);

vars = { "a", "b", "c", "d", "e", "f", "g", "h" };
print("x = " .. nodeToString(nodeSOP(F), vars));
print("x = " .. nodeToString(tree, vars));
