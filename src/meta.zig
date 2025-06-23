const std = @import("std");

/// creates a function to reduce a tow nullable values to one
pub fn reduce(comptime T: type) (fn (??T) ?T) {
    const thunk = struct {
        fn unwrap(value: ??T) ?T {
            return if (value) |v| v else null;
        }
    };
    return thunk.unwrap;
}

pub fn transpose(comptime T: type, value: ?anyerror!T) anyerror!?T {
    // yeah dont think about it too much, this is why I made a function to do
    // this
    return (value orelse return null) catch |e| return e;
}

// pub fn flattranspose(comptime T: type, value: ?anyerror!T) anyerror!T {
//     return (value orelse return error.Missing) catch |e| return e;
// }

test "the trans" {
    const err1: ?anyerror!u8 = error.Test;
    try std.testing.expectError(error.Test, transpose(u8, err1));

    // try std.testing.expectError(error.Missing, flattranspose(u8, null));
}
