// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

pub const ToolCall = struct {
    type: enum { function },
    id: []const u8,
    function: struct {
        name: []const u8,
        arguments: []const u8,
    },
};

pub const Message = struct {
    role: enum { system, user, assistant, tool },
    content: ?[]const u8,
    tool_call_id: ?[]const u8 = null,
    tool_calls: ?[]const ToolCall = null,
};

pub const MessageBuffer = struct {
    arena: ArenaAllocator,
    buffer: ArrayList(Message),

    pub fn init(allocator: Allocator) !@This() {
        return .{
            .arena = .init(allocator),
            .buffer = .empty,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn reset(self: *@This()) void {
        _ = self.arena.reset(.retain_capacity);
        self.buffer = .empty;
    }
};

pub const Response = struct {
    choices: []const struct {
        finish_reason: enum {
            tool_calls,
            stop,
            length,
            content_filter,
            @"error",
        },
        message: struct {
            content: ?[]const u8 = null,
            tool_calls: ?[]const ToolCall = null,
        },
    },
};
