require('../mossim/mossim');

function example_CMOSInverter()
    local m = mos();

    local Vdd = mosInput(m, kState1);
    local Gnd = mosInput(m, kState0);
    local Nin = mosInput(m, kState0);
    local Nout = mosNode(m);

    local Tp = mosTransistor(m, kTransistorTypeP, Nin, Vdd, Nout);
    local Tn = mosTransistor(m, kTransistorTypeN, Nin, Nout, Gnd);

    mosSetNodeName(m, Vdd, "Vdd");
    mosSetNodeName(m, Gnd, "Gnd");
    mosSetNodeName(m, Nin, "in");
    mosSetNodeName(m, Nout, "out");
    mosSetTransistorName(m, Tp, "tP");
    mosSetTransistorName(m, Tn, "tN");

    mosDumpState(m);
    mosSimulate(m);
    mosDumpState(m);
    assert(mosGetNodeState(m, Nout) == kState1);

    mosSetInputState(m, Nin, kState1);
    mosSimulate(m);
    mosDumpState(m);
    assert(mosGetNodeState(m, Nout) == kState0);

    mosSetInputState(m, Nin, kStateX);
    mosSimulate(m);
    mosDumpState(m);
    assert(mosGetNodeState(m, Nout) == kStateX);
end

function example_nMOSNand2()
    local m = mos();
    local Vdd = mosInput(m, kState1);
    local Gnd = mosInput(m, kState0);
    local in1 = mosInput(m);
    local in2 = mosInput(m);
    local clock = mosInput(m, kState0);
    local a = mosNode(m);
    local b = mosNode(m);
    local out = mosNode(m);

    local d = mosTransistor(m, kTransistorTypeD, a, Vdd, a, kSizeGamma1);
    local n1 = mosTransistor(m, kTransistorTypeN, in1, a, b, kSizeGamma2);
    local n2 = mosTransistor(m, kTransistorTypeN, in2, b, Gnd, kSizeGamma2);
    local pass = mosTransistor(m, kTransistorTypeN, clock, a, out, kSizeGamma2);

    mosSetNodeName(m, Vdd, "Vdd");
    mosSetNodeName(m, Gnd, "Gnd");
    mosSetNodeName(m, in1, "A");
    mosSetNodeName(m, in2, "B");
    mosSetNodeName(m, clock, "clk");
    mosSetNodeName(m, a, "d_tA");
    mosSetNodeName(m, b, "tA_tB");
    mosSetNodeName(m, out, "out");

    mosSetTransistorName(m, d, "d");
    mosSetTransistorName(m, n1, "tA");
    mosSetTransistorName(m, n2, "tB");
    mosSetTransistorName(m, pass, "pass");

    mosDumpState(m);
    mosSimulate(m);
    mosDumpState(m);

    assert(mosGetNodeState(m, out) == kStateX);

    mosSetInputState(m, in2, kState1);
    mosSimulate(m);
    mosDumpState(m);
    assert(mosGetNodeState(m, out) == kStateX);

    mosSetInputState(m, in1, kState1);
    mosSimulate(m);
    mosDumpState(m);
    assert(mosGetNodeState(m, out) == kStateX);

    mosSetInputState(m, clock, kState1);
    mosSimulate(m);
    mosDumpState(m);
    assert(mosGetNodeState(m, out) == kState0);

    mosSetInputState(m, in2, kState0);
    mosSimulate(m);
    mosDumpState(m);
    assert(mosGetNodeState(m, out) == kState1);
end

example_CMOSInverter();
example_nMOSNand2();
