// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const Rng = std.Random.DefaultPrng;

const app = @import("app.zig");
const openai = @import("openai.zig");

_io: *Io.Threaded,

io: Io,
global_allocator: Allocator,
rng: Rng,
timer: u16,
message_buffer: openai.MessageBuffer,
context: Io.Writer.Allocating,
data: app.Data,

pub fn init(allocator: Allocator) !@This() {
    const threaded = try allocator.create(Io.Threaded);
    threaded.* = .init(allocator, .{});
    const io = threaded.io();

    const data: app.Data = try .load(io, allocator);

    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));
    const rng: Rng = .init(seed);

    var self: @This() = .{
        ._io = threaded,
        .io = io,
        .rng = rng,
        .timer = undefined,
        .global_allocator = allocator,
        .message_buffer = try .init(allocator),
        .context = .init(allocator),
        .data = data,
    };

    self.resetTimer();

    return self;
}

pub fn deinit(self: *@This()) void {
    self.data.deinit(self.global_allocator);
    self.context.deinit();
    self.message_buffer.deinit();
    self._io.deinit();
    self.global_allocator.destroy(self._io);
}

pub fn resetTimer(self: *@This()) void {
    const random = self.rng.random();

    // 長めに5〜7分程度に設定
    self.timer = random.intRangeAtMost(u16, 300, 450);
}
