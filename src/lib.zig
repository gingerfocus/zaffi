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

pub fn DataIter(
    comptime T: type,
    comptime size: usize,
) type {
    return struct {
        data: [size]u8,
        nextfn: *const fn (*[size]u8) ?T,
        // nextfn: *const anyopaque,

        pub fn next(self: *@This()) ?T {
            // const func: *const fn (*[size]u8) ?T = @ptrCast(@alignCast(self.nextfn));
            return self.nextfn(@ptrCast(self));
        }
    };
}

pub fn flatiter(
    comptime T: type,
    iter: anytype,
) DataIter(T, @sizeOf(@TypeOf(iter))) {
    const Iter = @TypeOf(iter);
    const It = Iterator(Iter);
    const O = It.O;

    const size = @sizeOf(@TypeOf(iter));

    const thunk = struct {
        fn next(data: *[size]u8) ?O {
            std.debug.print("testing\n", .{});
            const self: *Iter = @ptrCast(@alignCast(data));
            return self.next();
        }
    };

    // const data = zf.asiter(iter);
    return DataIter(T, size){
        .data = std.mem.toBytes(iter),
        .nextfn = thunk.next,
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

        pub fn finish(self: @This()) void {
            var iter = self;
            while (iter.next()) |_| {}
        }

        pub fn last(self: @This()) ?O {
            var iter = self;
            var l: ?O = null;
            while (iter.next()) |item| l = item;
            return l;
        }

        pub fn collect(self: @This(), allocator: std.mem.Allocator) anyerror![]O {
            var iter = self;
            var list = std.ArrayList(O).init(allocator);
            defer list.deinit();

            while (iter.next()) |item| try list.append(item);
            return list.toOwnedSlice();
        }

        pub inline fn map(self: @This(), comptime func: anytype) Iterator(MapFunc(@This(), func)) {
            return zf.asiter(zf.map(self, func));
        }

        pub inline fn mapctx(self: @This(), comptime func: anytype, ctx: anytype) Iterator(MapCtx(@This(), func)) {
            return zf.asiter(zf.mapctx(self, func, ctx));
        }

        pub inline fn flatten(self: @This()) Iterator(Flatten(@This())) {
            return zf.asiter(zf.flatten(self));
        }

        pub inline fn flatmap(self: @This(), comptime func: anytype) Iterator(Flatten(MapFunc(@This(), func))) {
            return zf.asiter(zf.flatten(zf.map(self, func)));
        }

        pub inline fn filter(self: @This(), comptime pred: anytype) Iterator(Filter(@This(), pred)) {
            return zf.asiter(zf.filter(self, pred));
        }

        pub inline fn filterctx(self: @This(), comptime pred: anytype, ctx: anytype) Iterator(FilterCtx(@This(), pred)) {
            return zf.asiter(zf.filterctx(self, pred, ctx));
        }

        pub inline fn limit(self: @This(), size: usize) Iterator(Limit(@This())) {
            return zf.asiter(zf.limit(self, size));
        }

        pub inline fn fuse(self: @This()) Iterator(Fuse(@This())) {
            return zf.asiter(zf.fuse(self));
        }

        pub inline fn groups(self: @This(), comptime size: usize) Iterator(Groups(@This(), size)) {
            return zf.asiter(zf.groups(self, size));
        }

        fn enu(comptime T: type) fn (T, *usize) struct { T, usize } {
            return struct {
                fn inner(value: T, index: *usize) struct { T, usize } {
                    const result = struct { T, usize }{ value, index.* };
                    index.* += 1;
                    return result;
                }
            }.inner;
        }

        pub inline fn enumerate(self: @This()) Iterator(MapCtx(@This(), enu(O))) {
            return zf.asiter(zf.mapctx(self, enu(O), 0));
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

/// Helper function to create a MapCtx from a function
fn MapCtx(
    comptime Iter: type,
    comptime func: anytype,
) type {
    const Func = @TypeOf(func);

    const ti = @typeInfo(Func);
    if (ti != .@"fn") @compileError("func must be a function type");
    const Output = ti.@"fn".return_type.?;

    const params = ti.@"fn".params;
    std.debug.assert(params.len == 2);

    const Input = params[0].type.?;
    const It = Iterator(Iter);
    std.debug.assert(Input == It.O);

    const PointerCtx = params[1].type.?;
    const tiPointer = @typeInfo(PointerCtx);
    const Ctx = if (PointerCtx == void) void else if (tiPointer != .pointer) {
        @compileError("ctx must be a pointer");
    } else tiPointer.pointer.child;

    return struct {
        pub const T = It.O;
        pub const O = Output;
        const FunctionType = fn (T, PointerCtx) O;

        iter: Iter,
        ctx: Ctx,

        pub fn next(self: *@This()) ?O {
            const item = self.iter.next() orelse return null;
            const ctx = if (PointerCtx == void) {} else &self.ctx;
            return func(item, ctx);
        }

        pub inline fn asiter(self: @This()) Iterator(@This()) {
            return zf.asiter(self);
        }
    };
}

pub fn mapctx(iter: anytype, comptime func: anytype, ctx: anytype) MapCtx(@TypeOf(iter), func) {
    return .{
        .iter = iter,
        .ctx = ctx,
    };
}

/// Helper function to create a MapCtx from a function that has no context
fn MapFunc(
    comptime Iter: type,
    comptime func: anytype,
) type {
    const Tin = Iterator(Iter).O;
    const T = @typeInfo(@TypeOf(func)).@"fn".params[0].type.?;
    if (T != Tin) {
        @compileError(std.fmt.comptimePrint(
            \\ func has a mismatched input type from the iterator
            \\ func({s}) != Iter.O({s})
        , .{ @typeName(T), @typeName(Tin) }));
    }

    const O = @typeInfo(@TypeOf(func)).@"fn".return_type.?;

    // wrap the function in a thunk with no context
    const thunk = struct {
        fn inner(value: T, _: void) O {
            return @call(.always_inline, func, .{value});
        }
    };

    return MapCtx(Iter, thunk.inner);
}

pub fn map(iter: anytype, comptime func: anytype) MapFunc(@TypeOf(iter), func) {
    return .{ .iter = iter, .ctx = {} };
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

pub inline fn zip(iters: anytype) Zip(@TypeOf(iters)) {
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

pub fn Fuse(comptime It: type) type {
    const ti = @typeInfo(It.O);
    if (ti != .optional) @compileError("fuse only works with optionals");
    const CO = ti.optional.child;

    return struct {
        iter: It,
        fused: bool = false,

        pub const O = CO;

        pub fn next(self: *@This()) ?CO {
            if (self.fused) return null;
            const val = self.iter.next() orelse {
                self.fused = true;
                return null;
            };
            return val;
        }
    };
}

pub fn fuse(iter: anytype) Fuse(@TypeOf(iter)) {
    return .{ .iter = iter };
}

// // Filter iterator type
// fn Filter(comptime Iter: type, comptime pred: anytype) type {
//     const It = Iterator(Iter);
//
//     return struct {
//         iter: Iter,
//         pub const O = It.O;
//
//         pub fn next(self: *@This()) ?O {
//             while (self.iter.next()) |item| {
//                 if (@call(.always_inline, pred, .{item})) return item;
//             }
//             return null;
//         }
//     };
// }
//
// // Helper function to create a Filter iterator
// pub fn filter(iter: anytype, comptime pred: anytype) Filter(@TypeOf(iter), pred) {
//     return .{ .iter = iter };
// }

fn Filter(comptime Iter: type, comptime pred: anytype) type {
    const thunk = struct {
        fn inner(item: Iterator(Iter).O, _: void) bool {
            return @call(.always_inline, pred, .{item});
        }
    };
    return FilterCtx(Iter, thunk.inner);
}

pub fn filter(iter: anytype, comptime pred: anytype) Filter(@TypeOf(iter), pred) {
    return .{ .iter = iter, .ctx = {} };
}

fn FilterCtx(
    comptime Iter: type,
    comptime pred: anytype,
) type {
    const It = Iterator(Iter);
    const Func = @TypeOf(pred);
    const ti = @typeInfo(Func);
    if (ti != .@"fn") @compileError("pred must be a function type");
    const params = ti.@"fn".params;
    std.debug.assert(params.len == 2);
    // const Input = params[0].type.?;
    const PointerCtx = params[1].type.?;
    const tiPointer = @typeInfo(PointerCtx);
    const Ctx = if (PointerCtx == void) void else if (tiPointer != .pointer) {
        @compileError("ctx must be a pointer");
    } else tiPointer.pointer.child;

    return struct {
        iter: Iter,
        ctx: Ctx,
        pub const O = It.O;

        pub fn next(self: *@This()) ?O {
            std.debug.print("inner caller \n", .{});
            while (self.iter.next()) |item| {
                const ctx_ptr = if (PointerCtx == void) {} else &self.ctx;
                if (pred(item, ctx_ptr)) return item;
            }
            return null;
        }
    };
}

pub fn filterctx(iter: anytype, comptime pred: anytype, ctx: anytype) FilterCtx(@TypeOf(iter), pred) {
    return .{ .iter = iter, .ctx = ctx };
}

pub fn Peekable(comptime Iter: type) type {
    const T = Iterator(Iter).O;
    return struct {
        iter: Iter,
        nextitem: ?T = null,

        pub fn next(self: *@This()) ?T {
            if (self.nextitem) |value| {
                self.nextitem = null;
                return value;
            }
            return self.iter.next();
        }

        pub fn peek(self: *@This()) ?T {
            if (self.nextitem == null) {
                self.nextitem = self.iter.next();
            }
            return self.nextitem;
        }
    };
}

pub fn peekable(iter: anytype) Peekable(@TypeOf(iter)) {
    return .{ .iter = iter };
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
