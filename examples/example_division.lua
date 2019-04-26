require('../logic/sop');
require('../logic/factorization');

-- Algebraic division example from http://www.ece.utah.edu/~kalla/ECE5740/alg-div.pdf
-- F = ace + ade + bc + bd + be + a'b + ab
F = sop({
    cubeFromStrings("1-1-1"),
    cubeFromStrings("1--11"),
    cubeFromStrings("-11--"),
    cubeFromStrings("-1-1-"),
    cubeFromStrings("-1--1"),
    cubeFromStrings("01---"),
    cubeFromStrings("11---"),
});

-- G = ae + b
G = sop({
    cubeFromStrings("1---1"),
    cubeFromStrings("-1---"),
});

-- H = c + d
-- R = be + a'b + ab
-- F = (c + d)(ae + b) + be + a'b + ab
H, R = sopWeakDiv(F, G);
assert(#H == 2);
assert(sopHasCube(H, cubeFromStrings("--1--")) ~= 0);
assert(sopHasCube(H, cubeFromStrings("---1-")) ~= 0);
assert(#R == 3);
assert(sopHasCube(R, cubeFromStrings("-1--1")) ~= 0);
assert(sopHasCube(R, cubeFromStrings("01---")) ~= 0);
assert(sopHasCube(R, cubeFromStrings("11---")) ~= 0);
