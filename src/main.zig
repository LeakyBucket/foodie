var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    // Dig deeper into what exactly this is doing.  I'm confident that the double "incline" const declarations effectively decompose what the
    // switch expression is returning.  However I'm not sure about the `gpa:` (tagged scope?) bit wrapping the switch and why there is a break
    // there.
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    // Create a new http Client
    var http_client = std.http.Client{ .allocator = allocator };
    defer http_client.deinit();

    // Create an ArrayList to hold the response data.  An ArrayList is a dynamically growable data structure.
    var http_body = std.ArrayList(u8).init(allocator);
    defer http_body.deinit();

    // The URL we want to visit for this test.
    const url = "https://pluralistic.net/feed/";

    _ = try fetch_rss(url, &http_client, &http_body);

    const response_slice = try http_body.toOwnedSlice();

    try save_feed(url, response_slice, allocator);
}

// For some reason the compiler is not happy with the `uri_string` declaration in the head here.  I thought a `[]u8` would work for a string
// of any length but it complains that I am receiving an array with very explicit dimensions (including null termination).
//
// Turns out I was missing the `const` nature of the pointer.  Since it is a string compiled into the binary here the address can't change...
fn fetch_rss(uri_string: []const u8, client: *std.http.Client, response_list: *std.ArrayList(u8)) !std.http.Status {
    const uri = try std.Uri.parse(uri_string);

    const response = try client.fetch(.{ .method = .GET, .location = .{ .uri = uri }, .response_storage = .{ .dynamic = response_list }, .headers = .{ .accept_encoding = .{ .override = "application/rss" } } });

    return response.status;
}

// Write feed response to file.
fn save_feed(uri: []const u8, response: []u8, allocator: std.mem.Allocator) !void {
    // This is a tad bit janky and should be more robust.  However, as long as the URL is well formed then the second item
    // in the `uri_parts` iterator will be empty ("//").
    var uri_parts = std.mem.splitScalar(u8, uri, '/');
    _ = uri_parts.first();
    _ = uri_parts.next();

    const domain = uri_parts.next().?;
    const file_name = try std.mem.concat(allocator, u8, &.{ domain, ".rss" });
    defer allocator.free(file_name);

    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();

    _ = try file.write(response);
}

const std = @import("std");
const builtin = @import("builtin");
