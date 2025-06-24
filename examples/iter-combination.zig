const std = @import("std");
const zf = @import("zaffi");

const IterCombination = struct {
    iter: zf.DataIter([]const u8, 64),
    arena: std.heap.ArenaAllocator,

    nextitem: ?[]const u8 = null,

    pub fn next(self: *IterCombination) []const u8 {
        if (self.nextitem) |v| {
            self.nextitem = null;
            return v;
        }
        return self.iter.next() orelse @panic("no next item");
    }

    pub fn hasNext(self: *IterCombination) bool {
        if (self.nextitem != null) return true;
        self.nextitem = self.iter.next();
        return self.nextitem != null;
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
        fn seq(_: void, value: *u16) u16 {
            const v = value.*;
            value.* += 1;
            return v;
        }

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
    defer arena.deinit();
    const alloc = arena.allocator();
    const len: u6 = @intCast(characters.len);
    std.debug.assert(1 <= combinationLength and combinationLength <= len and len <= 15);

    const lim: usize = @as(usize, 1) << len;
    const iter = zf.gen.always(void{})
        .asiter()
        .mapctx(thunk.seq, 0)
        .limit(lim)
        .filterctx(thunk.filter, combinationLength)
        .mapctx(thunk.maskstr, .{ characters, alloc });

    const flat = zf.flatiter([]const u8, iter);

    return IterCombination{
        .arena = arena,
        .iter = flat,
    };
}

pub fn main() !void {
    var it1 = try itercombination("abc", 2);
    while (it1.hasNext()) std.debug.print("{s}\n", .{it1.next()});

    var it2 = try itercombination("abcdef", 4);
    while (it2.hasNext()) std.debug.print("{s}\n", .{it2.next()});
}
