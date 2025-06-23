# Zaffi
Meta functions for zig.

## Usage
See examples full uses cases.

In general, anything that has a next function is an iterator and can be used
as input to this library.

If you want to test if your object passes try setting it as input to
`zf.asiter`.

## Warning
A Generic `zf.AnyIterator` is provided but it is not recomended to use it as
there are lots of foot guns.
