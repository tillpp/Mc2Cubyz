const std = @import("std");
const files = @import("../utils/files.zig");
const utils = @import("../utils/utils.zig");
const main = @import("../main.zig");
const c = @cImport({
    @cInclude("zlib.h");
});

pub const World = struct{
    folderPath:[]const u8,
    pub fn init(folder:[]const u8) World {
        const world:World = .{
            .folderPath = main.globalAllocator.dupe(u8, folder),
        };
        if(files.cwd().hasDir(folder)){
            std.debug.print("Folder exist\n", .{});
        }
        return world;        
    }
    pub fn loadRegionFile(_:*World)!void{
        const path = "/home/uni/.minecraft/saves/Parkour Spiral/region/r.0.0.mca";
        const data = try files.cwd().read(main.stackAllocator,path);
        defer main.stackAllocator.free(data);
        var reader = utils.BinaryReader.init(data);
        
        var offsets = main.stackAllocator.alloc(u32,32*32);
        defer main.stackAllocator.free(offsets);
        var sizes = main.stackAllocator.alloc(u32,32*32);
        defer main.stackAllocator.free(sizes);
        var timestamps = main.stackAllocator.alloc(u32,32*32);
        defer main.stackAllocator.free(timestamps);


        for (0..32) |x| {
            for (0..32) |z| {
                // u24 big endian, times 4kiB 
                const offset = @as(u32,try reader.readInt(u24))*4096;
                const size = @as(u32,try reader.readInt(u8))*4096;
                
                std.debug.print(">{d}\n", .{offset});
                offsets[x+z*32] = offset;
                sizes  [x+z*32] = size;
                //std.debug.print("{d}:{d} =  {d}\n", .{x,z,offsets[x+z*32]});
            }
        }
        var biggest:u32 = 0;
        for (0..32) |x| {
            for (0..32) |z| {
                const timestamp = try reader.readInt(u32);
                if(biggest<timestamp)
                    biggest = timestamp;
                timestamps[x+z*32] = timestamp;
                //std.debug.print("{d}:{d} =  {d}\n", .{x,z,timestamps[x+z*32]});
            }
        }
        std.debug.print("file last edited: {d}\n", .{biggest});
        std.debug.print("offset: {d}\n", .{offsets[0]});

        //load 0 0 chunk
        var payload = data[offsets[0]..offsets[0]+sizes[0]];
        var chunkReader = utils.BinaryReader.init(payload);
        
        const length = try chunkReader.readInt(u32);
        const compressType = try chunkReader.readInt(u8);
        payload = payload[5..length+4];

        std.debug.print("length {d}\n", .{length});
        std.debug.print("compressType {d}\n", .{compressType});
        std.debug.print("{d}\n", .{payload.len});

        const srcLength :c_ulong = payload.len;
        const destLength:c_ulong = c.compressBound(srcLength);
        const dest = main.stackAllocator.alloc(u8, destLength);
        defer main.stackAllocator.free(dest);
        std.debug.print("until here\n", .{});
        // inflate
        // zlib struct
        var infstream = c.z_stream{
            .avail_in = @as(c_uint,@truncate(srcLength)), // size of input
            .next_in = payload.ptr, // input char array
            .avail_out = @as(c_uint,@truncate(destLength)), // size of output
            .next_out = dest.ptr // output char array
        };

        _ = c.inflateInit(&infstream);
        _ = c.inflate(&infstream, c.Z_NO_FLUSH);
        _ = c.inflateEnd(&infstream);

        //std.debug.print("", .{});
        //_ = c.compress(dest.ptr, &destLength, payload.ptr, srcLength);

        //4 * ((x mod 32) + (z mod 32) * 32)
    }
    pub fn deinit(self:*World) void {
        main.globalAllocator.free(self.folderPath);
    }
};