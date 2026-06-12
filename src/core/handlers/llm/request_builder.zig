// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;

const schema = @import("schema");
const State = schema.State;
const OpenAIResponse = schema.openai.Response;
const AppResponse = schema.app.Response;
const ReplaceText = schema.tools.ReplaceText;
const AppendKnowledge = schema.tools.AppendKnowledge;
const RemoveKnowledge = schema.tools.RemoveKnowledge;
const SearchKnowledge = schema.tools.SearchKnowledge;

const SYSTEM_PROMPT_TEMPLATE = @embedFile("templates/system_prompt.md");

const RESPONSE_FORMAT = @import("templates/response_format.zon");
const TOOLS = @import("templates/tools.zon");
const WORDS: []const []const u8 = @import("templates/words.zon");

const Knowledge = struct {
    id: u32,
    created_at: []const u8,
    content: []const u8,
};

const ToolTag = enum {
    update_persona,
    update_memory,
    append_knowledge,
    remove_knowledge,
    search_knowledge,
    get_word,
};

// TODO: 128KBで足りる気がするので、--nofileにしてもいいかも？

pub fn build(
    arena: Allocator,
    state: *State,
    datetime: []const u8,
    task: []const u8,
    user_input: ?[]const u8,
) ![]const u8 {
    const endpoint = state.data.endpoint orelse return error.NotReady;
    const bearer = state.data.bearer orelse return error.NotReady;
    const model = state.data.model orelse return error.NotReady;

    const persona = state.data.persona;
    const memory = state.data.memory;
    const context = if (state.context.written().len > 0)
        state.context.written()
    else
        state.data.context orelse "";

    state.message_buffer.reset();
    const message_buffer = &state.message_buffer.buffer;
    const buffer_allocator = state.message_buffer.arena.allocator();

    const system_prompt = try std.mem.concat(buffer_allocator, u8, &.{
        SYSTEM_PROMPT_TEMPLATE,
        "\n<persona>\n",
        persona,
        "\n</persona>\n\n<memory>\n",
        memory,
        "\n</memory>",
    });

    const msg_obj = .{
        .datetime = datetime,
        .context = context,
        .task = task,
        .input = user_input,
    };

    const msg = try std.json.Stringify.valueAlloc(buffer_allocator, msg_obj, .{});

    try message_buffer.append(buffer_allocator, .{
        .role = .system,
        .content = system_prompt,
    });
    try message_buffer.append(buffer_allocator, .{
        .role = .user,
        .content = msg,
    });

    const req = .{
        .model = model,
        .temperature = 1.0,
        .reasoning = .{
            .effort = "high",
        },
        .messages = message_buffer.items,
        .response_format = RESPONSE_FORMAT,
        .tools = TOOLS,
    };

    var buffer: [4096]u8 = undefined;
    const f = try Io.Dir.cwd().createFile(state.io, "request.json", .{});
    defer f.close(state.io);
    var fwriter = f.writer(state.io, &buffer);
    const writer = &fwriter.interface;

    try std.json.Stringify.value(req, .{ .emit_null_optional_fields = false }, writer);
    try fwriter.end();

    const script = std.fmt.allocPrint(arena,
        \\\![quicksection,true]Generating...\![quicksection,false]\![execute,http-post,{s}/chat/completions,--sync=OnLLMRespond,--authorization={s},--file=response.json,--param-input-file=request.json,--timeout=30]\e
    , .{ endpoint, bearer });

    return script;
}

pub fn processResponse(arena: Allocator, state: *State, datetime: []const u8) ![]const u8 {
    const endpoint = state.data.endpoint.?;
    const bearer = state.data.bearer.?;
    const model = state.data.model.?;

    const message_buffer = &state.message_buffer.buffer;
    const buffer_allocator = state.message_buffer.arena.allocator();

    const response_raw = try Io.Dir.cwd().readFileAlloc(state.io, "var/response.json", buffer_allocator, .unlimited);
    const response = try std.json.parseFromSliceLeaky(OpenAIResponse, buffer_allocator, response_raw, .{ .ignore_unknown_fields = true });
    const choice = response.choices[0];
    const message = choice.message;

    try message_buffer.append(buffer_allocator, .{
        .role = .assistant,
        .content = message.content,
        .tool_calls = message.tool_calls,
    });

    if (message.tool_calls) |tool_calls| {
        for (tool_calls) |tool_call| {
            const tool_tag = std.meta.stringToEnum(ToolTag, tool_call.function.name) orelse {
                try message_buffer.append(buffer_allocator, .{
                    .role = .tool,
                    .tool_call_id = tool_call.id,
                    .content = try std.fmt.allocPrint(buffer_allocator,
                        \\{{"error":"No such tool: {s}"}}
                    , .{tool_call.function.name}),
                });
                continue;
            };

            switch (tool_tag) {
                .update_persona => {
                    const args = std.json.parseFromSliceLeaky(ReplaceText, buffer_allocator, tool_call.function.arguments, .{}) catch |e| {
                        if (e == error.OutOfMemory) {
                            return e;
                        } else {
                            try message_buffer.append(buffer_allocator, .{
                                .role = .tool,
                                .tool_call_id = tool_call.id,
                                .content =
                                \\{"error":"Malformed arguments"}
                                ,
                            });
                            continue;
                        }
                    };
                    state.data.setPersona(state.global_allocator, args.old_string, args.new_string, args.replace_all) catch |e| {
                        if (e == error.NotFound) {
                            try message_buffer.append(buffer_allocator, .{
                                .role = .tool,
                                .tool_call_id = tool_call.id,
                                .content =
                                \\{"error":"Pattern not found"}
                                ,
                            });
                            continue;
                        } else {
                            return e;
                        }
                    };

                    try message_buffer.append(buffer_allocator, .{
                        .role = .tool,
                        .tool_call_id = tool_call.id,
                        .content =
                        \\{"status":"ok"}
                        ,
                    });
                },
                .update_memory => {
                    const args = std.json.parseFromSliceLeaky(ReplaceText, buffer_allocator, tool_call.function.arguments, .{}) catch |e| {
                        if (e == error.OutOfMemory) {
                            return e;
                        } else {
                            try message_buffer.append(buffer_allocator, .{
                                .role = .tool,
                                .tool_call_id = tool_call.id,
                                .content =
                                \\{"error":"Malformed arguments"}
                                ,
                            });
                            continue;
                        }
                    };
                    state.data.setMemory(state.global_allocator, args.old_string, args.new_string, args.replace_all) catch |e| {
                        if (e == error.NotFound) {
                            try message_buffer.append(buffer_allocator, .{
                                .role = .tool,
                                .tool_call_id = tool_call.id,
                                .content =
                                \\{"error":"Pattern not found"}
                                ,
                            });
                            continue;
                        } else {
                            return e;
                        }
                    };

                    try message_buffer.append(buffer_allocator, .{
                        .role = .tool,
                        .tool_call_id = tool_call.id,
                        .content =
                        \\{"status":"ok"}
                        ,
                    });
                },
                .append_knowledge => {
                    const args = std.json.parseFromSliceLeaky(AppendKnowledge, buffer_allocator, tool_call.function.arguments, .{}) catch |e| {
                        if (e == error.OutOfMemory) {
                            return e;
                        } else {
                            try message_buffer.append(buffer_allocator, .{
                                .role = .tool,
                                .tool_call_id = tool_call.id,
                                .content =
                                \\{"error":"Malformed arguments"}
                                ,
                            });
                            continue;
                        }
                    };

                    const id = state.data.knowledge_id_last + 1;
                    try state.data.knowledge.put(state.global_allocator, id, try .init(state.global_allocator, datetime, args.content, args.search_keys));
                    state.data.knowledge_id_last = id;

                    try message_buffer.append(buffer_allocator, .{
                        .role = .tool,
                        .tool_call_id = tool_call.id,
                        .content =
                        \\{"status":"ok"}
                        ,
                    });
                },
                .remove_knowledge => {
                    const args = std.json.parseFromSliceLeaky(RemoveKnowledge, buffer_allocator, tool_call.function.arguments, .{}) catch |e| {
                        if (e == error.OutOfMemory) {
                            return e;
                        } else {
                            try message_buffer.append(buffer_allocator, .{
                                .role = .tool,
                                .tool_call_id = tool_call.id,
                                .content =
                                \\{"error":"Malformed arguments"}
                                ,
                            });
                            continue;
                        }
                    };

                    const target = state.data.knowledge.get(args.id) orelse {
                        try message_buffer.append(buffer_allocator, .{
                            .role = .tool,
                            .tool_call_id = tool_call.id,
                            .content = try std.fmt.allocPrint(buffer_allocator,
                                \\{{"error":"Knowledge with the id {d} does not exist"}}
                            , .{args.id}),
                        });
                        continue;
                    };
                    target.deinit(state.global_allocator);

                    _ = state.data.knowledge.orderedRemove(args.id);

                    try message_buffer.append(buffer_allocator, .{
                        .role = .tool,
                        .tool_call_id = tool_call.id,
                        .content =
                        \\{"status":"ok"}
                        ,
                    });
                },
                .search_knowledge => {
                    const args = std.json.parseFromSliceLeaky(SearchKnowledge, buffer_allocator, tool_call.function.arguments, .{}) catch |e| {
                        if (e == error.OutOfMemory) {
                            return e;
                        } else {
                            try message_buffer.append(buffer_allocator, .{
                                .role = .tool,
                                .tool_call_id = tool_call.id,
                                .content =
                                \\{"error":"Malformed arguments"}
                                ,
                            });
                            continue;
                        }
                    };

                    var results: ArrayList(Knowledge) = .empty;
                    var iter = state.data.knowledge.iterator();
                    while (iter.next()) |knowledge| {
                        switch (args.mode) {
                            .AND => {
                                for (args.query) |word| {
                                    if (!std.mem.containsAtLeast(u8, knowledge.value_ptr.content, 1, word) and !std.mem.containsAtLeast(u8, knowledge.value_ptr.search_keys, 1, word)) {
                                        break;
                                    }
                                } else {
                                    try results.append(buffer_allocator, .{
                                        .id = knowledge.key_ptr.*,
                                        .created_at = knowledge.value_ptr.created_at,
                                        .content = knowledge.value_ptr.content,
                                    });
                                }
                            },
                            .OR => {
                                for (args.query) |word| {
                                    if (std.mem.containsAtLeast(u8, knowledge.value_ptr.content, 1, word) or std.mem.containsAtLeast(u8, knowledge.value_ptr.search_keys, 1, word)) {
                                        try results.append(buffer_allocator, .{
                                            .id = knowledge.key_ptr.*,
                                            .created_at = knowledge.value_ptr.created_at,
                                            .content = knowledge.value_ptr.content,
                                        });
                                        break;
                                    }
                                }
                            },
                        }
                    }

                    if (results.items.len == 0) {
                        try message_buffer.append(buffer_allocator, .{
                            .role = .tool,
                            .tool_call_id = tool_call.id,
                            .content =
                            \\{"status":"not found"}
                            ,
                        });
                        break;
                    }

                    const tool_response = .{
                        .status = "ok",
                        .results = results.items,
                    };

                    try message_buffer.append(buffer_allocator, .{
                        .role = .tool,
                        .tool_call_id = tool_call.id,
                        .content = try std.json.Stringify.valueAlloc(buffer_allocator, tool_response, .{}),
                    });
                },
                .get_word => {
                    const random = state.rng.random();
                    const idx = random.uintLessThan(usize, WORDS.len);
                    const word = WORDS[idx];

                    try message_buffer.append(buffer_allocator, .{
                        .role = .tool,
                        .tool_call_id = tool_call.id,
                        .content = try std.fmt.allocPrint(buffer_allocator,
                            \\{{"word":"{s}"}}
                        , .{word}),
                    });
                },
            }
        }

        const req = .{
            .model = model,
            .temperature = 1.0,
            .reasoning = .{
                .effort = "high",
            },
            .messages = message_buffer.items,
            .response_format = RESPONSE_FORMAT,
            .tools = TOOLS,
        };

        var buffer: [4096]u8 = undefined;
        const f = try Io.Dir.cwd().createFile(state.io, "request.json", .{});
        defer f.close(state.io);
        var fwriter = f.writer(state.io, &buffer);
        const writer = &fwriter.interface;

        try std.json.Stringify.value(req, .{ .emit_null_optional_fields = false }, writer);
        try fwriter.end();

        const script = std.fmt.allocPrint(arena,
            \\\![quicksection,true]Generating...\![quicksection,false]\![execute,http-post,{s}/chat/completions,--sync=OnLLMRespond,--authorization={s},--file=response.json,--param-input-file=request.json,--timeout=30]\e
        , .{ endpoint, bearer });

        return script;
    } else {
        const resp = try std.json.parseFromSliceLeaky(AppResponse, arena, message.content.?, .{});

        const writer = &state.context.writer;
        try writer.print("{s} {s}\n", .{ datetime, resp.summary });

        state.data.context = try std.fmt.allocPrint(state.global_allocator, "{s} {s}", .{ datetime, resp.summary });
        try state.data.save(state.io, state.global_allocator);

        // Cleanup
        try Io.Dir.cwd().deleteFile(state.io, "request.json");
        try Io.Dir.cwd().deleteFile(state.io, "var/response.json");

        const script = postprocess(arena, resp.script);
        return script;
    }
}

// 改行とウェイトはLLMに任せるより強制した方が楽
fn postprocess(allocator: Allocator, text: []const u8) ![]const u8 {
    // allocatorはArenaAllocatorのはずなのでfree()しても無意味
    const text1 = try std.mem.replaceOwned(u8, allocator, text, "\n\n", "\\n\\n[half]");
    const text2 = try std.mem.replaceOwned(u8, allocator, text1, "\n", "\\n");
    const text3 = try std.mem.replaceOwned(u8, allocator, text2, "、", "、\\w5");
    const text4 = try std.mem.replaceOwned(u8, allocator, text3, "。", "。\\w9");
    const text5 = try std.mem.replaceOwned(u8, allocator, text4, "！", "！\\w9");
    const text6 = try std.mem.replaceOwned(u8, allocator, text5, "？", "？\\w9");
    return text6;
}
