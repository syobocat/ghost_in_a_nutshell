// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;

const build_info = @import("build_info");

const shiori = @import("shiori");
const References = shiori.References;
const Response = shiori.response.Response;

const schema = @import("schema");
const State = schema.State;

pub fn version(_: std.mem.Allocator, _: References, _: *State) !Response {
    return .{
        .status = .ok,
        .value = build_info.version,
    };
}

pub fn craftman(_: std.mem.Allocator, _: References, _: *State) !Response {
    return .{
        .status = .ok,
        .value = "SyoBoN",
    };
}

pub fn name(_: std.mem.Allocator, _: References, _: *State) !Response {
    return .{
        .status = .ok,
        .value = "zSHIORI",
    };
}
