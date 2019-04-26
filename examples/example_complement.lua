require('../logic/sop');
require('../logic/algorithms');

F = sop({
    cubeFromStrings("-1111"),
    cubeFromStrings("-1110"),
    cubeFromStrings("-101-"),
    cubeFromStrings("-10-1")
});

Fb = sopComplement(F, nil);

-- Manual factoring/expansion of the terms and complementation gives:
-- F = x2*x3*x4*x5 + x2*x3*x4*x5b + x2*x3b*x4 + x2*x3b*x5 <=>
-- F = x2*x3*x4 + x2*x3b*x4 + x2*x3b*x5 <=>
-- F = x2*x4 + x2*x3b*x5 <=>
-- F = x2*(x4 + x3b*x5) =>
-- Fb = x2b + x3*x4b + x4b*x5b
assert(#Fb == 3);
assert(sopHasCube(Fb, cubeFromStrings("-0---")) ~= 0);
assert(sopHasCube(Fb, cubeFromStrings("--10-")) ~= 0);
assert(sopHasCube(Fb, cubeFromStrings("---00")) ~= 0);
