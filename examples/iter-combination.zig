const std = @import("std");
const zf = @import("zaffi");

const thunk = struct {
    fn countbits(value: u16, count: *u16) bool {
        return @popCount(value) == count.*;
    }

    fn maskstr(mask: u16, ctx: *struct { std.heap.ArenaAllocator, []const u8 }) []const u8 {
        var arena = ctx.@"0";
        const alloc = arena.allocator();

        const str = ctx.@"1";

        var buf = std.ArrayList(u8).init(alloc);
        defer buf.deinit();

        var i: u4 = 0;
        while (i < 16 and i < str.len) : (i += 1) {
            if ((@as(u16, 1) << i) & mask != 0) {
                buf.append(str[i]) catch @panic("OOM");
            }
        }
        return buf.toOwnedSlice() catch @panic("OOM");
    }
};

// 1286. Iterator for Combination

// Design the CombinationIterator class:
//
// CombinationIterator(string characters, int combinationLength) Initializes
// the object with a string characters of sorted distinct lowercase English
// letters and a number combinationLength as arguments. next() Returns the next
// combination of length combinationLength in lexicographical order. hasNext()
// Returns true if and only if there exists a next combination.
//
// Explanation
// CombinationIterator itr = new CombinationIterator("abc", 2);
// itr.next();    // return "ab"
// itr.hasNext(); // return True
// itr.next();    // return "ac"
// itr.hasNext(); // return True
// itr.next();    // return "bc"
// itr.hasNext(); // return False
//
//
// Constraints:
//
// 1 <= combinationLength <= characters.length <= 15
// All the characters of characters are unique.
// At most 104 calls will be made to next and hasNext.
// It is guaranteed that all calls of the function next are valid.
const IterCombination = struct {
    iter: zf.Peekable(zf.Iterator(zf.MapCtx(zf.Iterator(zf.FilterCtx(zf.Iterator(zf.gen.Range(u16)), thunk.countbits)), thunk.maskstr))),
    arena: std.heap.ArenaAllocator,

    pub fn init(characters: []const u8, combinationLength: u16) !IterCombination {
        const arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const len: u4 = @intCast(characters.len);
        std.debug.assert(1 <= combinationLength and combinationLength <= len and len <= 15);

        const lim: u16 = @as(u16, 1) << len;
        const iter = zf.gen.range(@as(u16, 0), lim)
            .asiter()
            .filterctx(thunk.countbits, combinationLength)
            .mapctx(thunk.maskstr, .{ arena, characters });

        const data = zf.peekable(iter);

        return IterCombination{ .iter = data, .arena = arena };
    }

    pub fn deinit(self: *IterCombination) void {
        self.arena.deinit();
    }

    pub fn next(self: *IterCombination) []const u8 {
        return self.iter.next() orelse @panic("no next item");
    }

    pub fn hasNext(self: *IterCombination) bool {
        return self.iter.peek() != null;
    }
};

pub fn main() !void {
    var it1 = try IterCombination.init("abc", 2);
    defer it1.deinit();

    while (it1.hasNext()) std.debug.print("{s}\n", .{it1.next()});

    var it2 = try IterCombination.init("abcdef", 4);
    defer it2.deinit();

    while (it2.hasNext()) std.debug.print("{s}\n", .{it2.next()});
}
