-- Switch-level simulator as described in 
-- "A Switch-Level Model and Simulator for MOS Digital Systems"
-- https://ieeexplore.ieee.org/document/1676408

-- NOTE: All constants start at 1 in order to be able to be used as array indices.
kTransistorTypeP = 1;
kTransistorTypeN = 2;
kTransistorTypeD = 3;

-- The elements of T are partially ordered 0 < X and 1 < X
kState0 = 1;
kState1 = 2;
kStateX = 3;

-- Most MOS circuits can be modeled with at most three node sizes
-- (K1,K2,Omega), with high capacitance nodes such as precharged
-- buses assigned size K2 and all other storage nodes assigned size K1.
-- Most, CMOS circuits do not involve ratioing, and hence, can be modeled with
-- one transistor strength (G1). 
-- Most NMOS circuits can be modeled with just two strengths (G1, G2)
-- with pullup load transistors having strength G1 and all others having
-- strength G2.
kSizeLambda = 0;
kSizeKappa1 = 1; -- default node size
kSizeKappa2 = 2;
kSizeGamma1 = 3;
kSizeGamma2 = 4; -- default transistor size
kSizeOmega  = 5; -- input node size

kSizeGammaMax = kSizeGamma2;

kStepLimit = 1000;

kTransistorState = {
    [kTransistorTypeP] = { [kState0] = kState1, [kState1] = kState0, [kStateX] = kStateX },
    [kTransistorTypeN] = { [kState0] = kState0, [kState1] = kState1, [kStateX] = kStateX },
    [kTransistorTypeD] = { [kState0] = kState1, [kState1] = kState1, [kStateX] = kState1 }
};

kTransistorStateName = {
    [kState0] = "open",
    [kState1] = "closed",
    [kStateX] = "ind"
};

kNodeStateName = {
    [kState0] = "low",
    [kState1] = "high",
    [kStateX] = "undef"
};

function set()
    return { n = 0 };
end

function setPut(S, x)
    local sz = S.n + 1;
    S[sz] = x;
    S.n = sz;
    return sz;
end

function setGet(S)
    assert(S.n > 0);
    local x = S[S.n];
    S[S.n] = nil;
    S.n = S.n - 1;
    return x;
end

function setClear(S)
    S.n = 0;
end

function setInsert(S, x)
    local n = S.n;
    for i=1,n do
        if(S[i] == x) then
            return;
        end
    end

    setPut(S, x);
end

function node(name, state, size)
    size = size or kSizeKappa1;
    local n = {
        name = name,
        state = kStateX,
        newState = state,
        size = size,
        q = size,
        u = size,
        d = size,
        found = true,
        done = true,
        fanoutSet = set(),
        inputConSet = set(),
        storageConSet = set()
    };

    return n;
end

function nodeSetState(n, state)
    assert(n.size == kSizeOmega);
    n.newState = state;
end

function isInputNode(n)
    return n.size == kSizeOmega;
end

function isStorageNode(n)
    return n.size ~= kSizeOmega;
end

-- the storage connectivity set contains transistors which connect this node to
-- other storage nodes.
-- the input connectivity set contains transistors which connect this node to 
-- input nodes.
function nodeConnection(node, other, transistor)
    if(isInputNode(other)) then
        setInsert(node.inputConSet, transistor);
    else
        assert(isStorageNode(other));
        setInsert(node.storageConSet, transistor);
    end 
end

function connectNodes(n1, n2, transistor)
    nodeConnection(n1, n2, transistor);
    nodeConnection(n2, n1, transistor);    
end

function transistor(name, type, gate, drain, source, size)
    size = size or kSizeGamma2;

    -- Each transistor record contains pointers to its source and drain
    -- nodes, labeled nodel and node2, with the convention that if
    -- either is an input node, it is labeled node 1.
    local n1 = isInputNode(drain) and drain or source;
    local n2 = drain == n1 and source or drain;

    local t = {
        name = name,
        state = kStateX,
        strength = size,
        type = type,
        node1 = n1,
        node2 = n2,
    };

    -- the fanout set contains transistors for which this node is the gate
    setPut(gate.fanoutSet, t);
    connectNodes(drain, source, t);

    return t;
end

-- table 1
function tstate(nodeState, transistorType)
    return kTransistorState[transistorType][nodeState];
end

-- equation 8
function nstate(u, d)
    -- TODO: LUT?
    return (d == kSizeLambda and kState1) or ((u == kSizeLambda and kState0) or kStateX);
end

function phase(C)
    local E = set();

    for iChangedNode=1,C.n do
        local node = C[iChangedNode];

        local newNodeState = node.newState;
        node.state = newNodeState;
        for iTransistor=1,node.fanoutSet.n do
            local transistor = node.fanoutSet[iTransistor];

            local newTransistorState = tstate(newNodeState, transistor.type);
            if(newTransistorState ~= transistor.state) then
                transistor.state = newTransistorState;

                perturb(E, transistor.node1);
                perturb(E, transistor.node2);
            end
        end

        if(node.size == kSizeOmega) then
            for iTransistor=1,node.storageConSet.n do
                local transistor = node.storageConSet[iTransistor];
                if(transistor.state == kState1 or transistor.state == kStateX) then
                    perturb(E, transistor.node2);
                end
            end
        else
            perturb(E, node);
        end
    end

    setClear(C);

    local stepCount = 0;
    while(E.n > 0 and stepCount < kStepLimit) do
        E = step(E);
        stepCount = stepCount + 1;
    end
end

function perturb(E, node)
    if(node.size ~= kSizeOmega and node.done) then
        node.done = false;
        setPut(E, node);
    end
end

function step(E)
    local C = set();

    for iNode=1,E.n do
        local node = E[iNode];
        if(not node.done) then
            vicinityResponse(C, node);
        end
    end

    setClear(E);

    for iNode=1,C.n do
        local node = C[iNode];
        local newNodeState = node.newState;
        node.state = newNodeState;
        for iTransistor=1,node.fanoutSet.n do
            local transistor = node.fanoutSet[iTransistor];
            local newTransistorState = tstate(newNodeState, transistor.type);
            if(newTransistorState ~= transistor.state) then
                transistor.state = newTransistorState;

                perturb(E, transistor.node1);
                perturb(E, transistor.node2);
            end
        end
    end

    return E;
end

function vicinityResponse(C, node)
    local V = set();

    findVicinity(V, node);
    solveQ(V);
    solveU(V);
    solveD(V);

    for i=1,V.n do
        local vnode = V[i];
        vnode.found = false;
        vnode.newState = nstate(vnode.u, vnode.d);
        if(vnode.state ~= vnode.newState) then
            setPut(C, vnode);
        end
    end
end

function findVicinity(V, node)
    node.found = true;
    setPut(V, node);
    for i=1,node.storageConSet.n do
        local transistor = node.storageConSet[i];
        local otherNode = node == transistor.node1 and transistor.node2 or transistor.node1;
        if(not otherNode.found) then
            findVicinity(V, otherNode);
        end
    end
end

-- Solve equation (12) for Q
-- - b[i] = s[i] + SUM(j in Ii, G1[i,j])
-- - fij(q[j]) = G1[i,j]*q[j]
function solveQ(V)
    local L = { set(), set(), set(), set(), set(), set() };

    for i=1,V.n do
        local ni = V[i];
        ni.done = false;

        local bi = ni.size; -- bi = si

        for j=1,ni.inputConSet.n do
            local tj = ni.inputConSet[j];
            local tj_state = tj.state;
            if(tj_state == kState1) then
                local G1_ij = tj.strength;
                bi = bi > G1_ij and bi or G1_ij; -- bi = max(bi, G1[i,j])
            end
        end

        ni.q = bi;
        setPut(L[bi], ni);
    end

    for x=kSizeGammaMax,kSizeKappa1,-1 do
        while(L[x].n ~= 0) do
            local nj = setGet(L[x]);
            if(not nj.done) then
                nj.done = true;
                local qj = nj.q;
                for i=1,nj.storageConSet.n do
                    local tij = nj.storageConSet[i];
                    local tij_state = tij.state;
                    if(tij_state == kState1) then
                        local ni = nj == tij.node1 and tij.node2 or tij.node1;
                        local G1_ij = tij.strength;

                        local qval = qj < G1_ij and qj or G1_ij; -- min(qi, G1_ij)
                        if(qval > ni.q) then
                            ni.q = qval;
                            setPut(L[qval], ni);
                        end
                    end
                end
            end
        end
    end
end

-- Solve equation (12) for U
-- - bi = (up(si,yi) + SUM(j in Ii, up(GL[i,j] + GX[i,j], yj)])) ~ qi
-- - fij(aj) = ((G1[i,j] + GX[i,j])*aj) ~ qi.
function solveU(V)
    local L = { set(), set(), set(), set(), set(), set() };
    local u0 = set();

    for i=1,V.n do
        local ni = V[i];
        ni.done = false;

        local bi = ni.state == kState0 and kSizeLambda or ni.size; -- up(si, yi);

        for j=1,ni.inputConSet.n do
            local tj = ni.inputConSet[j];
            local tj_state = tj.state;
            if(tj_state == kState1 or tj_state == kStateX) then
                local nj = tj.node1 == ni and tj.node2 or tj.node1;
                local b_term = nj.state == kState0 and kSizeLambda or tj.strength; -- up(G1X_ij, yj);
                bi = bi > b_term and bi or b_term; -- max(bi, b_term)
            end
        end

        bi = bi >= ni.q and bi or kSizeLambda; -- bi ~ ni.q;
        ni.u = bi;
        if(bi >= kSizeKappa1) then
            setPut(L[bi], ni);
        else
            setPut(u0, ni);
        end
    end

    for x=kSizeGammaMax,kSizeKappa1,-1 do
        while(L[x].n ~= 0) do
            local nj = setGet(L[x]);
            if(not nj.done) then
                nj.done = true;
                local uj = nj.u;
                for i=1,nj.storageConSet.n do
                    local tij = nj.storageConSet[i];
                    local tij_state = tij.state;
                    if(tij_state == kState1 or tij_state == kStateX) then
                        local ni = nj == tij.node1 and tij.node2 or tij.node1;
                        local qi = ni.q;

                        local G1X_ij = tij.strength;

                        -- fij = [(G1(i,j) + GX[i,j])*aj]~qi
                        local min_term = uj < G1X_ij and uj or G1X_ij;
                        local uval = min_term >= qi and min_term or kSizeLambda; -- min(uj, G1X_ij) ~ qi;
                        if(uval >= ni.u) then
                            ni.u = uval;
                            if(uval >= kSizeKappa1) then
                                setPut(L[uval], ni);
                            end
                        end
                    end
                end
            end
        end
    end

    for i=1,u0.n do
        u0[i].done = true;
    end
end

-- Solve equation (12) for D
function solveD(V)
    local L = { set(), set(), set(), set(), set(), set() };
    local d0 = set();

    for i=1,V.n do
        local ni = V[i];
        ni.done = false;

        local bi = ni.state == kState1 and kSizeLambda or ni.size; -- down(si, yi);

        for j=1,ni.inputConSet.n do
            local tj = ni.inputConSet[j];
            local tj_state = tj.state;
            if(tj_state == kState1 or tj_state == kStateX) then
                local nj = tj.node1 == ni and tj.node2 or tj.node1;
                local b_term = nj.state == kState1 and kSizeLambda or tj.strength; -- down(G1X_ij, yj);
                bi = bi > b_term and bi or b_term; -- max(bi, b_term)
            end
        end

        bi = bi >= ni.q and bi or kSizeLambda; -- bi ~ ni.q;
        ni.d = bi;
        if(bi >= kSizeKappa1) then
            setPut(L[bi], ni);
        else
            setPut(d0, ni);
        end
    end

    for x=kSizeGammaMax,kSizeKappa1,-1 do
        while(L[x].n ~= 0) do
            local nj = setGet(L[x]);
            if(not nj.done) then
                nj.done = true;
                local dj = nj.d;
                for i=1,nj.storageConSet.n do
                    local tij = nj.storageConSet[i];
                    local tij_state = tij.state;
                    if(tij_state == kState1 or tij_state == kStateX) then
                        local ni = nj == tij.node1 and tij.node2 or tij.node1;
                        local qi = ni.q;

                        local G1X_ij = tij.strength;

                        -- fij = [(G1(i,j) + GX[i,j])*aj]~qi
                        local min_term = dj < G1X_ij and dj or G1X_ij;
                        local dval = min_term >= qi and min_term or kSizeLambda; -- min(dj, G1X_ij) ~ qi;
                        if(dval >= ni.d) then
                            ni.d = dval;
                            if(dval >= kSizeKappa1) then
                                setPut(L[dval], ni);
                            end
                        end
                    end
                end
            end
        end
    end

    -- Mark all d0 nodes as done for the next iteration
    for i=1,d0.n do
        d0[i].done = true;
    end
end

function mos()
    local m = {
        nodes = set(),
        transistors = set(),
        C = set()
    };

    return m;
end

function mosInput(m, state)
    local n = node("in" .. m.nodes.n, state or kStateX, kSizeOmega);
    setPut(m.C, n);
    return setPut(m.nodes, n);
end

function mosNode(m, size, state)
    local n = node("n" .. m.nodes.n, state or kStateX, size);
    setPut(m.C, n);
    return setPut(m.nodes, n);
end

function mosTransistor(m, type, gate, drain, source, size)
    gate = m.nodes[gate];
    drain = m.nodes[drain];
    source = m.nodes[source];
    local t = transistor("t" .. m.transistors.n, type, gate, drain, source, size);
    return setPut(m.transistors, t);
end

function mosSetNodeName(m, nodeID, name)
    m.nodes[nodeID].name = name;
end

function mosSetTransistorName(m, transistorID, name)
    m.transistors[transistorID].name = name;
end

function mosSetInputState(m, inputID, state)
    local n = m.nodes[inputID];
    nodeSetState(n, state);
    setInsert(m.C, n);
end

function mosGetNodeState(m, nodeID)
    return m.nodes[nodeID].state;
end

function mosSimulate(m)
    phase(m.C);
end

function mosDumpState(m)
    print("Nodes");
    for i=1,m.nodes.n do
        local n = m.nodes[i];
        print("- " .. n.name, kNodeStateName[n.state], "q:"..n.q, "u:"..n.u, "d:"..n.d);
    end
    print("Transistors");
    for i=1,m.transistors.n do
        local t = m.transistors[i];
        print("- " .. t.name, kTransistorStateName[t.state], t.strength);
    end
    print("");
end
