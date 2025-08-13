const std = @import("std");
const config = @import("config");

const TIMEO = 30;

const sys = std.os.linux;
const log = std.log;
const SIG = sys.SIG;

fn spawn(argv: [*:null]const ?[*:0]const u8, set: *const std.c.sigset_t) i32 {
    switch (sys.fork()) {
        0 => {
            _ = sys.sigprocmask(SIG.UNBLOCK, set, null);
            _ = sys.setsid();
            _ = sys.execve(argv[0].?, argv, &.{null});
            unreachable;
        },
        else => |pid| return @intCast(pid),
    }
}

pub fn main() void {
    if (sys.getpid() != 1) {
        log.err("kumi must be pid 1", .{});
        sys.exit(1);
        return;
    }

    const SECOND = 1_000_000_000;
    var backoff: usize = 1;
    while (backoff <= 32) : (backoff *= 2) {
        if (backoff > 1) {
            log.warn("Init Failed. Retrying after delay of {} seconds...", .{backoff});
            std.time.sleep(backoff * SECOND);
        }

        kumi(); // do the thing
    }

    std.log.err(
        \\ ============= Begin Sinit Abort =============
        \\Failed to start 6 times...
        \\Your system is broken!
        \\  _______________________________________ 
        \\ / Oops! I broke it... sorry 'bout that. \
        \\ \ Here, take this stacktrace. A gift.   /
        \\  ---------------------------------------
        \\        \   ^__^
        \\         \  (oo)\_______
        \\            (__)\       )\/\
        \\                ||----w |
        \\                ||     ||
        \\
    , .{});
    if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
    std.process.abort();
}

fn kumi() void {
    std.posix.chdirZ("/") catch |err| switch (err) {
        // OOM, try again after backoff
        error.SystemResources => return,
        else => unreachable,
    };

    var set = std.mem.zeroes(std.c.sigset_t);
    _ = std.c.sigfillset(&set);
    _ = std.c.sigprocmask(SIG.BLOCK, &set, null);

    var initid = spawn(config.rcinitcmd, &set);

    while (true) {
        _ = std.c.alarm(TIMEO);

        var sig: i32 = 0;
        _ = std.c.sigwait(&set, &sig);

        switch (sig) {
            // poweroff
            SIG.USR1 => _ = spawn(config.rcpoweroffcmd, &set),
            // restart init command
            SIG.USR2 => {
                if (sys.kill(initid, 9) != 0) log.warn("rc was dead before restart", .{});

                // error.ProcessNotFound =>
                initid = spawn(config.rcinitcmd, &set);
            },
            // reap
            SIG.CHLD, SIG.ALRM => {
                // clean up whatever mess is finished
                _ = std.posix.waitpid(-1, std.posix.W.NOHANG);
            },
            // reboot
            SIG.INT => _ = spawn(config.rcrebootcmd, &set),
            else => unreachable,
        }
    }
}
