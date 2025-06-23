const std = @import("std");
const zf = @This();

pub const gen = @import("gen.zig");
pub const meta = @import("meta.zig");

pub fn AnyIterator(comptime T: type) type {
    return struct {
        dataptr: *anyopaque,
        vtable: *const struct {
            next: fn (self: *anyopaque) ?T,
        },

        pub fn next(self: *@This()) ?T {
            return self.vtable.next(self.dataptr);
        }

        pub fn asiter(self: @This()) Iterator(@This()) {
            return Iterator(@This()){ .iter = self };
        }
    };
}

pub fn Iterator(
    comptime Iter: type,
) type {
    const iter_info = @typeInfo(Iter);
    const InnerIter = if (iter_info == .pointer) iter_info.pointer.child else Iter;

    if (!std.meta.hasFn(InnerIter, "next")) {
        @compileError("type " ++ @typeName(InnerIter) ++ " does not have a 'next' function");
    }

    const iterfunc = @field(InnerIter, "next");
    const nextfunc = @typeInfo(@TypeOf(iterfunc)).@"fn";

    const SomeO = nextfunc.return_type.?;
    const tiSomeO = @typeInfo(SomeO);
    if (tiSomeO != .optional) @compileError("iter.next() must return an optional type");

    return struct {
        iter: Iter,

        pub const O = tiSomeO.optional.child;

        pub fn next(self: *@This()) ?O {
            return self.iter.next();
        }

        pub fn nextOr(self: *@This(), default: O) O {
            return self.next() orelse default;
        }

        pub fn collect(self: @This(), allocator: std.mem.Allocator) anyerror![]O {
            var iter = self;
            var list = std.ArrayList(O).init(allocator);
            defer list.deinit();

            while (iter.next()) |item| try list.append(item);
            return list.toOwnedSlice();
        }

        pub inline fn groups(self: @This(), comptime size: usize) Iterator(Groups(@This(), size)) {
            return zf.asiter(zf.groups(self, size));
        }

        pub inline fn map(self: @This(), comptime func: anytype) Iterator(MapFuncCtx(@This(), @TypeOf(func), void)) {
            return zf.asiter(zf.map(self, func));
        }

        pub inline fn flatmap(self: @This(), comptime func: anytype) Iterator(Flatten(MapFuncCtx(@This(), @TypeOf(func), void))) {
            return zf.asiter(zf.flatten(zf.map(self, func)));
        }

        pub fn asanyiter(self: @This()) AnyIterator(O) {
            return AnyIterator(O){
                .dataptr = self,
                .vtable = &.{
                    .next = next,
                },
            };
        }

        // pub fn windows(self: @This(), size) Window(@This()) {

    };
}

pub inline fn asiter(iter: anytype) Iterator(@TypeOf(iter)) {
    return .{ .iter = iter };
}

/// The internal map declaration
pub fn MapCtx(
    comptime Iter: type,
    comptime Output: type,
    comptime Ctx: type,
) type {
    const It = Iterator(Iter);

    return struct {
        pub const T = It.O;
        pub const O = Output;

        iter: Iter,
        func: *const fn (It.O, Ctx) O,
        ctx: Ctx,

        pub fn next(self: *@This()) ?O {
            const item = self.iter.next() orelse return null;
            return self.func(item, self.ctx);
        }

        pub inline fn asiter(self: @This()) Iterator(@This()) {
            return zf.asiter(self);
        }
    };
}

/// Helper function to create a MapCtx from a function
fn MapFuncCtx(
    comptime Iter: type,
    comptime Func: type,
    comptime Ctx: type,
) type {
    const ti = @typeInfo(Func);
    if (ti != .@"fn") @compileError("Func must be a function type");

    const O = ti.@"fn".return_type.?;
    return MapCtx(Iter, O, Ctx);
}

pub fn mapctx(iter: anytype, func: anytype, ctx: anytype) MapFuncCtx(@TypeOf(iter), @TypeOf(func), @TypeOf(ctx)) {
    return MapFuncCtx(@TypeOf(iter), @TypeOf(func), @TypeOf(ctx)){
        .iter = iter,
        .func = func,
        .ctx = ctx,
    };
}

pub fn map(iter: anytype, func: anytype) MapFuncCtx(@TypeOf(iter), @TypeOf(func), void) {
    const Output = MapFuncCtx(@TypeOf(iter), @TypeOf(func), void);

    // wrap the function in a thunk with no context
    const thunk = struct {
        fn inner(value: Output.T, _: void) Output.O {
            return @call(.always_inline, func, .{value});
        }
    };

    return Output{ .iter = iter, .func = thunk.inner, .ctx = {} };
}

pub fn Zip(comptime Iters: type) type {
    const ti = @typeInfo(Iters);
    if (ti != .@"struct") @compileError("Zip requires a tuple struct of iters");
    const feilds = ti.@"struct".fields;
    if (!ti.@"struct".is_tuple) @compileError("Zip requires a tuple struct of iters");

    if (feilds.len == 0) @compileError("Zip requires at least one iterator");

    // get the result types
    var results: [Iters.len]type = undefined;
    inline for (feilds, 0..) |feild, i| {
        results[i] = Iterator(feild.type).O;
    }
    const ResultTuple = std.meta.Tuple(&results);

    return struct {
        iters: Iters,

        pub const O = ResultTuple;

        pub fn next(self: *@This()) ?O {
            var result: O = undefined;

            // Try to get the next item from each iterator
            inline for (&self.iters, 0..) |*iter, i| {
                // TODO: This can discard some result values. Some deinit
                // functions would never be called.
                result[i] = iter.next() orelse return null;
            }

            return result;
        }

        pub inline fn asiter(self: @This()) Iterator(@This()) {
            return zf.asiter(self);
        }
    };
}

pub fn zip(iters: anytype) Zip(@TypeOf(iters)) {
    return .{ .iters = iters };
}

// pub fn Window(comptime Iter: type) type {

pub fn Groups(comptime Iter: type, comptime size: usize) type {
    const It = Iterator(Iter);

    return struct {
        pub const O = [size]It.O;

        iter: Iter,

        pub fn next(self: *@This()) ?O {
            var result: O = undefined;
            for (&result) |*item| {
                item.* = self.iter.next() orelse return null;
            }
            return result;
        }

        pub inline fn asiter(self: @This()) Iterator(@This()) {
            return .{ .iter = self };
        }
    };
}

pub fn groups(iter: anytype, comptime size: usize) Groups(@TypeOf(iter), size) {
    return .{ .iter = iter };
}

pub fn Flatten(comptime Iter: type) type {
    const It = Iterator(Iter);
    const InnerIter = Iterator(It.O);

    return struct {
        iter: Iter,
        current: ?It.O = null,

        pub fn next(self: *@This()) ?InnerIter.O {
            while (true) {
                if (self.current) |*current| {
                    const result = current.next() orelse {
                        self.current = null;
                        continue;
                    };
                    return result;
                } else {
                    self.current = self.iter.next() orelse return null;
                }
            }
        }

        pub inline fn asiter(self: @This()) Iterator(@This()) {
            return .{ .iter = self };
        }
    };
}

pub fn flatten(iter: anytype) Flatten(@TypeOf(iter)) {
    return .{ .iter = iter };
}

pub fn Limit(comptime Iter: type) type {
    const It = Iterator(Iter);

    return struct {
        pub const O = It.O;

        iter: Iter,
        index: usize = 0,
        size: usize,

        pub fn next(self: *@This()) ?O {
            if (self.index >= self.size) return null;
            const result = self.iter.next() orelse return null;
            self.index += 1;
            return result;
        }

        pub inline fn asiter(self: @This()) Iterator(@This()) {
            return zf.asiter(self);
        }
    };
}

pub fn limit(iter: anytype, size: usize) Limit(@TypeOf(iter)) {
    return .{ .iter = iter, .size = size };
}

test "test map" {
    const csvdata = "afafsa,afasf,asf ,12,wadf,,a";
    const iter = std.mem.splitScalar(u8, csvdata, ',');

    const thunk = struct {
        fn len(item: []const u8) usize {
            return item.len;
        }
        fn add(item: usize) usize {
            return item + 6;
        }
    };

    var new = map(
        map(iter, thunk.len),
        thunk.add,
    );

    // try std.testing.expectEqualStrings("thing", @typeName(@TypeOf(new)));

    try std.testing.expectEqual(new.next(), 12);
    try std.testing.expectEqual(new.next(), 11);
    try std.testing.expectEqual(new.next(), 10);
    try std.testing.expectEqual(new.next(), 8);
    try std.testing.expectEqual(new.next(), 10);
    try std.testing.expectEqual(new.next(), 6);
    try std.testing.expectEqual(new.next(), 7);
    try std.testing.expectEqual(new.next(), null);
}

