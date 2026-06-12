// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayHashMap = std.AutoArrayHashMapUnmanaged;
const ArrayList = std.ArrayList;
const Io = std.Io;

pub const Response = struct {
    script: []const u8,
    summary: []const u8,
};

const KnowledgeContent = struct {
    created_at: []const u8,
    content: []const u8,
    search_keys: []const u8,

    pub fn init(allocator: Allocator, created_at: []const u8, content: []const u8, search_keys: []const []const u8) !@This() {
        return .{
            .created_at = try allocator.dupe(u8, created_at),
            .content = try allocator.dupe(u8, content),
            .search_keys = try std.mem.join(allocator, " ", search_keys),
        };
    }

    pub fn deinit(self: @This(), allocator: Allocator) void {
        allocator.free(self.created_at);
        allocator.free(self.content);
        allocator.free(self.search_keys);
    }
};

const Knowledge = struct {
    id: u32,
    content: KnowledgeContent,
};

const SaveData = struct {
    setup_completed: bool = false,

    endpoint: ?[]const u8 = null,
    token: ?[]const u8 = null,
    model: ?[]const u8 = null,

    context: ?[]const u8 = null,
    persona: ?[]const u8 = null,
    memory: ?[]const u8 = null,
    knowledge: ?[]const Knowledge = null,
    knowledge_id_last: u32 = 0,

    fn load(io: Io, allocator: Allocator) @This() {
        const zon = Io.Dir.cwd().readFileAllocOptions(io, "data.zon", allocator, .unlimited, .@"8", 0) catch return .{};
        defer allocator.free(zon);
        const parsed = std.zon.parse.fromSliceAlloc(@This(), allocator, zon, null, .{}) catch return .{};

        return parsed;
    }

    fn save(self: @This(), io: Io) !void {
        const file = try Io.Dir.cwd().createFile(io, "data.zon", .{});
        var buffer: [4096]u8 = undefined;
        var fwriter = file.writer(io, &buffer);
        const writer = &fwriter.interface;
        try std.zon.stringify.serialize(self, .{ .whitespace = false }, writer);
        try fwriter.end();
    }
};

pub const Data = struct {
    setup_completed: bool = false,

    endpoint: ?[]const u8 = null,
    bearer: ?[]const u8 = null,
    model: ?[]const u8 = null,

    context: ?[]const u8 = null,
    persona: []const u8,
    memory: []const u8,
    knowledge: ArrayHashMap(u32, KnowledgeContent) = .empty,
    knowledge_id_last: u32 = 0,

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.endpoint) |endpoint| {
            allocator.free(endpoint);
        }
        if (self.bearer) |bearer| {
            allocator.free(bearer);
        }
        if (self.model) |model| {
            allocator.free(model);
        }
        if (self.context) |context| {
            allocator.free(context);
        }
        allocator.free(self.persona);
        allocator.free(self.memory);
        var iter = self.knowledge.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.knowledge.deinit(allocator);
    }

    pub fn load(io: Io, allocator: Allocator) !@This() {
        const savedata: SaveData = .load(io, allocator);

        var data: @This() = .{
            .setup_completed = savedata.setup_completed,
            .endpoint = savedata.endpoint,
            .bearer = if (savedata.token) |token| try std.mem.concat(allocator, u8, &.{ "Bearer ", token }) else null,
            .model = savedata.model,
            .context = savedata.context,
            .persona = if (savedata.persona) |persona| persona else try allocator.dupe(u8, @embedFile("templates/blank_persona.md")),
            .memory = if (savedata.memory) |memory| memory else try allocator.dupe(u8, @embedFile("templates/blank_memory.md")),
            .knowledge_id_last = savedata.knowledge_id_last,
        };

        if (savedata.token) |token| {
            allocator.free(token);
        }

        if (savedata.knowledge) |knowledge| {
            for (knowledge) |entry| {
                try data.knowledge.put(allocator, entry.id, entry.content);
            }
        }

        return data;
    }

    pub fn save(self: @This(), io: Io, allocator: Allocator) !void {
        var knowledge: ArrayList(Knowledge) = .empty;
        defer knowledge.deinit(allocator);

        var iter = self.knowledge.iterator();
        while (iter.next()) |entry| {
            try knowledge.append(allocator, .{ .id = entry.key_ptr.*, .content = entry.value_ptr.* });
        }

        const savedata: SaveData = .{
            .setup_completed = self.setup_completed,
            .endpoint = self.endpoint,
            .token = if (self.bearer) |bearer| bearer[7..] else null,
            .model = self.model,
            .context = self.context,
            .persona = self.persona,
            .memory = self.memory,
            .knowledge = knowledge.items,
            .knowledge_id_last = self.knowledge_id_last,
        };

        try savedata.save(io);
    }

    pub fn setBearer(self: *@This(), allocator: Allocator, token: []const u8) !void {
        if (self.bearer) |bearer| {
            allocator.free(bearer);
        }
        self.bearer = try std.mem.concat(allocator, u8, &.{ "Bearer ", token });
    }

    pub fn setPersona(self: *@This(), allocator: Allocator, old: []const u8, new: []const u8, replace_all: bool) !void {
        const new_persona = try replaceText(allocator, self.persona, old, new, replace_all);
        allocator.free(self.persona);
        self.persona = new_persona;
    }

    pub fn setMemory(self: *@This(), allocator: Allocator, old: []const u8, new: []const u8, replace_all: bool) !void {
        const new_memory = try replaceText(allocator, self.memory, old, new, replace_all);
        allocator.free(self.memory);
        self.memory = new_memory;
    }
};

fn replaceText(allocator: Allocator, text: []const u8, old: []const u8, new: []const u8, replace_all: bool) ![]const u8 {
    if (std.mem.eql(u8, old, "*")) {
        return allocator.dupe(u8, new);
    }
    if (std.mem.eql(u8, old, "$")) {
        return std.mem.concat(allocator, u8, &.{ text, new });
    }
    const pos = std.mem.find(u8, text, old) orelse {
        return error.NotFound;
    };
    if (replace_all) {
        return std.mem.replaceOwned(u8, allocator, text, old, new);
    } else {
        return std.mem.concat(allocator, u8, &.{ text[0..pos], new, text[pos + old.len ..] });
    }
}
