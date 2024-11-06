const std = @import("std");
const args = @import("./args.zig");
const log = std.log;
const print = std.debug.print;
const fs = std.fs;
const mem = std.mem;

const FileError = error{ Scan, Creation, OutOfMemory };

const IGNORED_DIRECTORIES = [_][]const u8{ "node_modules", ".zig-cache", "zig-out", "test", ".git" };
const BASE_PATH_SCAN = ".";

pub fn main() !void {
    // create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const filename = args.getArgumentCommandLine("--filename") catch {
        print("No argument found", .{});
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

    print("File path : {any}\n", .{file});
    print("File scanned : {d}\n", .{file_count});
    print("Directory scanned : {d}\n", .{directory_count});

    return;
}

fn findFile(alloc: mem.Allocator, path: []const u8, filename: []const u8, base_dir: fs.Dir, file_count: *usize, directory_count: *usize) FileError!fs.File {
    // open the directory
    var dir = fs.cwd().openDir(path, .{ .iterate = true }) catch return FileError.Scan;
    defer dir.close(); // close the directory when we're done

    var directory_iterator = dir.iterate();

    while (directory_iterator.next() catch return FileError.Scan) |entry| {
        if (entry.kind == .file) {
            file_count.* += 1;

            if (mem.eql(u8, filename, entry.name)) {
                return dir.openFile(filename, .{}) catch FileError.Creation;
            }
        }
        if (entry.kind == .directory and !shouldIgnoreDirectory(entry.name)) {
            directory_count.* += 1;

            const new_path = try std.fs.path.join(alloc, &[_][]const u8{ path, entry.name });
            defer alloc.free(new_path);

            // recursively search in subdirectories
            return findFile(alloc, new_path, filename, base_dir, file_count, directory_count);
        }
    }

    return base_dir.createFile(filename, .{ .read = true }) catch FileError.Creation;
}

fn shouldIgnoreDirectory(name: []const u8) bool {
    for (IGNORED_DIRECTORIES) |ignored| {
        if (mem.eql(u8, ignored, name)) return true;
    }
    return false;
}
