require("hdl/hdl");
require("hdl/dot_generator");
require("hdl/optimizer");

Xor = module[[Xor]](
function ()
	a = input(bit);
	b = input(bit);
	o = output((a & ~b) | (~a & b));
end);

-- Calculate (a ~ b) ~ c using the Xor module from above.
Xor3 = module[[Xor3]](
function ()
	a = input(bit);
	b = input(bit);
	c = input(bit);

	xAB = Xor{a = a, b = b};
	xABC = Xor{a = xAB.o, b = c};

	o = output(xABC.o);
end);

local dotfile = io.open("examples/dot/xor3.dot", "w");
dotfile:write(generate_dot_file(Xor3));
dotfile:close();

-- http://zipcpu.com/blog/2017/06/02/generating-timing.html
FractionalClockDiv = module[[Fractional Clock Divider]](
function ()
	i_clk = input(bit);
	i_rst = input(bit);

	cnt = register(bit[8], i_clk, ~i_rst);
  
	-- Since 'cnt' is an 8-bit register, 
	-- '+' will generate an 8-bit adder
	sum = cnt + 0x40;

	-- When the result of an 8-bit adder is used directly, 
	-- it's assumed to be a 8-bit signal.
	assign(cnt, sum);

	-- The carry out of an 8-bit adder is the 9-th bit.
	o_pix_stb = output(sum[9]);
end);

local dotfile = io.open("examples/dot/fractional_clock_divider.dot", "w");
dotfile:write(generate_dot_file(FractionalClockDiv));
dotfile:close();

TestOptimizer = module[[Test Optimizer]](
function ()
	a = input(bit);
	b = input(bit);

	nand = output(~(a & b));
	nor = output(~(a | b));
	zero = output(a & 0);
	one = output(b | 1);
end);

local dotfile = io.open("examples/dot/test_optimizer_pre.dot", "w");
dotfile:write(generate_dot_file(TestOptimizer));
dotfile:close();
local dotfile = io.open("examples/dot/test_optimizer_post.dot", "w");
dotfile:write(generate_dot_file(hdlProcessModule(TestOptimizer)));
dotfile:close();

TestIndexSliceConcat = module[[Test Index/Slice/Concat]](
function ()
	a = input(bit[4]);
	b = input(bit[8]);

	a12 = output(a(1,3));
	b5 = output(b[5]);
	a_b = output(a .. b);
end);

local dotfile = io.open("examples/dot/test_index_slice_concat.dot", "w");
dotfile:write(generate_dot_file(TestIndexSliceConcat));
dotfile:close();
