const std = @import("std");

const sys = std.os.linux;
const mem = std.mem;

const SIG = std.posix.SIG;

var svdir: [*:0]u8 = undefined;

const SvInfo = extern struct {
    dev: std.posix.dev_t,
    ino: std.posix.ino_t,
    pid: std.posix.pid_t = 0,
    isgone: bool = false,
};

pub export var dev: c_ulong = 0;
pub export var ino: c_ulong = 0;

var sv: [1000]SvInfo = std.mem.zeroes([1000]SvInfo);
var svnum: usize = 0;

pub export var check: c_int = 1;
pub export var rplog: [*c]u8 = null;
pub export var rploglen: c_int = @import("std").mem.zeroes(c_int);
pub export var logpipe: [2]c_int = @import("std").mem.zeroes([2]c_int);
// pub export var io: [1]iopause_fd = @import("std").mem.zeroes([1]iopause_fd);
// pub export var stamplog: struct_taia = @import("std").mem.zeroes(struct_taia);
pub export var pgrp: c_int = 0;

const USAGE = "[-P] dir";

fn usage() void {
    std.log.err("usage: {s} " ++ USAGE, .{mem.span(progname)});
    std.posix.exit(1);
}

var exitsoon: c_int = 0;

fn s_term(_: i32) callconv(.C) void {
    exitsoon = 1;
}

fn s_hangup(_: i32) callconv(.C) void {
    exitsoon = 2;
}

fn runsv(srv: *SvInfo, name: []const u8) !void {
    const pid = std.posix.fork() catch {
        // warn(@as([*c]u8, @ptrCast(@volatileCast(@constCast("unable to fork for ")))), name);
        return;
    };

    if (pid == @as(c_int, 0)) {
        // TODO: bad implementation

        // const prog: [2]?[*:0]const u8 = .{ "./start", null };
        // try std.posix.chdir(name);
        //
        // var buf: [256]u8 = undefined;
        // const len = sys.getcwd(&buf, 256);
        // @memcpy(buf[len .. len + 6], "/start");
        // buf[len + 6] = 0;
        //
        // sig_catch(SIG.HUP, SIG.DFL);
        // sig_catch(SIG.TERM, SIG.DFL);
        //
        // if (pgrp != 0) _ = sys.setsid();
        //
        // std.debug.print("file: {s}\n", .{buf});
        //
        // std.log.err("running file: ({s})", .{buf[0 .. len + 6]});
        //
        // // return std.posix.execveZ(@ptrCast(&buf), @ptrCast(&prog), @ptrCast(std.os.environ.ptr));
        // // return std.posix.execveZ(@ptrCast(&buf), @ptrCast(&prog), std.c.environ);
        // return std.posix.execveZ(prog[0].?, @ptrCast(&prog), std.c.environ);

        const prog: [3]?[*:0]const u8 = .{ "runsv", @ptrCast(name.ptr), null };

        sig_catch(SIG.HUP, SIG.DFL);
        sig_catch(SIG.TERM, SIG.DFL);

        if (pgrp != 0) _ = sys.setsid();

        // return std.posix.execvpeZ(prog[0], @ptrCast(&prog), @ptrCast(std.os.environ.ptr));
        return std.posix.execvpeZ(prog[0].?, @ptrCast(&prog), std.c.environ);
    }

    srv.pid = pid;
}

fn runsvdir() !void {
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    // mark all as missing
    var i: usize = 0;
    while (i < svnum) : (i += 1) sv[i].isgone = true;

    var iter = dir.iterate();
    while (try iter.next()) |d| { // iterate through dir entries

        if (d.name[0] == '.') continue; // skip hidden files

        var s: sys.Stat = undefined;
        if (sys.stat(@ptrCast(d.name.ptr), &s) != 0) {
            std.log.warn("unable to stat: {s}", .{d.name});
            continue;
        }

        // TODO: this needs to account for being a symlink to a directory
        if (d.kind != .directory) continue;

        // can also be seen with `s.mode`
        // if (!((s.st_mode & @as(__mode_t, @bitCast(@as(c_int, 61440)))) == @as(__mode_t, @bitCast(@as(c_int, 16384))))) continue;

        // find what service this file coresponds to then run it if it is not
        // already running
        for (sv[0..svnum]) |*srv| {
            if (srv.ino == s.ino and srv.dev == s.dev) {
                srv.isgone = false;

                if (srv.pid == 0) try runsv(srv, d.name);
                break;
            }
        } else {
            // if we dont find anything then we start it
            if (svnum >= @as(c_int, 1000)) {
                // warn3x(@as([*c]u8, @ptrCast(@volatileCast(@constCast("unable to start runsv ")))), @as([*c]u8, @ptrCast(@alignCast(&d.*.d_name))), @as([*c]u8, @ptrCast(@volatileCast(@constCast(": too many services.")))));
                continue;
            }
            sv[svnum] = .{ .ino = s.ino, .dev = s.dev };

            try runsv(&sv[svnum], d.name);

            svnum += 1;

            check = 1;
        }
    }

    i = 0;
    while (i < svnum) {
        if (!sv[i].isgone) {
            i += 1;
            continue;
        }

        if (sv[@as(c_uint, @intCast(i))].pid != 0) {
            std.posix.kill(sv[i].pid, SIG.TERM) catch {};
        }
        svnum -= 1;
        sv[i] = sv[svnum];
        // sv[svnum] = std.mem.zeroes(SvInfo);

        // we dont iterate i here beacuse this assignment requires we check
        // index i again as i can be invalid again if the end of the list was
        // invalid as well
        check = 1;
    }
}

var progname: [*c]u8 = @import("std").mem.zeroes([*c]u8);

fn sig_catch(sig: u6, f: ?*const fn (i32) callconv(.C) void) void {
    const sa = std.posix.Sigaction{
        .handler = .{ .handler = f },
        .flags = 0,
        .mask = std.posix.empty_sigset,
    };

    std.posix.sigaction(sig, &sa, null);
}

pub fn main() !u8 {
    var __u32: u32 = undefined; // unused, never read

    const argv = std.os.argv;
    const argc = argv.len;

    var i: usize = 0;

    var index: usize = 0;

    progname = argv[index];
    index += 1;

    if (index >= argc) usage();

    // parse args
    if (argv[index][0] == '-') {
        switch (argv[index][1]) {
            'P' => {
                pgrp = 1;
                index += 1;
            },
            '-' => index += 1,
            else => {},
        }
        if (index >= argc) usage();
    }

    var mtime: isize = 0;
    var ch: u8 = undefined;
    _ = &ch;

    sig_catch(std.posix.SIG.TERM, &s_term);
    sig_catch(std.posix.SIG.HUP, &s_hangup);

    svdir = argv[index];
    index += 1;

    if (index < argc) {
        // rplog = argv[index];
        // if (setup_log() != @as(c_int, 1)) {
        //     rplog = null;
        //     warn3x(@as([*c]u8, @ptrCast(@volatileCast(@constCast("log service disabled.")))), null, null);
        // }
    }

    const curdir = std.posix.getenv("PWD") orelse unreachable;

    // var deadline: struct_taia = undefined;
    // _ = &deadline;

    var stampcheck = std.time.timestamp();
    var now = stampcheck;

    while (true) {
        // collect childern
        while (true) {
            const pid: isize = @bitCast(sys.waitpid(-1, &__u32, sys.W.NOHANG));
            if (pid <= 0) break; // breaks from the search loop

            // if a program ends after started that is not out problem, the
            // user can restart it if they need that
            i = 0;
            while (i < svnum) : (i += 1) {
                if (pid == sv[i].pid) {
                    sv[i].pid = 0;
                    check = 1;
                    break; // breaks from the iterator
                }
            }
        }

        now = std.time.timestamp();

        if (now < stampcheck - 3) {
            std.log.warn("time warp: resetting time stamp", .{});
            stampcheck = now;

            // if (rplog != null) {
            //     taia_now(&stamplog);
            // }
        }

        // this is a long way of checking file timestamps and if the dir
        // changed then re-ruinng `runsvdir` after changing directories
        if (stampcheck < now) {
            stampcheck = now + 1;

            var s: sys.Stat = undefined;
            if (sys.stat(svdir, &s) == 0) {
                if (check != 0 or s.mtime().sec != mtime or s.ino != ino or s.dev != dev) {
                    try std.posix.chdirZ(svdir);

                    mtime = s.mtime().sec;
                    dev = s.dev;
                    ino = s.ino;
                    check = 0;

                    // std.posix.nanosleep(1, 0);

                    std.debug.print("svdir: {s}\n", .{mem.span(svdir)});
                    try runsvdir();

                    try std.posix.chdirZ(curdir); // TODO: retry after delay
                }
            } else {
                std.log.warn("unable to stat: {s}", .{mem.span(svdir)});
            }
        }

        // if (rplog != null) if (taia_less(&now, &stamplog) == @as(c_int, 0)) {
        //     _ = write(logpipe[@as(c_uint, @intCast(@as(c_int, 1)))], @as(?*const anyopaque, @ptrCast(".")), @as(usize, @bitCast(@as(c_long, @as(c_int, 1)))));
        //     taia_uint(&deadline, @as(c_uint, @bitCast(@as(c_int, 900))));
        //     taia_add(&stamplog, &now, &deadline);
        // };

        // taia_uint(&deadline, @as(c_uint, @bitCast(if (check != 0) @as(c_int, 1) else @as(c_int, 5))));
        // taia_add(&deadline, &now, &deadline);
        // sig_block(sig_child);
        // if (rplog != null) {
        //     iopause(@as([*c]iopause_fd, @ptrCast(@alignCast(&io))), @as(c_uint, @bitCast(@as(c_int, 1))), &deadline, &now);
        // } else {
        //     iopause(null, @as(c_uint, @bitCast(@as(c_int, 0))), &deadline, &now);
        // }
        // sig_unblock(sig_child);
        // if ((rplog != null) and ((@as(c_int, @bitCast(@as(c_int, io[@as(c_uint, @intCast(@as(c_int, 0)))].revents))) | @as(c_int, 1)) != 0)) while (read(logpipe[@as(c_uint, @intCast(@as(c_int, 0)))], @as(?*anyopaque, @ptrCast(&ch)), @as(usize, @bitCast(@as(c_long, @as(c_int, 1))))) > @as(isize, @bitCast(@as(c_long, @as(c_int, 0))))) if (ch != 0) {
        //     {
        //         i = 6;
        //         while (i < rploglen) : (i += 1) {
        //             (blk: {
        //                 const tmp = i - @as(c_int, 1);
        //                 if (tmp >= 0) break :blk rplog + @as(usize, @intCast(tmp)) else break :blk rplog - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        //             }).* = (blk: {
        //                 const tmp = i;
        //                 if (tmp >= 0) break :blk rplog + @as(usize, @intCast(tmp)) else break :blk rplog - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        //             }).*;
        //         }
        //     }
        //     (blk: {
        //         const tmp = rploglen - @as(c_int, 1);
        //         if (tmp >= 0) break :blk rplog + @as(usize, @intCast(tmp)) else break :blk rplog - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
        //     }).* = ch;
        // };

        switch (exitsoon) {
            @as(c_int, 1) => std.posix.exit(0),
            @as(c_int, 2) => {
                for (sv[0..svnum]) |srv| if (srv.pid != 0)
                    std.posix.kill(srv.pid, SIG.TERM) catch {};
                std.posix.exit(111);
            },
            else => {},
        }
    }
    return 0;
}
