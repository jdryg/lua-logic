require('../logic/logic3');

function testFromInt()
    local s65535 = signalFromInt(65535, 16);
    assert(s65535[1] == 0);
    assert(s65535[2] == 65535);
end

function testFromString()
    local s = signalFromString("10-01-");
    assert(s[1] == 29);
    assert(s[2] == 43);
end

testFromInt();
testFromString();
