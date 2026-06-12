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

fn extractDateTime(allocator: Allocator, references: References) ![]const u8 {
    const year = references.get(0) orelse return error.BadRequest;
    const month = references.get(1) orelse return error.BadRequest;
    const day = references.get(2) orelse return error.BadRequest;
    const hour = references.get(3) orelse return error.BadRequest;
    const minute = references.get(4) orelse return error.BadRequest;
    const second = references.get(5) orelse return error.BadRequest;

    const datetime = try std.fmt.allocPrint(allocator, "{s}-{s:0>2}-{s:0>2} {s:0>2}:{s:0>2}:{s:0>2}", .{ year, month, day, hour, minute, second });

    return datetime;
}

pub fn onLLMRespondMain(allocator: Allocator, references: References, state: *State) !Response {
    const datetime = extractDateTime(allocator, references) catch |e|
        return if (e == error.BadRequest)
            .{ .status = .bad_request }
        else
            e;
    const script = try request_builder.processResponse(allocator, state, datetime);

    return .{
        .status = .ok,
        .value = script,
    };
}

pub fn onPersonaSetMain(allocator: Allocator, references: References, state: *State) !Response {
    const datetime = extractDateTime(allocator, references) catch |e|
        return if (e == error.BadRequest)
            .{ .status = .bad_request }
        else
            e;
    const persona = try Io.Dir.cwd().readFileAlloc(state.io, "persona.txt", allocator, .unlimited);
    const script = try request_builder.build(allocator, state, datetime,
        \\ユーザーがあなたの初期人格を作成しました。与えられたテキストを元に、ペルソナを更新してください。与えられたテキストに関わらず、ペルソナは一人称視点で記述してください。
        \\完了後、ユーザーに対し初期設定が完了した旨を伝え、最初の挨拶を行ってください。
    , persona);
    try Io.Dir.cwd().deleteFile(state.io, "persona.txt");

    return .{
        .status = .ok,
        .value = script,
    };
}

pub fn onLLMRandomTalkRequested(allocator: Allocator, references: References, state: *State) !Response {
    const datetime = extractDateTime(allocator, references) catch |e|
        return if (e == error.BadRequest)
            .{ .status = .bad_request }
        else
            e;

    const script = try request_builder.build(allocator, state, datetime, "ユーザーからランダムトークを求められました。トークを生成してください。", null);
    return .{
        .status = .ok,
        .value = script,
    };
}

pub fn onLLMRandomTalkTriggered(allocator: Allocator, references: References, state: *State) !Response {
    const datetime = extractDateTime(allocator, references) catch |e|
        return if (e == error.BadRequest)
            .{ .status = .bad_request }
        else
            e;

    const script = try request_builder.build(allocator, state, datetime, "ランダムトークを行います。自発的なトークを生成してください。", null);
    return .{
        .status = .ok,
        .value = script,
    };
}

pub fn onLLMBootTalkRequested(allocator: Allocator, references: References, state: *State) !Response {
    const datetime = extractDateTime(allocator, references) catch |e|
        return if (e == error.BadRequest)
            .{ .status = .bad_request }
        else
            e;

    const script = try request_builder.build(allocator, state, datetime, "起動しました。トークを生成してください。", null);
    return .{
        .status = .ok,
        .value = script,
    };
}

pub fn onMenuOpen(allocator: Allocator, references: References, _: *State) !Response {
    const datetime = extractDateTime(allocator, references) catch |e|
        return if (e == error.BadRequest)
            .{ .status = .bad_request }
        else
            e;

    return .{
        .status = .ok,
        .value = try std.fmt.allocPrint(allocator,
            \\\![quicksection,true]・\q[何か喋って,OnAITalk]\n\n[half]・\q[話しかける,"script:\![open,inputbox,OnLLMTalkRequested,--timeout=0,--reference={s}]"]\n\n\n\n\f[align,right]\q[キャンセル,script:\e]\![quicksection,false]
        , .{datetime}),
    };
}
pub fn onLLMTalkRequested(allocator: Allocator, references: References, state: *State) !Response {
    const input = references.get(0) orelse {
        return .{ .status = .bad_request };
    };
    const datetime = references.get(2) orelse {
        return .{ .status = .bad_request };
    };

    const script = try request_builder.build(allocator, state, datetime, "ユーザーに話しかけられました。返答を生成してください。", input);
    return .{
        .status = .ok,
        .value = script,
    };
}
