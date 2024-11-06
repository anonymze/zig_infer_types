const std = @import("std");

const ArgumentError = error{NoArgumentFound};

pub fn getArgumentCommandLine(argument_name: []const u8) ArgumentError![]const u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, argument_name)) {
            if (args.next()) |val| {
                return val;
            }
        }
    }

    return ArgumentError.NoArgumentFound;
}
