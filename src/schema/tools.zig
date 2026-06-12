// SPDX-FileCopyrightText: 2026 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

pub const ReplaceText = struct {
    old_string: []const u8,
    new_string: []const u8,
    replace_all: bool,
};

pub const AppendKnowledge = struct {
    content: []const u8,
    search_keys: []const []const u8,
};

pub const RemoveKnowledge = struct {
    id: u32,
};

pub const SearchKnowledge = struct {
    query: []const []const u8,
    mode: enum { AND, OR },
};
