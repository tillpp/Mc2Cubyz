const world = @import("world.zig");

pub fn testMCloader() void{
    var w = world.World.init("/home/uni/.minecraft/saves/Parkour Spiral");
    defer w.deinit();
    w.loadRegionFile() catch return;
}