const std = @import("std");
const log = std.log;
const print = std.debug.print;
const fs = std.fs;

pub fn main() !void {
    // const alloc = std.heap.page_allocator;

    var iter = (try std.fs.cwd().openDir(
        ".",
        .{ .iterate = true },
    )).iterate();

    var file_count: usize = 0;
    while (try iter.next()) |entry| {
        if (entry.kind == .file) file_count += 1;
        if (entry.kind == .directory) {
            log.info("{s}", .{entry.name});
        }
    }

    log.info("{d}", .{file_count});

    return;
}
