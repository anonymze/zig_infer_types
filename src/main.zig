const std = @import("std");
const args = @import("./args.zig");
const log = std.log;
const print = std.debug.print;
const fs = std.fs;
const mem = std.mem;

const FileError = error{ NotFound, Scan, OutOfMemory };

const IGNORED_DIRECTORIES = [_][]const u8{ "node_modules", ".zig-cache", "zig-out", "test", ".git" };
const BASE_PATH_SCAN = ".";

pub fn main() !void {
    // Create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const filename = args.getArgumentCommandLine("--filename") catch {
        print("No argument found", .{});
        return;
    };

    var file_count: usize = 0;
    var directory_count: usize = 0;

    const file_path = findPathFile(alloc, BASE_PATH_SCAN, filename, &file_count, &directory_count) catch |err| {
        print("File scanned : {d}\n", .{file_count});
        print("Directory scanned : {d}\n", .{directory_count});

        switch (err) {
            FileError.NotFound => {
                print("File not found\n", .{});
                var dir = try fs.cwd().openDir(BASE_PATH_SCAN, .{});
                defer dir.close();

                const file = try dir.createFile(filename, .{ .read = true });
                defer file.close();

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
    defer alloc.free(file_path);

    print("File path : {s}\n", .{file_path});
    print("File scanned : {d}\n", .{file_count});
    print("Directory scanned : {d}\n", .{directory_count});

    return;
}

fn findPathFile(alloc: mem.Allocator, path: []const u8, filename: []const u8, file_count: *usize, directory_count: *usize) FileError![]const u8 {
    // open the directory
    var dir = fs.cwd().openDir(path, .{ .iterate = true }) catch return FileError.Scan;
    defer dir.close(); // close the directory when we're done

    var directory_iterator = dir.iterate();

    while (directory_iterator.next() catch return FileError.Scan) |entry| {
        if (entry.kind == .file) {
            file_count.* += 1;

            if (mem.eql(u8, filename, entry.name)) {
                return try fs.path.join(alloc, &[_][]const u8{ path, entry.name });
            }
        }
        if (entry.kind == .directory and !shouldIgnoreDirectory(entry.name)) {
            directory_count.* += 1;

            const new_path = try std.fs.path.join(alloc, &[_][]const u8{ path, entry.name });
            defer alloc.free(new_path);

            // recursively search in subdirectories
            return findPathFile(alloc, new_path, filename, file_count, directory_count) catch |err| {
                if (err != FileError.NotFound) return err;
                continue;
            };
        }
    }

    return FileError.NotFound;
}

fn shouldIgnoreDirectory(name: []const u8) bool {
    for (IGNORED_DIRECTORIES) |ignored| {
        if (mem.eql(u8, ignored, name)) return true;
    }
    return false;
}
