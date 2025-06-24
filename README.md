# Zaffi - Zig Allocation Free Functional Interface

Meta functions for zig.

## Usage
There are some Leetcode problems solved in the examples folder. I hope the
elegance of the solution speaks to the simplicity of this api.

In general, anything that has a next function is an iterator and can be used
as input to this library.

If you want to test if your object passes try setting it as input to
`zf.asiter`.

## Warning
A Generic `zf.AnyIterator` is provided but it is not recomended to use it as
there are lots of foot guns. Just dont make be smart about pointers to the
stack.

# TODO
Currently, the compiler does not unroll these functions the same way it does in
rust and cpp. I dont know why.
