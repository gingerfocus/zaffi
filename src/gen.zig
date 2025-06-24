const zf = @import("lib.zig");

pub fn Always(comptime T: type) type {
    return struct {
        value: T,

        pub fn next(self: *@This()) ?T {
            return self.value;
        }

        pub fn asiter(self: @This()) zf.Iterator(@This()) {
            return zf.asiter(self);
        }
    };
}

pub fn always(value: anytype) Always(@TypeOf(value)) {
    return .{ .value = value };
}

pub fn Buffer(comptime Items: type) type {
    const ptr = @typeInfo(Items).pointer;
    // const msg = std.fmt.comptimePrint("{any}", .{ptr});
    if (ptr.size != .slice) {
        @compileError("Buffer only works with slices");
    }
    const T = ptr.child;
    return struct {
        items: []const T,
        index: usize = 0,

        pub fn next(self: *@This()) ?T {
            if (self.index >= self.items.len) return null;
            const value = self.items[self.index];
            self.index += 1;
            return value;
        }

        pub inline fn asiter(self: @This()) zf.Iterator(@This()) {
            return zf.asiter(self);
        }
    };
}

pub fn buffer(value: anytype) Buffer(@TypeOf(value)) {
    return Buffer(@TypeOf(value)){ .items = value };
}

pub fn Never(comptime T: type) type {
    return struct {
        _: void = {},

        pub fn next(_: *@This()) ?T {
            return null;
        }
    };
}

pub fn never(comptime T: type) Never(T) {
    return .{};
}

pub fn Once(comptime T: type) type {
    return struct {
        value: ?T,

        pub fn next(self: *@This()) ?T {
            const v = self.value orelse return null;
            self.value = null;
            return v;
        }
    };
}

pub fn once(value: anytype) Once(@TypeOf(value)) {
    return .{ .value = value };
}
