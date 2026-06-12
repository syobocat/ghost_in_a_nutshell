// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const shiori = @import("shiori");
const References = shiori.References;
const Response = shiori.response.Response;

const schema = @import("schema");
const State = schema.State;

const request_builder = @import("llm/request_builder.zig");

pub fn onLLMRespond(_: Allocator, _: References, _: *State) !Response {
    return .{
        .status = .ok,
        .value =
        \\\![get,property,OnLLMRespondMain,system.year,system.month,system.day,system.hour,system.minute,system.second]\e
        ,
    };
}

pub fn onAITalk(_: Allocator, _: References, state: *State) !Response {
    // 準備できていないときはやらない
    if (!state.data.setup_completed) {
        return .{};
    }

    return .{
        .status = .ok,
        .value =
        \\\![get,property,OnLLMRandomTalkRequested,system.year,system.month,system.day,system.hour,system.minute,system.second]\e
        ,
    };
}

pub fn onSecondChange(_: Allocator, references: References, state: *State) !Response {
    // 準備できていないときはやらない
    if (!state.data.setup_completed) {
        return .{};
    }

    // Reference3が0のときはトーク再生不可なので無視
    // NOTIFYになるのでそもそも無視されるはずだけど念のためチェック
    const ref3 = references.get(3) orelse return .{ .status = .bad_request };
    if (std.mem.eql(u8, ref3, "0")) {
        return .{};
    }

    state.timer -= 1;

    if (state.timer == 0) {
        state.resetTimer();
        return .{
            .status = .ok,
            .value =
            \\\![get,property,OnLLMRandomTalkTriggered,system.year,system.month,system.day,system.hour,system.minute,system.second]\e
            ,
        };
    }

    return .{};
}

pub fn onMouseDoubleClick(_: Allocator, _: References, _: *State) !Response {
    return .{
        .status = .ok,
        .value =
        \\\![get,property,OnMenuOpen,system.year,system.month,system.day,system.hour,system.minute,system.second]\e
        ,
    };
}
