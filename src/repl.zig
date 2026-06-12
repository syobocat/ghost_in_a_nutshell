// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const Io = std.Io;

const schema = @import("schema");
const State = schema.State;

const core = @import("core");

pub fn main(init: std.process.Init) !void {
    var debug: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug.deinit();
    const allocator = debug.allocator();

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;
    var reader = Io.File.stdin().reader(init.io, &read_buf);
    var writer = Io.File.stdout().writer(init.io, &write_buf);
    const stdin = &reader.interface;
    const stdout = &writer.interface;

    var state: State = try .init(allocator);
    defer state.deinit();
    outer: while (true) {
        var _arena: ArenaAllocator = .init(allocator);
        defer _arena.deinit();
        const arena = _arena.allocator();

        var lines: ArrayList([]const u8) = .empty;
        while (true) {
            const l = try stdin.takeDelimiter('\n');
            const line = l orelse {
                break :outer;
            };
            const line_trimmed = std.mem.trimEnd(u8, line, "\r");
            try lines.append(arena, try arena.dupe(u8, line_trimmed));
            if (line_trimmed.len == 0) {
                break;
            }
        }

        const req = try std.mem.join(arena, "\r\n", lines.items);
        const resp = core.request(arena, req, &state);
        try stdout.writeAll(resp);
        try stdout.flush();
    }
}
