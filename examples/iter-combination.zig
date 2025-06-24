const std = @import("std");
const zf = @import("zaffi");

var stat: zf.Peekable(zf.DataIter([]const u8, 40)) = undefined;

const IterCombination = struct {
    iter: zf.Peekable(zf.DataIter([]const u8, 40)),
    arena: std.heap.ArenaAllocator,

    pub fn next(self: *IterCombination) []const u8 {
        std.debug.assert(std.meta.eql(stat, self.iter));
        return self.iter.next() orelse @panic("no next item");
    }

    pub fn hasNext(self: *IterCombination) bool {
        return self.iter.peek() != null;
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
fn itercombination(characters: []const u8, combinationLength: u16) !IterCombination {
    const thunk = struct {
        fn filter(value: u16, count: *u16) bool {
            return @popCount(value) == count.*;
        }

        fn maskstr(mask: u16, ctx: *struct { []const u8, std.mem.Allocator }) []const u8 {
            const str = ctx.@"0";
            const alloc = ctx.@"1";

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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const len: u4 = @intCast(characters.len);
    // std.debug.assert(1 <= combinationLength and combinationLength <= len and len <= 15);

    const lim: u16 = @as(u16, 1) << len;
    const iter = zf.gen.range(@as(u16, 0), lim)
        .asiter()
        .filterctx(thunk.filter, combinationLength)
        .mapctx(thunk.maskstr, .{ characters, alloc });

    const data = zf.peekable(iter);

    return IterCombination{
        .arena = arena,
        .iter = data,
    };
}

pub fn main() !void {
    var it1 = try itercombination("abc", 2);
    while (it1.hasNext()) std.debug.print("{s}\n", .{it1.next()});
    defer it1.arena.deinit();

    var it2 = try itercombination("abcdef", 4);
    while (it2.hasNext()) std.debug.print("{s}\n", .{it2.next()});
    defer it2.arena.deinit();
}
