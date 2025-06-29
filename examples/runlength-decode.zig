//! Solution to leetcode problem 900: RLE Iterator

const zf = @import("zaffi");
const std = @import("std");

pub fn main() !void {
    var buffer: [64]u8 = undefined;

    const numbers1 = [_]u8{ 3, 8, 2, 5 };
    std.debug.print("inpt: {d}\n", .{numbers1});
    std.debug.print("nums: {d}\n", .{runlengthdecode(buffer[0..], &numbers1)});

    const numbers2 = [_]u8{ 3, 8, 0, 9, 2, 5 };
    std.debug.print("inpt: {d}\n", .{numbers2});
    std.debug.print("nums: {d}\n", .{runlengthdecode(buffer[0..], &numbers2)});

    const numbers3 = [_]u8{ 2, 8, 1, 8, 2, 5 };
    std.debug.print("inpt: {d}\n", .{numbers3});
    std.debug.print("nums: {d}\n", .{runlengthdecode(buffer[0..], &numbers3)});
}

/// We can use run-length encoding (i.e., RLE) to encode a sequence of integers.
/// In a run-length encoded array of even length encoding (0-indexed), for all
/// even i, encoding[i] tells us the number of times that the non-negative
/// integer value encoding[i + 1] is repeated in the sequence. For example, the
/// sequence arr = [8,8,8,5,5] can be encoded to be encoding = [3,8,2,5].
/// encoding = [3,8,0,9,2,5] and encoding = [2,8,1,8,2,5] are also valid RLE of
/// arr.
///
/// Given a run-length encoded array, design an iterator that iterates through it.
///
/// Implement the RLEIterator class:
///
///     RLEIterator(int[] encoded) Initializes the object with the encoded array encoded.
///     int next(int n) Exhausts the next n elements and returns the last element exhausted in this way. If there is no element left to exhaust, return -1 instead.
///
/// Constraints:
///
///     2 <= encoding.length <= 1000
///     encoding.length is even.
///     0 <= encoding[i] <= 109
///     1 <= n <= 109
///     At most 1000 calls will be made to next.
///
fn runlengthdecode(buffer: []u8, iter: []const u8) []u8 {
    const thunk = struct {
        fn produce(value: [2]u8) zf.Limit(zf.gen.Always(u8)) {
            return zf.limit(zf.gen.always(value[1]), value[0]);
        }

        fn loadbuffer(value: struct { u8, usize }, buf: *[]u8) ?usize {
            const v = value[0];
            const idx = value[1];
            if (buf.len == 0) return null;
            buf.*[idx] = v;
            return idx + 1;
        }
    };


    const index = zf.gen.buffer(iter).asiter()
        .groups(2)
        .flatmap(thunk.produce)
        .enumerate()
        .mapctx(thunk.loadbuffer, buffer)
        .fuse().last() orelse 0;

    return buffer[0..index];
}
