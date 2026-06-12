// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const StaticStringMap = std.StaticStringMap;

const shiori = @import("shiori");
const References = shiori.References;
const Response = shiori.response.Response;

const schema = @import("schema");
const State = schema.State;

const setup = @import("handlers/setup.zig");
const llm = @import("handlers/llm.zig");
const llm_wrapper = @import("handlers/llm_wrapper.zig");
const resource = @import("handlers/resource.zig");

const handlers = StaticStringMap(*const fn (Allocator, References, *State) anyerror!Response).initComptime(.{
    .{ "OnBoot", &setup.onBoot },

    .{ "OnUserInputCancel", &setup.onUserInputCancel },
    .{ "OnEnterEndpoint", &setup.onEnterEndpoint },
    .{ "OnEnterToken", &setup.onEnterToken },
    .{ "OnEnterModel", &setup.onEnterModel },
    .{ "OnPersonaSet", &setup.onPersonaSet },
    .{ "OnPersonaSetMain", &llm.onPersonaSetMain },

    .{ "OnLLMRespond", &llm_wrapper.onLLMRespond },
    .{ "OnLLMRespondMain", &llm.onLLMRespondMain },

    .{ "OnLLMBootTalkRequested", &llm.onLLMBootTalkRequested },
    .{ "OnAITalk", &llm_wrapper.onAITalk },
    .{ "OnLLMRandomTalkRequested", &llm.onLLMRandomTalkRequested },
    .{ "OnSecondChange", &llm_wrapper.onSecondChange },
    .{ "OnLLMRandomTalkTriggered", &llm.onLLMRandomTalkTriggered },
    .{ "OnMouseDoubleClick", &llm_wrapper.onMouseDoubleClick },
    .{ "OnMenuOpen", &llm.onMenuOpen },
    .{ "OnLLMTalkRequested", &llm.onLLMTalkRequested },

    .{ "version", &resource.version },
    .{ "craftman", &resource.craftman },
    .{ "craftmanw", &resource.craftman },
    .{ "name", &resource.name },
});

fn getResponse(allocator: Allocator, body: []const u8, state: *State) Response {
    const req = shiori.request.parse(allocator, body) catch {
        return .{ .status = .bad_request };
    };
    if (req.method == .notify) {
        return .{};
    }
    const handler = handlers.get(req.id) orelse {
        return .{};
    };
    const resp = handler(allocator, req.references, state) catch {
        return .{ .status = .internal_server_error };
    };
    return resp;
}

pub fn request(allocator: Allocator, body: []const u8, state: *State) [:0]const u8 {
    const resp = getResponse(allocator, body, state);
    return resp.render(allocator);
}
