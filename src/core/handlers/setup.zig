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

pub fn onBoot(_: Allocator, _: References, state: *State) !Response {
    if (state.data.endpoint == null) {
        return .{
            .status = .ok,
            .value =
            \\\s0はじめまして。\w9初期設定を行います。\w9\nまずは、\w5OpenAI互換APIのURLを入力してください。\w9\![open,inputbox,OnEnterEndpoint,0,https://openrouter.ai/api/v1]\e
            ,
        };
    } else if (state.data.bearer == null) {
        return .{
            .status = .ok,
            .value =
            \\\s0初期設定の続きですね。\w9\nAPIトークンを入力してください。\w9\![open,inputbox,OnEnterToken,0]\e
            ,
        };
    } else if (state.data.model == null) {
        return .{
            .status = .ok,
            .value =
            \\\s0初期設定の続きですね。\w9\n使用するモデルのIDを入力してください。\w9\![open,inputbox,OnEnterModel,0]\e
            ,
        };
    } else if (!state.data.setup_completed) {
        return .{
            .status = .ok,
            .value =
            \\\s0初期設定の続きですね。\w9\n私に初期の人格を与えてください。\w9\nテキストエディタが開きますので、名前やキャラクター設定を記述し、\w5保存してください。\w9\n\n[half]保存が終わったら、\w5OKをクリックしてください。\w9\![open,editor,persona.txt]\n\n\q[OK,OnPersonaSet]\![enter,passivemode]\e
            ,
        };
    } else {
        return .{
            .status = .ok,
            .value =
            \\\s0\![get,property,OnLLMBootTalkRequested,system.year,system.month,system.day,system.hour,system.minute,system.second]\e
            ,
        };
    }
}

pub fn onEnterEndpoint(_: Allocator, references: References, state: *State) !Response {
    const endpoint = references.get(0) orelse {
        return .{ .status = .bad_request };
    };
    state.data.endpoint = try state.global_allocator.dupe(u8, endpoint);
    try state.data.save(state.io, state.global_allocator);
    return .{
        .status = .ok,
        .value =
        \\つぎに、\w5APIトークンを入力してください。\w9\![open,inputbox,OnEnterToken,0]\e
        ,
    };
}

pub fn onEnterToken(_: Allocator, references: References, state: *State) !Response {
    const token = references.get(0) orelse {
        return .{ .status = .bad_request };
    };
    try state.data.setBearer(state.global_allocator, token);
    try state.data.save(state.io, state.global_allocator);
    return .{
        .status = .ok,
        .value =
        \\つぎに、\w5使用するモデルのIDを入力してください。\w9\![open,inputbox,OnEnterModel,0]\e
        ,
    };
}

pub fn onEnterModel(_: Allocator, references: References, state: *State) !Response {
    const model = references.get(0) orelse {
        return .{ .status = .bad_request };
    };
    state.data.model = try state.global_allocator.dupe(u8, model);
    try state.data.save(state.io, state.global_allocator);

    var f = try Io.Dir.cwd().createFile(state.io, "persona.txt", .{});
    f.close(state.io);

    return .{
        .status = .ok,
        .value =
        \\最後に、\w5私に初期の人格を与えてください。\w9\nテキストエディタが開きますので、名前やキャラクター設定を記述し、\w5保存してください。\w9\n\n[half]保存が終わったら、\w5OKをクリックしてください。\w9\![open,editor,persona.txt]\n\n\q[OK,OnPersonaSet]\![enter,passivemode]\e
        ,
    };
}

pub fn onPersonaSet(_: Allocator, _: References, state: *State) !Response {
    state.data.setup_completed = true;
    try state.data.save(state.io, state.global_allocator);

    return .{
        .status = .ok,
        .value =
        \\\![leave,passivemode]\![get,property,OnPersonaSetMain,system.year,system.month,system.day,system.hour,system.minute,system.second]\e
        ,
    };
}

pub fn onUserInputCancel(allocator: Allocator, references: References, _: *State) !Response {
    const id = references.get(0) orelse {
        return .{ .status = .bad_request };
    };
    const msg = try std.fmt.allocPrint(allocator,
        \\\![open,inputbox,{s},0]\e
    , .{id});
    return .{
        .status = .ok,
        .value = msg,
    };
}
