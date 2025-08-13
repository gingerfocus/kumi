const ExecList = [*:null]const ?[*:0]const u8;

pub const rcinitcmd: ExecList = &.{"/etc/kumi/bin/init"};
pub const rcrebootcmd: ExecList = &.{ "/etc/kumi/bin/shutdown", "reboot" };
pub const rcpoweroffcmd: ExecList = &.{ "/etc/kumi/bin/shutdown", "poweroff" };
