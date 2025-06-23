const std = @import("std");
const zf = @This();


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

pub inline fn asiter(iter: anytype) Iterator(@TypeOf(iter)) {
    return .{ .iter = iter };
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
            return zf.asiter( zf.groups(self, size));
        }

        pub inline fn map(self: @This(), comptime func: anytype) Iterator(MapFuncCtx(@This(), @TypeOf(func), void)) {
            return zf.asiter(zf.map(self, func));
        }

        pub inline fn flatmap(self: @This(), comptime func: anytype) Iterator(Flatten(MapFuncCtx(@This(), @TypeOf(func), void))) {
            return zf.asiter( zf.flatten(zf.map(self, func)));
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

/// The internal iterator declaration. Add all util functions to this struct.
pub fn MapCtx(
    comptime Iter: type,
    comptime fO: type,
    comptime Ctx: type,
) type {
    // TODO: handle pointers to an iterable

    const ti = @typeInfo(Iter);
    const InnerIter = if (ti == .pointer) ti.pointer.child else Iter;

    if (!std.meta.hasFn(InnerIter, "next")) {
        @compileError("iter " ++ @typeName(InnerIter) ++ " does not have a 'next' function");
    }

    const iterfunc = @field(InnerIter, "next");
    const func = @typeInfo(@TypeOf(iterfunc)).@"fn";
    const SomeT = func.return_type.?;
    const tiSomeT = @typeInfo(SomeT);
    if (tiSomeT != .optional) @compileError("iter.next() must return an optional type");
    const fT = tiSomeT.optional.child;

    return struct {
        pub const T = fT;
        pub const O = fO;

        iter: Iter,
        func: *const fn (T, Ctx) O,
        ctx: Ctx,

        pub fn next(self: *@This()) ?O {
            const item = self.iter.next() orelse return null;
            return self.func(item, self.ctx);
        }

        pub fn asiter(self: @This()) Iterator(@This()) {
            return Iterator(@This()){ .iter = self };
        }
    };
}

pub fn MapFuncCtx(
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

pub fn Zip(comptime Iters: anytype) type {
    // Check if we have at least one iterator
    if (Iters.len == 0) @compileError("Zip requires at least one iterator");

    // Create arrays of types for the result tuple and iters tuple
    var resultTypes: [Iters.len]type = undefined;
    var iterTypes: [Iters.len]type = undefined;

    // Extract type information for each iterator
    inline for (Iters, 0..) |IterType, i| {
        // std.builtin.Type.StructField.

        const ti = @typeInfo(IterType.type);
        const InnerIter = if (ti == .pointer) ti.pointer.child else IterType.type;

        if (!std.meta.hasFn(InnerIter, "next")) {
            @compileError("iter " ++ @typeName(InnerIter) ++ " does not have a 'next' function");
        }

        const iterfunc = @field(InnerIter, "next");
        const func = @typeInfo(@TypeOf(iterfunc)).@"fn";
        const SomeItem = func.return_type.?;
        const tiSomeItem = @typeInfo(SomeItem);

        if (tiSomeItem != .optional) {
            @compileError("iter.next() must return an optional type");
        }

        resultTypes[i] = tiSomeItem.optional.child;
        iterTypes[i] = IterType.type;
    }

    // Create tuple types
    const ResultTuple = std.meta.Tuple(&resultTypes);
    const IterTuple = std.meta.Tuple(&iterTypes);

    return struct {
        // Store all iterators
        iters: IterTuple,

        pub const O = ResultTuple;

        pub fn next(self: *@This()) ?O {
            var result: O = undefined;

            // Try to get the next item from each iterator
            inline for (&self.iters, 0..) |*iter, i| {
                result[i] = iter.next() orelse return null;
            }

            return result;
        }

        pub fn asiter(self: @This()) Iterator(@This()) {
            return Iterator(@This()){ .iter = self };
        }
    };
}

pub fn zip(iters: anytype) Zip(std.meta.fields(@TypeOf(iters))) {
    return .{ .iters = iters };
}

pub fn Always(comptime T: type) type {
    return struct {
        value: T,

        pub fn next(self: *@This()) ?T {
            return self.value;
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
        value: []const T,
        index: usize = 0,

        pub fn next(self: *@This()) ?T {
            if (self.index >= self.value.len) return null;
            const value = self.value[self.index];
            self.index += 1;
            return value;
        }

        pub fn asiter(self: @This()) Iterator(@This()) {
            return .{ .iter = self };
        }
    };
}

pub fn buffer(value: anytype) Iterator( Buffer(@TypeOf(value))) {
    return Iterator(Buffer(@TypeOf(value))){
        .iter = .{ .value = value },
    };
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

        pub fn asiter(self: @This()) Iterator(@This()) {
            return .{ .iter = self };
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

// pub fn maperr(
//     // comptime T: type
//     iter: anytype,
// ) !MapCtx() {
//     const T = iter.O;

//     const thunk = struct {
//         fn doit(value: anyerror!T, err: *?anyerror) ?T {
//             if (err.* != null) return null;
//             return value catch |e| {
//                 err.* = e;
//                 return null;
//             };
//         }
//     };
//     mapctx(
//         iter,
//     )
//     return thunk.doit;
// }

// pub fn tryit(comptime T: type) (fn (anyerror!T, *?anyerror) ?T) {
// }

// pub fn reduce(comptime T: type) (fn (??T) ?T) {
//     const thunk = struct {
//         fn unwrap(value: ??T) ?T {
//             return if (value) |v| v else null;
//         }
//     };

//     return thunk.unwrap;
// }
