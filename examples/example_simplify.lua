require('../logic/sop');
require('../logic/algorithms');

-- page 51
F = sop({
    cubeFromStrings("0--"),
    cubeFromStrings("11-"),
    cubeFromStrings("-11"),
});

Fsimple = sopSimplify(F);
assert(#Fsimple == 2);
assert(sopHasCube(Fsimple, cubeFromStrings("-1-")) ~= 0);
assert(sopHasCube(Fsimple, cubeFromStrings("0--")) ~= 0);
