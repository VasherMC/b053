/// BFS bruteforcer for b053

// some pruning is hardcoded
// for example, the bottom-right corner with the rock is unchangeable
// so we use u35 to track tiles instead of u36

const std = @import("std");

const Facing = enum(u2) { U, L, R, D };
const Pos = u6;

/// Least significant to most significant bits
/// (important for bucketing [top 16 bits] / sorting)
/// having tiles as MSB cuts time at depth 38 from 30s->25s (mostly in sorting) compared to having glass as MSB
/// having facing as LSB is important for deduplication while processing
const Board = packed struct(u80) {
    facing: Facing,
    gray: Pos,
    pocket: u2, // empty/stairs/glass/tile
    glass: u35, // set = tile/stairs
    tiles: u35, // set = tile/glass

    fn at(b: Board, p: Pos) u2 {
        if (p > 34) unreachable;
        return @as(u2, @intCast((b.glass >> p) & 1)) | @as(u2, @intCast(((b.tiles >> p) & 1) << 1));
    }

    fn pickup(b: Board, p: Pos, t: u2) Board { // t is non-empty
        if (p > 34) unreachable;
        const remove_mask: u35 = @as(u35, 1) << p;
        return Board{
            .tiles = b.tiles & ~remove_mask,
            .glass = b.glass & ~remove_mask,
            .gray = b.gray,
            .facing = b.facing,
            .pocket = t,
        };
    }

    fn place(b: Board, p: Pos) Board {
        // guaranteed p is empty
        if (p > 34) unreachable;
        //const mask: u35 = @as(u35, 1) << p;
        //const tile_mask = if (b.pocket > 1) mask else 0;
        //const glass_mask = if (b.pocket & 1 == 1) mask else 0;
        const tile_mask = @as(u35, (b.pocket >> 1) & 1) << p;
        const glass_mask = @as(u35, b.pocket & 1) << p;
        return Board{
            .tiles = b.tiles | tile_mask,
            .glass = b.glass | glass_mask,
            .gray = b.gray,
            .facing = b.facing,
            .pocket = 0, // empty
        };
    }
    fn move_to(b: Board, p: Pos, f: Facing) ?Board {
        if (p > 34) unreachable;
        if ((b.tiles >> p) & 1 == 0) return null; // can't move to air/stairs
        // if moving onto glass, remove the glass immediately (reduces bookkeeping?)
        const moving_onto_glass = (b.glass >> p) & 1 == 0;
        const remove_mask: u35 = if (moving_onto_glass) @as(u35, 1) << p else 0;
        return Board{
            .tiles = b.tiles & ~remove_mask,
            .glass = b.glass,
            .gray = p,
            .facing = f,
            .pocket = b.pocket,
        };
    }
    fn unmove_from(b: Board, p: Pos, f: Facing) Board {
        if (p > 34) unreachable;
        // if unmoving from air, unbreak glass there
        const unmoving_from_glass = (b.tiles >> b.gray) & 1 == 0;
        const add_mask: u35 = if (unmoving_from_glass) @as(u35, 1) << b.gray else 0;
        return Board{
            .tiles = b.tiles | add_mask,
            .glass = b.glass,
            .gray = p,
            .facing = f,
            .pocket = b.pocket,
        };
    }
};

const Action = enum(u3) { Z, U, L, R, D };

fn move_by(p: Pos, f: Facing) Pos {
    if (p > 34) unreachable;
    const new_p = switch (f) {
        .U => if (p >= 29) p else p + 6, // p+1 >= 30
        .L => if (p % 6 == 4) p else p + 1, // p+1 % 6 == 5
        .R => if (p % 6 == 5 or p == 0) p else p - 1, // p+1 % 6 == 0
        .D => if (p < 6) p else p - 6, // p+1 < 6 or p==5
    };
    if (new_p > 34) unreachable;
    return new_p;
}

fn do_action(b: Board, a: Action) ?Board {
    // prohibit bumping
    // in this puzzle there's no need to stall; can't move any objects
    // so it doesnt allow changing facing dir in a useful way
    switch (a) {
        .Z => {
            // get the position in front (pickup/place)
            const forward = move_by(b.gray, b.facing);
            if (forward == b.gray) return null; // same tile denotes would bump
            const f_tile = b.at(forward);
            // pickup if our pocket is empty
            // place if it is full
            return switch (b.pocket) {
                0 => if (f_tile == 0) null else b.pickup(forward, f_tile),
                else => if (f_tile != 0) null else b.place(forward),
            };
        },
        else => {
            const new_facing: Facing = switch (a) {
                .U => .U,
                .L => .L,
                .R => .R,
                .D => .D,
                else => unreachable,
            };
            const new_pos = move_by(b.gray, new_facing);
            return if (new_pos == b.gray) null else b.move_to(new_pos, new_facing);
        },
    }
}

fn reverse(b: Board, a: Action) Board {
    switch (a) {
        .Z => { // symmetrical
            const forward = move_by(b.gray, b.facing);
            if (forward == b.gray) unreachable; // same tile denotes would bump
            const f_tile = b.at(forward);
            // pickup if our pocket is empty
            // place if it is full
            return switch (b.pocket) {
                0 => b.pickup(forward, f_tile),
                else => b.place(forward),
            };
        },
        else => {
            const old_facing: Facing = switch (a) {
                .U => .U,
                .L => .L,
                .R => .R,
                .D => .D,
                else => unreachable,
            };
            const back_dir: Facing = switch (b.facing) {
                .U => .D,
                .L => .R,
                .R => .L,
                .D => .U,
            };
            const old_pos = move_by(b.gray, back_dir);
            return b.unmove_from(old_pos, old_facing);
        },
    }
}

const add_tile: u35 = 0b100001_000110_011111_111110_011000_10000;
const eus_tile: u35 = 0b110011_001100_110001_111011_110111_11001;
const bee_tile: u35 = 0b000001_001100_111001_100111_110011_11100;
const tan_tile: u35 = 0b101101_001100_101101_110011_101101_11001;

const eus_tot = @popCount(eus_tile);
const bee_tot = @popCount(bee_tile);
const tan_tot = @popCount(tan_tile);

const start_tiles = 0b111111_111111_111111_111111_111011_11101;
const start_glass = 0b000000_001100_001000_000000_000000_00010;
const b053 = Board{
    .tiles = start_tiles,
    .glass = start_glass,
    .gray = 26,
    .facing = .D,
    .pocket = 0,
};

pub fn main(init: std.process.Init) !void {
    //var gpa = std.heap.DebugAllocator(.{}){};
    const gpa = init.gpa;
    const io = init.io;
    //const alloc = gpa.allocator();
    std.debug.print("{} {}\n\n", .{ @sizeOf(u80), @sizeOf(Board) });
    try run_bfs_partition2(gpa, io);
    // hashmap
    // sortedmerge
    // compress
    // partition
    // partition2
}

// Optimizations:
// - bfs with sortedmerge instead of hashmap  (`sortedmerge`)
// - compress sorted visited/todo streams with xor diff and variable-length encoding (`compress`)
// - partition frontier into buckets to speed up sorting and reduce size ()
// - more aggressive pruning of likely-bad states
// - ignore facing state where it's not important, to more aggressively deduplicate states
// - bucket the todo list (frontier) and visited set as well (partition2)
//    -> compression ratio drops from ~3.3 to ~2.4  (30% saving) in visited set

fn check_solution(b: Board, tilecount: usize) bool {
    var solution = false;
    if (b.tiles == add_tile) {
        std.debug.print("\n\n\n\n\nfound a solution for Add\n", .{});
        solution = true;
    }
    if (b.tiles == eus_tile) {
        std.debug.print("\n\n\n\n\nfound a solution for Eus\n", .{});
        solution = true;
    }
    if (b.tiles == bee_tile) {
        std.debug.print("\n\n\n\n\nfound a solution for Bee\n", .{});
        solution = true;
    }
    if (b.tiles == tan_tile) {
        std.debug.print("\n\n\n\n\nfound a solution for Tan\n", .{});
        solution = true;
    }
    //if ((b.tiles ^ tan_tile) & 0xffff == 0) {
    //    std.debug.print("\n\n\nFound partial solution for bottom half of Tan\n", .{});
    //    solution = true;
    //}
    if (solution) {
        std.debug.print("{}\ntilecount={}  tiles={b}  glass={b:035}\n\n\n\n", .{ b, tilecount, b.tiles, b.glass });
    }
    return solution;
}

/// TODO:
/// merge tiles/glass with PDEP/PEXT? (spread/select with 64-bit 0x33333333)
const itemType = Board;
const compressedStream = struct {
    arr: std.ArrayList(u8),
    len: usize,

    fn init() @This() {
        return .{
            .arr = .empty,
            .len = 0,
        };
    }
    fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.arr.deinit(alloc);
        self.len = 0;
    }
    const Reader = struct {
        stream: *const compressedStream,
        byte_offset: usize,
        state: ?u80,
        fn hasNext(self: *@This()) bool {
            return self.byte_offset < self.stream.*.arr.items.len;
        }
        fn peek(self: *@This()) ?itemType {
            if (self.byte_offset >= self.stream.*.arr.items.len) return null;
            if (self.byte_offset == 0) {
                return @bitCast(std.mem.bytesToValue(u80, self.stream.*.arr.items[0..10]));
            }
            if (self.state == null) unreachable;
            const cmpr_indices = self.stream.*.arr.items[self.byte_offset .. self.byte_offset + 2];
            const diff = std.mem.bytesToValue(u10, cmpr_indices);
            // start at with high order bytes
            var mask: u80 = 0;
            var i: usize = 2;
            for (0..10) |bit_idx| {
                mask <<= 8;
                const bit = (diff >> @as(u4, @intCast(9 - bit_idx))) & 1;
                if (bit == 1) {
                    const byte = self.stream.*.arr.items[self.byte_offset + i];
                    i += 1;
                    mask |= byte;
                }
            }
            return @bitCast(self.state.? ^ mask);
        }
        fn pop(self: *@This()) ?itemType {
            //std.debug.print("pop: offset {} bytes {any}\n", .{ self.byte_offset, self.stream.*.arr.items[self.byte_offset..] });
            if (self.byte_offset >= self.stream.*.arr.items.len) return null;
            if (self.byte_offset == 0) {
                self.state = std.mem.bytesToValue(u80, self.stream.*.arr.items[0..10]);
                self.byte_offset = 10;
                return @bitCast(self.state.?);
            }
            if (self.state == null) unreachable;
            // decompress
            // VPEXPANDB
            const cmpr_indices = self.stream.*.arr.items[self.byte_offset .. self.byte_offset + 2];
            self.byte_offset += 2;
            const diff = std.mem.bytesToValue(u10, cmpr_indices);
            //std.debug.print("pop compressed indices: {b} (bytes: {any})\n", .{ diff, cmpr_indices });
            //std.debug.print("pop compressed indices: reading {} bytes ({} available)\n", .{ @popCount(diff), self.stream.*.arr.items[self.byte_offset..].len });
            // start at with high order bytes
            var mask: u80 = 0;
            for (0..10) |bit_idx| {
                mask <<= 8;
                const bit = (diff >> @as(u4, @intCast(9 - bit_idx))) & 1;
                if (bit == 1) {
                    const byte = self.stream.*.arr.items[self.byte_offset];
                    self.byte_offset += 1;
                    mask |= byte;
                }
            }
            //std.debug.print("pop: xoring state with {b}\n", .{mask});
            self.state = self.state.? ^ mask;
            return @bitCast(self.state.?);
        }
    };
    fn reader(self: *const @This()) Reader {
        return .{ .stream = self, .byte_offset = 0, .state = null };
    }
    fn write(self: *@This(), state: ?u80, b: u80, alloc: std.mem.Allocator) !void {
        self.len += 1;
        if (state == null) {
            const bytes = std.mem.toBytes(b);
            try self.arr.appendSlice(alloc, bytes[0..10]);
            return;
        }
        var diff = state.? ^ b;
        //const orig_diff = diff;
        if (diff == 0) return error.DuplicateWrite;
        // compress
        // Result is big-endian, i.e. first byte must become highest-order in decompressed result
        // ASM: VPCOMPRESSB
        var bytes: [10]u8 = undefined;
        var offset: usize = 10;
        var mask: u10 = 0;
        for (0..10) |bit| {
            const byte: u8 = @intCast(diff & 0xff);
            if (byte != 0) {
                offset -= 1;
                bytes[offset] = byte;
                mask |= @as(u10, 1) << @as(u4, @intCast(bit));
            }
            diff >>= 8;
        }
        //std.debug.assert(diff == 0);
        //std.debug.print("writing: diff {b} {any} encoded-idx {b} {any} compressed-diff {any}\n", .{ orig_diff, std.mem.toBytes(orig_diff)[0..10], mask, std.mem.toBytes(mask), bytes[offset..10] });
        try self.arr.appendSlice(alloc, &std.mem.toBytes(mask));
        try self.arr.appendSlice(alloc, bytes[offset..10]);
    }
    const Writer = struct {
        stream: *compressedStream,
        state: ?u80,
        fn write(self: *@This(), b: Board, alloc: std.mem.Allocator) !void {
            try self.stream.write(self.state, @bitCast(b), alloc);
            self.state = @bitCast(b);
        }
    };
    fn writer(self: *@This()) Writer {
        return .{ .stream = self, .state = null };
    }
};

test "compressedStream" {
    const alloc = std.testing.allocator;
    var stream = compressedStream.init(alloc);
    defer stream.deinit();
    var w = stream.writer();
    var r = stream.reader();
    try std.testing.expect(r.peek() == null);
    var next = try std.ArrayList(Board).initCapacity(alloc, 5);
    defer next.deinit(alloc);

    for (std.enums.values(Action)) |a| {
        if (do_action(b053, a)) |result| {
            next.appendAssumeCapacity(result);
            try w.write(result);
        }
    }
    for (next.items) |item| {
        const pk = r.peek().?;
        const compr = r.pop().?;
        try std.testing.expect(pk == compr);
        std.debug.print("expect: {}\ndecomp: {}\n", .{ item, compr });
        std.debug.print("expect tiles/glass: {b} {b}\ndecomp tiles/glass: {b} {b}\n", .{ item.tiles, item.glass, compr.tiles, compr.glass });
        try std.testing.expect(item == compr);
    }
    try std.testing.expect(!r.hasNext());
}

const compressedStream8 = struct {
    arr: std.ArrayList(u8),
    len: usize,

    const empty: @This() = .{
        .arr = .empty,
        .len = 0,
    };
    fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.arr.deinit(alloc);
        self.len = 0;
    }
    const Reader = struct {
        stream: *const compressedStream8,
        byte_offset: usize,
        state: ?u64,
        next_offset: ?usize,
        fn hasNext(self: *@This()) bool {
            return self.byte_offset < self.stream.*.arr.items.len;
        }
        fn peek(self: *@This()) ?u64 {
            if (self.byte_offset >= self.stream.*.arr.items.len) return null;
            if (self.byte_offset == 0) {
                return std.mem.bytesToValue(u64, self.stream.*.arr.items[0..8]);
            }
            if (self.state == null) unreachable;
            const diff = self.stream.*.arr.items[self.byte_offset];
            // start at with high order bytes
            var mask: u64 = 0;
            var read_offset: usize = self.byte_offset + 1;
            for (0..8) |bit_idx| {
                mask <<= 8;
                const bit = (diff >> @as(u3, @intCast(7 - bit_idx))) & 1;
                if (bit == 1) {
                    const byte = self.stream.*.arr.items[read_offset];
                    read_offset += 1;
                    mask |= byte;
                }
            }
            self.next_offset = read_offset;
            return self.state.? ^ mask;
        }
        fn drop(self: *@This(), state: u64) void {
            if (self.next_offset) |off| {
                self.byte_offset = off;
                self.state = state;
                self.next_offset = null;
            } else {
                _ = self.pop();
            }
        }
        fn pop(self: *@This()) ?u64 {
            //std.debug.print("pop: offset {} bytes {any}\n", .{ self.byte_offset, self.stream.*.arr.items[self.byte_offset..] });
            self.next_offset = null;
            if (self.byte_offset >= self.stream.*.arr.items.len) return null;
            if (self.byte_offset == 0) {
                self.state = std.mem.bytesToValue(u64, self.stream.*.arr.items[0..8]);
                self.byte_offset = 8;
                return self.state.?;
            }
            if (self.state == null) unreachable;
            // decompress
            // VPEXPANDB
            const diff = self.stream.*.arr.items[self.byte_offset];
            self.byte_offset += 1;
            // start at with high order bytes
            var mask: u64 = 0;
            for (0..8) |bit_idx| {
                mask <<= 8;
                const bit = (diff >> @as(u3, @intCast(7 - bit_idx))) & 1;
                if (bit == 1) {
                    const byte = self.stream.*.arr.items[self.byte_offset];
                    self.byte_offset += 1;
                    mask |= byte;
                }
            }
            //std.debug.print("pop: xoring state with {b}\n", .{mask});
            self.state = self.state.? ^ mask;
            return self.state.?;
        }
    };
    fn reader(self: *const @This()) Reader {
        return .{ .stream = self, .byte_offset = 0, .state = null, .next_offset = null };
    }
    fn write(self: *@This(), state: ?u64, b: u64, alloc: std.mem.Allocator) !void {
        self.len += 1;
        if (state == null) {
            const bytes = std.mem.toBytes(b);
            std.debug.assert(bytes.len == 8);
            try self.arr.appendSlice(alloc, bytes[0..8]);
            return;
        }
        var diff = state.? ^ b;
        //const orig_diff = diff;
        if (diff == 0) {
            std.debug.print("duplicate write of u64 value: {b} {}", .{ b, b });
            return error.DuplicateWrite;
        }
        // compress
        // Result is big-endian, i.e. first byte must become highest-order in decompressed result
        // ASM: VPCOMPRESSB
        var bytes: [8]u8 = undefined;
        var offset: usize = 8;
        var mask: u8 = 0;
        for (0..8) |bit| {
            const byte: u8 = @intCast(diff & 0xff);
            if (byte != 0) {
                offset -= 1;
                bytes[offset] = byte;
                mask |= @as(u8, 1) << @as(u3, @intCast(bit));
            }
            diff >>= 8;
        }
        //std.debug.assert(diff == 0);
        //std.debug.print("writing: diff {b} {any} encoded-idx {b} {any} compressed-diff {any}\n", .{ orig_diff, std.mem.toBytes(orig_diff)[0..10], mask, std.mem.toBytes(mask), bytes[offset..10] });
        try self.arr.appendSlice(alloc, &std.mem.toBytes(mask));
        try self.arr.appendSlice(alloc, bytes[offset..8]);
    }
    const Writer = struct {
        stream: *compressedStream8,
        state: ?u64,
        fn write(self: *@This(), b: u64, alloc: std.mem.Allocator) !void {
            try self.stream.write(self.state, b, alloc);
            self.state = b;
        }
    };
    fn writer(self: *@This()) Writer {
        return .{ .stream = self, .state = null };
    }
};

/// Backtrace path through state space given a bucketed set of state-streams and parent-actions
fn trace_path_partitioned(alloc: std.mem.Allocator, seen_streams: []const compressedStream8, parents: []const std.ArrayList(Action), end: Board) !void {
    var b = end;
    var path = try std.ArrayList(Action).initCapacity(alloc, 30);
    while (b != b053) {
        // search for b in the seen list to find the matching action
        const bin: u16 = @intCast(@as(u80, @bitCast(b)) >> 64);
        const val: u64 = @truncate(@as(u80, @bitCast(b)));
        var r = seen_streams[bin].reader();
        var i: usize = 0;
        // just linear search; bins arent expected to be that large
        // and also we don't care that much about time here
        while (r.pop()) |candidate| : (i += 1) {
            if (val == candidate) break;
        }
        const last_action = parents[bin].items[i];
        try path.append(alloc, switch (last_action) {
            .Z => .Z,
            else => switch (b.facing) {
                .U => .U,
                .L => .L,
                .R => .R,
                .D => .D,
            },
        });
        b = reverse(b, last_action);
    }
    for (0..path.items.len) |j| {
        const a = path.items[path.items.len - 1 - j];
        std.debug.print("{c}", .{@as(u8, switch (a) {
            .Z => 'Z',
            .U => 'U',
            .L => 'L',
            .R => 'R',
            .D => 'D',
        })});
    }
    std.debug.print("\n\n", .{});
}

/// Backtrace path through state space given single linear stream of states and parent-actions
fn trace_path(alloc: std.mem.Allocator, seen_stream: compressedStream, parent: []const Action, end: Board) !void {
    // does not have ownerhip of underlying compressedStream
    // build binary search array for reader
    var seen_r = seen_stream.reader();
    var readers = try std.ArrayList(compressedStream.Reader).initCapacity(alloc, (seen_stream.len + 255) / 256);
    var boards = try std.ArrayList(Board).initCapacity(alloc, (seen_stream.len + 255) / 256);
    while (seen_r.hasNext()) {
        try readers.append(alloc, seen_r); // copy
        try boards.append(alloc, seen_r.peek().?); // element i=0 mod 256
        for (0..256) |_| {
            if (seen_r.pop() == null) break;
        }
    }
    // we now have runs of K (256) in each reader
    // do binary search on the array first
    var path = try std.ArrayList(Action).initCapacity(alloc, 30);
    var b = end;
    while (b != b053) {
        // search for b in the seen list
        var i = binarySearch(Board, boards.items, b, boardCmp);
        var temp_r = readers.items[i]; // copy
        i *= 256;
        while (temp_r.pop().? != b) : (i += 1) {} // linear search
        // we now have the full index
        const last_action = parent[i];
        try path.append(alloc, switch (last_action) {
            .Z => .Z,
            else => switch (b.facing) {
                .U => .U,
                .L => .L,
                .R => .R,
                .D => .D,
            },
        });
        b = reverse(b, last_action);
    }
    //var pathstr = std.ArrayList(u8).initCapacity(alloc, path.items.len);
    for (0..path.items.len) |j| {
        const a = path.items[path.items.len - 1 - j];
        std.debug.print("{c}", .{@as(u8, switch (a) {
            .Z => 'Z',
            .U => 'U',
            .L => 'L',
            .R => 'R',
            .D => 'D',
        })});
    }
    std.debug.print("\n\n", .{});
}

fn boardCmp(a: Board, b: Board) std.math.Order {
    const aa: u80 = @bitCast(a);
    const bb: u80 = @bitCast(b);
    return if (aa == bb) .eq else if (aa < bb) .lt else .gt;
}

/// Rather than returning null like std.sort.binarySearch,
/// returns the largest index such that needle =>items[idx]
/// this is where you would insert the needle
fn binarySearch(
    comptime T: type,
    haystack: []const T,
    needle: anytype,
    comptime compareFn: fn (@TypeOf(needle), T) std.math.Order,
) usize {
    var low: usize = 0;
    var high: usize = haystack.len;

    // invariant: needle position < high
    // invariant: needle position >= low
    while (low + 1 < high) {
        // Avoid overflowing in the midpoint calculation
        const mid = low + (high - low) / 2;
        switch (compareFn(needle, haystack[mid])) {
            .eq => return mid,
            .gt => low = mid,
            .lt => high = mid,
        }
    }
    std.debug.assert(low + 1 == high);
    return low;
}

const Timestamp = std.Io.Timestamp;

// at 27 depth: seen 40mil todo 8.8mil items -> seem 37.5ish todo 8.2ish
// Can't just unconditionally set to a specific facing - breaks backtracking
// need to actually deduplicate after sorting
// Results:
// - reduces states stored by approx 6%
// - doesn't noticeably increase total time
fn is_duplicate(pi: usize, a: u64, b: u64, prev_a: Action, prev_b: Action) bool {
    if (a == b) return true;
    if ((a ^ b) > 3) return false;
    // if only facing (low 2 bits) is different, might be able to prune (board+pos+pocket is the same)
    // if neither can Z, we can treat them as equivalent
    if (prev_a == .Z and prev_b == .Z) return true; // can't Z twice in a row
    const ab: Board = @bitCast((@as(u80, @intCast(pi)) << 64) | @as(u80, @intCast(a)));
    const a_fw = move_by(ab.gray, ab.facing);
    const a_tile = ab.at(a_fw);
    const a_can_Z = prev_a != .Z and (a_fw != ab.gray) and ((ab.pocket == 0 and a_tile != 0) or (ab.pocket != 0 and a_tile == 0));
    if (a_can_Z) return false;
    const bb: Board = @bitCast((@as(u80, @intCast(pi)) << 64) | @as(u80, @intCast(a)));
    const b_fw = move_by(bb.gray, bb.facing);
    const b_tile = bb.at(b_fw);
    const b_can_Z = prev_b != .Z and (b_fw != bb.gray) and ((bb.pocket == 0 and b_tile != 0) or (bb.pocket != 0 and b_tile == 0));
    if (b_can_Z) return false;
    return true;
}

// split into function that can be parallelized
fn mergeStream8(alloc: std.mem.Allocator, top: u16, seen: *compressedStream8, todo_out: *compressedStream8, seen_par: *std.ArrayList(Action), pt: std.ArrayList(u64), pr: std.ArrayList(Action), dupes: *usize) !void {
    if (seen.len == 0 and pt.items.len == 0) return; // nop
    var new_stream: compressedStream8 = .empty;
    var seen_r = seen.reader();
    var seen_w = new_stream.writer();
    var new_todo: compressedStream8 = .empty;
    var todo_w = new_todo.writer();
    var out_par: std.ArrayList(Action) = try .initCapacity(alloc, seen_par.items.len);
    //...
    var seen_i: usize = 0;
    var j: usize = 0;
    // merge seen_r stream with pt (new frontier states) stream
    while (seen_r.hasNext() and j < pt.items.len) {
        // clear duplicates from sorted
        while (j + 1 < pt.items.len and is_duplicate(top, pt.items[j], pt.items[j + 1], pr.items[j], pr.items[j + 1])) {
            dupes.* += 1;
            j += 1;
        }
        const seen_r_peek = seen_r.peek().?;
        if (seen_r_peek == pt.items[j]) { // advance both
            seen_r.drop(seen_r_peek);
            try seen_w.write(seen_r_peek, alloc);
            try out_par.append(alloc, seen_par.items[seen_i]);
            seen_i += 1;
            j += 1;
        } else if (seen_r_peek < pt.items[j]) { // advance seen
            seen_r.drop(seen_r_peek);
            try seen_w.write(seen_r_peek, alloc);
            try out_par.append(alloc, seen_par.items[seen_i]);
            seen_i += 1;
        } else { // advance frontier
            try todo_w.write(pt.items[j], alloc);
            try seen_w.write(pt.items[j], alloc);
            try out_par.append(alloc, pr.items[j]);
            j += 1;
        }
    }
    while (seen_r.hasNext()) { // frontier exhausted
        try seen_w.write(seen_r.pop().?, alloc);
        try out_par.append(alloc, seen_par.items[seen_i]);
        seen_i += 1;
    }
    while (j < pt.items.len) { // seen exhausted
        while (j + 1 < pt.items.len and is_duplicate(top, pt.items[j], pt.items[j + 1], pr.items[j], pr.items[j + 1])) {
            dupes.* += 1;
            j += 1;
        }
        try todo_w.write(pt.items[j], alloc);
        try seen_w.write(pt.items[j], alloc);
        try out_par.append(alloc, pr.items[j]);
        j += 1;
    }
    //...
    if (seen.len != 0) {
        seen.deinit(alloc);
        seen_par.deinit(alloc);
    }
    seen.* = new_stream;
    seen_par.* = out_par;
    todo_out.* = new_todo;
}

// Currently active
fn run_bfs_partition2(alloc: std.mem.Allocator, io: std.Io) !void {
    // https://www.snellman.net/blog/archive/2018-07-23-optimizing-breadth-first-search/
    const b053top: u16 = @intCast(@as(u80, @bitCast(b053)) >> 64);
    const b053val: u64 = @truncate(@as(u80, @bitCast(b053)));
    // Invariant: todo contains one depth
    var todo = [_]compressedStream8{.empty} ** 65536;
    try todo[b053top].write(null, b053val, alloc);
    var todo_len: usize = 1;
    // Invariant: seen is sorted by (state)  [ignoring depth]
    var seen = [_]compressedStream8{.empty} ** 65536;
    try seen[b053top].write(null, b053val, alloc);
    var seen_par = [_]std.ArrayList(Action){.empty} ** 65536;
    try seen_par[b053top].append(alloc, .Z);
    var seen_len: usize = 1;
    //
    //var parent = std.ArrayList(Action).init(alloc);
    //try parent.append(.Z);  // ULDR denote previous *facing* direction before move
    for (1..200) |depth| {
        //var insert_duration = 0;
        //TODO:
        const t_start = Timestamp.now(io, .awake);
        std.debug.print("\n\ndepth {}  todo {}\n", .{ depth, todo_len });
        const insert_start = Timestamp.now(io, .awake);
        // frontier parts
        var parts = [_]std.ArrayList(u64){.empty} ** 65536;
        //
        var parents = [_]std.ArrayList(Action){.empty} ** 65536;
        var i: usize = 0;
        for (&todo, 0..65536) |*todo_bucket, top| {
            // can parallelize, but need to synchronize writes
            if (todo_bucket.len == 0) continue;
            var todo_r = todo_bucket.reader();
            while (todo_r.pop()) |low| : (i += 1) {
                if (i % 1000000 == 0) std.debug.print("progress = {}% {}/{} total={}\n", .{ (i * 100) / todo_len, i, todo_len, seen_len + todo_len });
                const b: Board = @bitCast((@as(u80, @intCast(top)) << 64) | @as(u80, @intCast(low)));
                if (b.pocket == 1) {
                    if (check_solution(b, @popCount(b.tiles) + (b.pocket >> 1) + 1)) {
                        //
                        try trace_path_partitioned(alloc, seen[0..], seen_par[0..], b);
                    }
                }
                for (std.enums.values(Action)) |a| {
                    if (do_action(b, a)) |result| {
                        const tilecount = @popCount(result.tiles) + (result.pocket >> 1) + 1;
                        if (tilecount < 22) continue; // not enough tiles left for Tan
                        // rough heuristic that we don't want to walk on these tiles
                        // so we can exclude these states entirely (not even in visited set) to save storage
                        if (result.gray == 0 or result.gray == 3 or result.gray == 4 or result.gray == 5 or result.gray == 10 or result.gray == 11 or result.gray == 16 or result.gray == 34 or result.gray == 29) continue;
                        // can't deduplicate facing here because we dont know which states are possible to backtrack from
                        // Heuristic: we need to fill missing tiles
                        // assume that we need to break at least 1 glass to place each missing tile
                        // - If we have a raft, we need to break glass tiles to place off that row/column
                        // - If we don't have a raft, we also need to break glass tiles to place further
                        // - We also likely need to break glass just to pickup tiles needing to be moved
                        // - So the ideal situation (where we can just move glass from too-full areas to empty areas)
                        //   doesn't really exist (exception for pocket tile, maybe also current-facing
                        // so true required tiles is is higher (though this is heuristic so we leave buffer)
                        // If this is 21 + 1x missing-tiles, search completes in ~2m
                        // dropping down to 21 + 2/3x, takes 16m to complete at depth 169
                        //   -> This means that any successful TAN solution
                        //      would at some point be in a situation where it could fill all remaining gaps
                        //      without breaking as many glass tiles as it is moving
                        if (tilecount < 21 + (2 * @popCount(tan_tile & ~result.tiles) / 3)) continue;
                        // needs to wait until post-sorting
                        const bin: u16 = @intCast(@as(u80, @bitCast(result)) >> 64);
                        const val: u64 = @truncate(@as(u80, @bitCast(result)));
                        try parts[bin].append(alloc, val);
                        //
                        try parents[bin].append(alloc, switch (a) {
                            .Z => .Z,
                            else => switch (b.facing) { // our previous facing
                                .U => .U,
                                .L => .L,
                                .R => .R,
                                .D => .D,
                            },
                        });
                    }
                }
            }
            todo_bucket.deinit(alloc);
        }
        const insert_dur = insert_start.untilNow(io, .awake).toNanoseconds();
        std.debug.print("sorting frontier\n", .{});
        const sort_start = Timestamp.now(io, .awake);
        //for (parts) |p| {
        //    std.sort.pdq(u64, p.items, {}, std.sort.asc(u64));
        //}
        for (parts, parents) |p, pr| {
            // instead of sorting both simultaneously
            // just store vals(actions) in hashmap, sort keys (states), and refill actions
            var m: std.AutoHashMap(u64, Action) = .init(alloc);
            defer m.deinit();
            for (p.items, pr.items) |b, a| {
                try m.put(b, a);
            }
            std.sort.pdq(u64, p.items, {}, std.sort.asc(u64));
            for (p.items, 0..) |b, pi| {
                pr.items[pi] = m.get(b).?;
            }
        }
        const sort_dur = sort_start.untilNow(io, .awake).toNanoseconds();
        // merge sorted next (depth=d) with sorted seen (depth<d)
        std.debug.print("merging\n", .{});
        const merge_start = Timestamp.now(io, .awake);
        seen_len = 0;
        todo_len = 0;
        var dupes: usize = 0;
        var total: usize = 0; // total frontier candidates, before deduplicating
        var seen_bytes: usize = 0;
        var todo_bytes: usize = 0;
        // todo is write-only here
        for (&seen, &todo, &seen_par, &parts, &parents, 0..65536) |*s, *t, *sp, *pt, *pr, top| {
            if (pt.items.len == 0) {
                // nothing to be done
                seen_len += s.len;
                seen_bytes += s.arr.items.len;
                continue;
                //todo_len += 0;
            }
            total += pt.items.len;
            try mergeStream8(alloc, @truncate(top), s, t, sp, pt.*, pr.*, &dupes);
            seen_len += s.len;
            todo_len += t.len;
            seen_bytes += s.arr.items.len;
            todo_bytes += t.arr.items.len;
            pt.deinit(alloc);
            pr.deinit(alloc);
        }
        const merge_dur = merge_start.untilNow(io, .awake).toNanoseconds();

        std.debug.print("done merge (input dupes: {}% | {}/{}), deallocating\n", .{ dupes * 100 / total, dupes, total });
        const t_dur = t_start.untilNow(io, .awake).toNanoseconds();
        std.debug.print("compression stats | seen: ratio {:.3} items {} size {}kb\n", .{
            @as(f64, @floatFromInt(seen_bytes)) / @as(f64, @floatFromInt(seen_len)),
            seen_len,
            seen_bytes / 1024,
        });
        std.debug.print("compression stats | todo: ratio {:.3} items {} size {}kb\n", .{
            @as(f64, @floatFromInt(todo_bytes)) / @as(f64, @floatFromInt(todo_len)),
            todo_len,
            todo_bytes / 1024,
        });
        std.debug.print("timing stats | frontier-gen {}% sort {}% merge {}% total {}ms\n", .{
            @divFloor(insert_dur * 100, t_dur),
            @divFloor(sort_dur * 100, t_dur),
            @divFloor(merge_dur * 100, t_dur),
            @divFloor(t_dur, 1000000),
        });
        if (todo_len == 0) break;
    }
    std.debug.print("finished bruteforcing with full partitioning\n\n", .{});
}

// Currently active
fn run_bfs_partition(alloc: std.mem.Allocator, io: std.Io) !void {
    // https://www.snellman.net/blog/archive/2018-07-23-optimizing-breadth-first-search/
    // Invariant: todo contains one depth
    var todo = compressedStream.init();
    var todow = todo.writer();
    try todow.write(b053, alloc);
    // Invariant: seen is sorted by (state)  [ignoring depth]
    var seen = compressedStream.init();
    var seenw = seen.writer();
    try seenw.write(b053, alloc);
    var seen_par = try std.ArrayList(Action).initCapacity(alloc, 1);
    seen_par.appendAssumeCapacity(.Z);
    //
    //var parent = std.ArrayList(Action).init(alloc);
    //try parent.append(.Z);  // ULDR denote previous *facing* direction before move
    for (1..200) |depth| {
        //var insert_duration = 0;
        //TODO:
        const t_start = Timestamp.now(io, .awake);
        std.debug.print("\n\ndepth {}  todo {}\n", .{ depth, todo.len });
        const insert_start = Timestamp.now(io, .awake);
        // frontier parts
        var parts = [_]std.ArrayList(u64){.empty} ** 65536;
        //
        var parents = [_]std.ArrayList(Action){.empty} ** 65536;
        var i: usize = 0;
        var todo_r = todo.reader();
        while (todo_r.pop()) |b| : (i += 1) {
            if (i % 1000000 == 0) std.debug.print("progress = {}% {}/{} total={}\n", .{ (i * 100) / todo.len, i, todo.len, seen.len + todo.len });
            if (b.pocket == 1) {
                if (check_solution(b, @popCount(b.tiles) + (b.pocket >> 1) + 1)) {
                    //
                    try trace_path(alloc, seen, seen_par.items, b);
                }
            }
            for (std.enums.values(Action)) |a| {
                if (do_action(b, a)) |result| {
                    const tilecount = @popCount(result.tiles) + (result.pocket >> 1) + 1;
                    if (tilecount < 22) continue; // not enough tiles left for Tan
                    // rough heuristic that we don't want to walk on these tiles
                    // so we can exclude these states entirely (not even in visited set) to save storage
                    if (result.gray == 0 or result.gray == 3 or result.gray == 4 or result.gray == 5 or result.gray == 10 or result.gray == 11 or result.gray == 16 or result.gray == 34 or result.gray == 29) continue;
                    // can't deduplicate facing here because we dont know which states are possible to backtrack from
                    // needs to wait until post-sorting
                    const bin: u16 = @intCast(@as(u80, @bitCast(result)) >> 64);
                    const val: u64 = @truncate(@as(u80, @bitCast(result)));
                    try parts[bin].append(alloc, val);
                    //
                    try parents[bin].append(alloc, switch (a) {
                        .Z => .Z,
                        else => switch (b.facing) { // our previous facing
                            .U => .U,
                            .L => .L,
                            .R => .R,
                            .D => .D,
                        },
                    });
                }
            }
        }
        const insert_dur = insert_start.untilNow(io, .awake).toNanoseconds();
        std.debug.print("clearing todo-list\n", .{});
        todo.deinit(alloc);
        std.debug.print("sorting frontier\n", .{});
        const sort_start = Timestamp.now(io, .awake);
        //for (parts) |p| {
        //    std.sort.pdq(u64, p.items, {}, std.sort.asc(u64));
        //}
        for (parts, parents) |p, pr| {
            // instead of sorting both simultaneously
            // just store vals(actions) in hashmap, sort keys (states), and refill actions
            var m: std.AutoHashMap(u64, Action) = .init(alloc);
            defer m.deinit();
            for (p.items, pr.items) |b, a| {
                try m.put(b, a);
            }
            std.sort.pdq(u64, p.items, {}, std.sort.asc(u64));
            for (p.items, 0..) |b, pi| {
                pr.items[pi] = m.get(b).?;
            }
        }
        const sort_dur = sort_start.untilNow(io, .awake).toNanoseconds();
        // merge sorted next (depth=d) with sorted seen (depth<d)
        // only sorted according to boardLessThan func (depth info is forgotten)
        std.debug.print("allocating for merge\n", .{});
        // TODO these should be out-streams?
        var seen_r = seen.reader();
        var out_todo = compressedStream.init();
        var todo_w = out_todo.writer();
        var out_seen = compressedStream.init();
        var seen_w = out_seen.writer();
        var out_par = try std.ArrayList(Action).initCapacity(alloc, seen_par.items.len);
        var seen_i: usize = 0;
        var dupes: usize = 0;
        std.debug.print("merging\n", .{});
        const merge_start = Timestamp.now(io, .awake);
        var total: usize = 0;
        var p_i: usize = 0;
        var p_ii: usize = 0;
        while (p_i < parts.len and parts[p_i].items.len == 0) p_i += 1;
        while (seen_r.hasNext() and p_i < parts.len) {
            // clear duplicates from sorted
            while (p_ii + 1 < parts[p_i].items.len and is_duplicate(p_i, parts[p_i].items[p_ii], parts[p_i].items[p_ii + 1], parents[p_i].items[p_ii], parents[p_i].items[p_ii + 1])) {
                dupes += 1;
                p_ii += 1;
            }
            const next_p: Board = @bitCast((@as(u80, @intCast(p_i)) << 64) | @as(u80, @intCast(parts[p_i].items[p_ii])));
            const seen_r_peek = seen_r.peek().?;
            if (seen_r_peek == next_p) {
                try seen_w.write(seen_r.pop().?, alloc);
                try out_par.append(alloc, seen_par.items[seen_i]);
                seen_i += 1;
                p_ii += 1;
                if (p_ii >= parts[p_i].items.len) {
                    total += p_ii;
                    p_ii = 0;
                    p_i += 1;
                    while (p_i < parts.len and parts[p_i].items.len == 0) p_i += 1;
                }
            } else if (boardLessThan({}, seen_r_peek, next_p)) {
                try seen_w.write(seen_r.pop().?, alloc);
                try out_par.append(alloc, seen_par.items[seen_i]);
                seen_i += 1;
            } else {
                try todo_w.write(next_p, alloc);
                try seen_w.write(next_p, alloc);
                try out_par.append(alloc, parents[p_i].items[p_ii]);
                p_ii += 1;
                if (p_ii >= parts[p_i].items.len) {
                    total += p_ii;
                    p_ii = 0;
                    p_i += 1;
                    while (p_i < parts.len and parts[p_i].items.len == 0) p_i += 1;
                }
            }
        }
        while (seen_r.hasNext()) {
            try seen_w.write(seen_r.pop().?, alloc);
            try out_par.append(alloc, seen_par.items[seen_i]);
            seen_i += 1;
        }
        while (p_i < parts.len) {
            while (p_ii + 1 < parts[p_i].items.len and is_duplicate(p_i, parts[p_i].items[p_ii], parts[p_i].items[p_ii + 1], parents[p_i].items[p_ii], parents[p_i].items[p_ii + 1])) {
                dupes += 1;
                p_ii += 1;
            }
            const next_p: Board = @bitCast((@as(u80, @intCast(p_i)) << 64) | @as(u80, @intCast(parts[p_i].items[p_ii])));
            try todo_w.write(next_p, alloc);
            try seen_w.write(next_p, alloc);
            try out_par.append(alloc, parents[p_i].items[p_ii]);
            p_ii += 1;
            if (p_ii >= parts[p_i].items.len) {
                total += p_ii;
                p_ii = 0;
                p_i += 1;
                while (p_i < parts.len and parts[p_i].items.len == 0) p_i += 1;
            }
        }
        const merge_dur = merge_start.untilNow(io, .awake).toNanoseconds();

        std.debug.print("done merge (input dupes: {}% | {}/{}), deallocating\n", .{ dupes * 100 / total, dupes, total });
        for (parts[0..], parents[0..]) |*p, *pr| {
            p.deinit(alloc);
            pr.deinit(alloc);
        }
        seen.deinit(alloc);
        seen_par.deinit(alloc);
        seen = out_seen;
        todo = out_todo;
        seen_par = out_par;
        const t_dur = t_start.untilNow(io, .awake).toNanoseconds();
        std.debug.print("compression stats | seen: ratio {:.3} items {} size {}kb\n", .{
            @as(f64, @floatFromInt(seen.arr.items.len)) / @as(f64, @floatFromInt(seen.len)),
            seen.len,
            seen.arr.items.len / 1024,
        });
        std.debug.print("compression stats | todo: ratio {:.3} items {} size {}kb\n", .{
            @as(f64, @floatFromInt(todo.arr.items.len)) / @as(f64, @floatFromInt(todo.len)),
            todo.len,
            todo.arr.items.len / 1024,
        });
        std.debug.print("timing stats | frontier-gen {}% sort {}% merge {}% total {}ms\n", .{
            @divFloor(insert_dur * 100, t_dur),
            @divFloor(sort_dur * 100, t_dur),
            @divFloor(merge_dur * 100, t_dur),
            @divFloor(t_dur, 1000000),
        });
    }
    std.debug.print("finished bruteforcing with compression\n", .{});
}

fn boardLessThan(context: void, lhs: Board, rhs: Board) bool {
    _ = context;
    return @as(u80, @bitCast(lhs)) < @as(u80, @bitCast(rhs));
}
