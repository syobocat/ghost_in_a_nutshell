// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
const Io = std.Io;

const ukadll = @import("ukadll");

const schema = @import("schema");
const State = schema.State;

const core = @import("core");

const root_allocator = std.heap.page_allocator;
var state: State = undefined;

export const loadu = ukadll.load(_loadu);
// export const load = ukadll.load(_load);
export const unload = ukadll.unload(_unload);
export const request = ukadll.request(_request, root_allocator);

fn _loadu(_: []const u8) !void {
    state = try .init(root_allocator);
}

// fn _load(_: []const u8) !void {}

fn _unload() void {
    state.deinit();
}

fn _request(allocator: Allocator, body: []const u8) [:0]const u8 {
    return core.request(allocator, body, &state);
}
