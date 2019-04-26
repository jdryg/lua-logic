require('../logic/sop');
require('../logic/algorithms');

F = sop({
    cubeFromStrings("-1-0"),
    cubeFromStrings("--10"),
    cubeFromStrings("1-11"),
    cubeFromStrings("0---")
});

assert(not sopIsTautology(F));
