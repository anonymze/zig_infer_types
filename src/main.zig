const std = @import("std");
const args = @import("./args.zig");
const log = std.log;
const print = std.debug.print;
const fs = std.fs;
const mem = std.mem;

const FileError = error{ Scan, Creation, OutOfMemory };

const IGNORED_DIRECTORIES = [_][]const u8{ "node_modules", ".zig-cache", "zig-out", "test", ".git" };
const BASE_PATH_SCAN = ".";
const START_SCANNER = "// start-infer-types";
const END_SCANNER = "// end-infer-types";
const SCAN_FILE_TYPE = ".svg";

pub fn main() !void {
    // create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const filename = args.getArgumentCommandLine("--filename") catch {
        print("No argument filename found", .{});
        return;
    };

    const directory_to_scan = args.getArgumentCommandLine("--directory") catch {
        print("No argument directory found", .{});
        return;
    };

    var base_dir = fs.cwd().openDir(BASE_PATH_SCAN, .{}) catch {
        print("Error while scanning base directory", .{});
        return;
    };
    defer base_dir.close();

    var file_count: usize = 0;
    var directory_count: usize = 0;

    const file = findFile(alloc, BASE_PATH_SCAN, filename, base_dir, &file_count, &directory_count) catch |err| {
        print("Files scanned : {d}\n", .{file_count});
        print("Directories scanned : {d}\n", .{directory_count});

        switch (err) {
            FileError.Creation => {
                print("Error while creating file", .{});
                return;
            },
            FileError.Scan => {
                print("Error while scanning directories", .{});
                return;
            },
            else => {
                print("System error", .{});
                return;
            },
        }
    };
    defer file.close();

    print("File scanned : {d}\n", .{file_count});
    print("Directory scanned : {d}\n", .{directory_count});

    const filenames = try getFilenamesOfDirectory(alloc, directory_to_scan);
    defer {
        for (filenames.items) |item| {
            alloc.free(item);
        }
        filenames.deinit();
    }

    print("Filenames found : {s}", .{filenames.items});

    try replaceContentFile(alloc, file, filenames);

    return;
}

fn findFile(alloc: mem.Allocator, path: []const u8, filename: []const u8, base_dir: fs.Dir, file_count: *usize, directory_count: *usize) FileError!fs.File {
    // open the directory
    var dir = base_dir.openDir(path, .{ .iterate = true }) catch return FileError.Scan;
    defer dir.close(); // close the directory when we're done

    var directory_iterator = dir.iterate();

    while (directory_iterator.next() catch return FileError.Scan) |entry| {
        if (entry.kind == .file) {
            file_count.* += 1;

            if (mem.eql(u8, filename, entry.name)) {
                return dir.openFile(filename, .{ .mode = .read_write }) catch FileError.Creation;
            }
        }
        if (entry.kind == .directory and !shouldIgnoreDirectory(entry.name)) {
            directory_count.* += 1;

            const new_path = try std.fs.path.join(alloc, &[_][]const u8{ path, entry.name });
            defer alloc.free(new_path);

            // recursively search in subdirectories
            if (findFile(alloc, new_path, filename, base_dir, file_count, directory_count)) |file| {
                return file;
            } else |_| {
                // if we get an error, continue searching other directories
                continue;
            }
        }
    }

    if (mem.eql(u8, path, BASE_PATH_SCAN)) {
        // only create the file if we're in the base directory and haven't found it anywhere
        return base_dir.createFile(filename, .{ .truncate = true }) catch FileError.Creation;
    }

    return FileError.Creation;
}

fn getFilenamesOfDirectory(alloc: mem.Allocator, path: []const u8) !std.ArrayListAligned([]const u8, null) {
    var dir = try fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var dir_itreate = dir.iterate();

    var filenames = std.ArrayList([]const u8).init(alloc);
    errdefer filenames.deinit();

    while (try dir_itreate.next()) |entry| {
        if (entry.kind != .file) continue;
        try filenames.append(try alloc.dupe(u8, entry.name));
    }

    return filenames;
}

fn replaceContentFile(alloc: mem.Allocator, file: fs.File, filenames: ?std.ArrayListAligned([]const u8, null)) !void {
    const content_file = try file.readToEndAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(content_file);

    const ContentResult = struct {
        content: []const u8,
        needs_free: bool,
    };

    const content_between_scanners = blk: {
        if (filenames) |list| {
            const content = try formatContentBetweenScanners(alloc, list);
            break :blk ContentResult{
                .content = content,
                .needs_free = true,
            };
        } else {
            break :blk ContentResult{
                .content =
                \\
                \\type SVGIcons = "test";
                \\
                ,
                .needs_free = false,
            };
        }
    };
    defer if (content_between_scanners.needs_free) alloc.free(content_between_scanners.content);

    const start_index = mem.indexOf(u8, content_file, START_SCANNER) orelse {
        try writeContentEndOfFile(file, content_between_scanners.content);
        return;
    };

    const end_index = mem.indexOf(u8, content_file, END_SCANNER) orelse {
        try writeContentEndOfFile(file, content_between_scanners.content);
        return;
    };

    if (end_index <= start_index) {
        try writeContentEndOfFile(file, content_between_scanners.content);
        return;
    }

    var new_content = std.ArrayList(u8).init(alloc);
    defer new_content.deinit();

    const content_before_scanner = content_file[0 .. start_index + START_SCANNER.len];
    const content_after_scanners = content_file[end_index..];

    try new_content.appendSlice(content_before_scanner);
    try new_content.appendSlice(content_between_scanners.content);
    try new_content.appendSlice(content_after_scanners);

    // position pointer file at the beginning
    try file.seekTo(0);
    try file.writeAll(new_content.items);
    // remove content file after the length of the new_content
    try file.setEndPos(new_content.items.len);
}

fn writeContentEndOfFile(file: fs.File, content: []const u8) !void {
    try file.writeAll(START_SCANNER);
    try file.writeAll(content);
    try file.writeAll(END_SCANNER);
}

fn shouldIgnoreDirectory(name: []const u8) bool {
    for (IGNORED_DIRECTORIES) |ignored| {
        if (mem.eql(u8, ignored, name)) return true;
    }
    return false;
}

fn formatContentBetweenScanners(alloc: mem.Allocator, filenames: std.ArrayListAligned([]const u8, null)) ![]const u8 {
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    const type_svg_icons = "\ntype SVGIcons = ";
    var first_svg_used = false;

    for (filenames.items, 0..) |name, idx| {
        if (idx == 0) try buffer.appendSlice(type_svg_icons);

        if (mem.endsWith(u8, name, SCAN_FILE_TYPE)) {
            if (first_svg_used) try buffer.appendSlice(" | ");
            try buffer.appendSlice("\"");
            try buffer.appendSlice(name[0 .. name.len - 4]);
            try buffer.appendSlice("\"");
            first_svg_used = true;
        }

        if (idx == filenames.items.len - 1) {
            // if we have no svg on the directory we type it to never
            if (buffer.items.len == type_svg_icons.len) try buffer.appendSlice("never");
            try buffer.appendSlice(";\n");
        }
    }

    return buffer.toOwnedSlice();
}
