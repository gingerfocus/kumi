const ExecList = [*:null]const ?[*:0]const u8;

pub const rcinitcmd: ExecList = &.{"/bin/kumi/init"};
pub const rcrebootcmd: ExecList = &.{ "/bin/kumi/shutdown", "reboot" };
pub const rcpoweroffcmd: ExecList = &.{ "/bin/kumi/shutdown", "poweroff" };
