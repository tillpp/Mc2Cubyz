const std = @import("std");
const Mc2Cubyz = @import("Mc2Cubyz");
const heap = @import("utils/heap.zig");
const zon = @import("utils/zon.zig");
const files = @import("utils/files.zig");
const utils = @import("utils/utils.zig");
const chunk = @import("utils/chunk.zig");
const vec = @import("utils/vec.zig");
const blocks = @import("utils/blocks.zig");
const Block = @import("utils/blocks.zig").Block;
const MCLoader = @import("mc/main.zig");

const c = @cImport({
    @cInclude("zlib.h");
});

pub threadlocal var stackAllocator: heap.NeverFailingAllocator = undefined;
threadlocal var stackAllocatorBase: heap.StackAllocator = undefined;
pub const globalAllocator: heap.NeverFailingAllocator = heap.allocators.handledGpa.allocator();


pub fn initThreadLocals() void {
	stackAllocatorBase = heap.StackAllocator.init(globalAllocator, 1 << 23);
	stackAllocator = stackAllocatorBase.allocator();
    heap.GarbageCollection.addThread();
}

pub fn deinitThreadLocals() void {
	stackAllocatorBase.deinit();
	heap.GarbageCollection.removeThread();
}


pub fn deflate(allocator: heap.NeverFailingAllocator, data: []const u8, level: std.compress.flate.deflate.Level) []u8 {
	var result = main.List(u8).init(allocator);
	var comp = std.compress.flate.compressor(result.writer(), .{.level = level}) catch unreachable;
	_ = comp.write(data) catch unreachable;
	comp.finish() catch unreachable;
	return result.toOwnedSlice();
}
const ChunkCompressionAlgo = enum(u32) {
	deflate_with_position_no_block_entities = 0,
	deflate_no_block_entities = 1,
	uniform = 2,
	deflate_with_8bit_palette_no_block_entities = 3,
	deflate = 4,
	deflate_with_8bit_palette = 5,
};
const BlockEntityCompressionAlgo = enum(u8) {
	raw = 0, // TODO: Maybe we need some basic compression at some point. For now this is good enough though.
};
fn compressBlockData(ch: *chunk.Chunk,writer: *utils.BinaryWriter) void {
	var uncompressedWriter = utils.BinaryWriter.initCapacity(stackAllocator, chunk.chunkVolume*@sizeOf(u32));
	defer uncompressedWriter.deinit();

	for(0..chunk.chunkVolume) |i| {
		uncompressedWriter.writeInt(u32, ch.data.getValue(i).toInt());
		//uncompressedWriter.writeInt(u32, @intCast(i%2));
	}
	const compressedData = utils.Compression.deflate(stackAllocator, uncompressedWriter.data.items, .default);
	defer stackAllocator.free(compressedData);

	writer.writeEnum(ChunkCompressionAlgo, .deflate);
	writer.writeVarInt(usize, compressedData.len);
	writer.writeSlice(compressedData);
}

pub fn compressBlockEntityData(_: *chunk.Chunk,_: *utils.BinaryWriter) void {
	return;
    //if(ch.blockPosToEntityDataMap.count() == 0) return;

	// writer.writeEnum(BlockEntityCompressionAlgo, .raw);

	// var iterator = ch.blockPosToEntityDataMap.iterator();
	// while(iterator.next()) |entry| {
	// const index = entry.key_ptr.*;
	// const blockEntityIndex = entry.value_ptr.*;
	// const block = ch.data.getValue(index);
	// const blockEntity = block.blockEntity() orelse continue;

	// var tempWriter = BinaryWriter.init(stackAllocator);
	// defer tempWriter.deinit();

	// blockEntity.onStoreServerToDisk(blockEntityIndex, &tempWriter);
		
	// if(tempWriter.data.items.len == 0) continue;

	// writer.writeInt(u16, @intCast(index));
	// writer.writeVarInt(usize, tempWriter.data.items.len);
	// writer.writeSlice(tempWriter.data.items);
	// }
}
pub fn ChunkCompressionStoreChunk(allocator: heap.NeverFailingAllocator,ch: *chunk.Chunk) []const u8 {
	var writer = utils.BinaryWriter.init(allocator);
	compressBlockData(ch, &writer);
	compressBlockEntityData(ch,&writer);
	return writer.data.toOwnedSlice();
}


pub fn main() !void {
    defer heap.allocators.deinit();
	defer heap.GarbageCollection.assertAllThreadsStopped();

    utils.initDynamicIntArrayStorage();
    defer utils.deinitDynamicIntArrayStorage();

    initThreadLocals();
    defer deinitThreadLocals();    
    
    chunk.init();
    defer chunk.deinit();
    
    //defer heap.GarbageCollection.debug();
    defer heap.GarbageCollection.syncPoint();
    //defer heap.GarbageCollection.debug();


    MCLoader.testMCloader();
    
    if(true)
        return;


    //files.openDirInWindow("src");
    const palette = try files.cwd().readToZon(stackAllocator, "/home/uni/.cubyz/saves/Save3/palette.zig.zon");
    defer palette.deinit(stackAllocator);
    

    var i:usize = 0;
    while(i < palette.arraySize()){
        const x = palette.getAtIndex([]const u8, i, "");
        i+=1;
        std.debug.print("{s}\n", .{x});

    }
    const chunkPos = chunk.ChunkPosition.initFromWorldPos(vec.Vec3i{0,0,1}, 1);

    var reg = RegionFile.init(chunkPos, "/home/uni/.cubyz/saves/Save3/chunks");
    defer reg.deinit();
    
    const ch = chunk.Chunk.init(chunkPos);
    defer chunk.Chunk.deinit(ch);

    for (0..32) |x| {
        for (0..32) |y| {
            for (0..32) |z| {
                if(y%2 == 0 or x%2 == 0){

                   ch.updateBlock(@intCast(x), @intCast(y), @intCast(z), Block.fromPair(@intCast(x),0));
                }
                else
                    ch.updateBlock(@intCast(x), @intCast(y), @intCast(z), Block.fromPair(0,0));
            }

        }
    }
    const x = ChunkCompressionStoreChunk(stackAllocator,ch);
    defer stackAllocator.free(x);

    reg.storeChunk(x, 0, 0, 0);
    reg.store();
    //gc
    //var file = files.cwd().openFile("test.region") catch return;
    //file.write();
    
    

    //var z = zon.ZonElement.initObject(stackAllocator).put("lol", 5);
    //defer z.deinit(stackAllocator);
    // var file = try std.fs.cwd().createFile("output.json", .{});
    // defer file.close();
    // const json_data =
        // "{\n" ++
        // "    \"name\": \"ArtEm\",\n" ++
        // "    \"age\": 99,\n" ++
        // "    \"languages\": [\"Zig\", \"C\", \"Rust\", \"Go\"]\n" ++
        // "}";
    // try file.writeAll(json_data);
    // std.debug.print("output.json\n", .{});
    // Prints to stderr, ignoring potential errors.
    
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try Mc2Cubyz.bufferedPrint();
}
pub const RegionFile = struct { // MARK: RegionFile
	const version = 0;
	pub const regionShift = 2;
	pub const regionSize = 1 << regionShift;
	pub const regionVolume = 1 << 3*regionShift;

	const headerSize = 8 + regionSize*regionSize*regionSize*@sizeOf(u32);

	chunks: [regionVolume][]u8 = @splat(&.{}),
	pos: chunk.ChunkPosition,
	saveFolder: []const u8,

	pub fn getIndex(x: usize, y: usize, z: usize) usize {
		std.debug.assert(x < regionSize and y < regionSize and z < regionSize);
		return ((x*regionSize) + y)*regionSize + z;
	}
    pub fn init(pos: chunk.ChunkPosition, saveFolder: []const u8) *RegionFile {
		std.debug.assert(pos.wx & (1 << chunk.chunkShift + regionShift) - 1 == 0);
		std.debug.assert(pos.wy & (1 << chunk.chunkShift + regionShift) - 1 == 0);
		std.debug.assert(pos.wz & (1 << chunk.chunkShift + regionShift) - 1 == 0);
		const self = globalAllocator.create(RegionFile);
		self.* = .{
			.pos = pos,
			.saveFolder = globalAllocator.dupe(u8, saveFolder),
		};
		return self;
	}
    pub fn store(self: *RegionFile) void {
        var totalSize: usize = 0;
        for(self.chunks) |ch| {
            totalSize += ch.len;
        }
        if(totalSize > std.math.maxInt(u32)) {
            std.log.err("Size of region file {} is too big to be stored", .{self.pos});
            return;
        }

        var writer = utils.BinaryWriter.initCapacity(stackAllocator, totalSize + headerSize);
        defer writer.deinit();

        writer.writeInt(u32, version);
        writer.writeInt(u32, @intCast(totalSize));

        for(0..regionVolume) |i| {
            writer.writeInt(u32, @intCast(self.chunks[i].len));
        }
        for(0..regionVolume) |i| {
            writer.writeSlice(self.chunks[i]);
        }
        std.debug.assert(writer.data.items.len == totalSize + headerSize);

        const path = std.fmt.allocPrint(stackAllocator.allocator, "{s}/{}/{}/{}/{}.region", .{self.saveFolder, self.pos.voxelSize, self.pos.wx, self.pos.wy, self.pos.wz}) catch unreachable;
        defer stackAllocator.free(path);
        const folder = std.fmt.allocPrint(stackAllocator.allocator, "{s}/{}/{}/{}", .{self.saveFolder, self.pos.voxelSize, self.pos.wx, self.pos.wy}) catch unreachable;
        defer stackAllocator.free(folder);

        std.debug.print("Debug {s}", .{path});
        files.cwd().makePath(folder) catch |err| {
            std.log.err("Error while writing to file {s}: {s}", .{path, @errorName(err)});
        };

        files.cwd().write(path, writer.data.items) catch |err| {
            std.log.err("Error while writing to file {s}: {s}", .{path, @errorName(err)});
        };
    }
    pub fn deinit(self: *RegionFile) void {
		for(self.chunks) |ch| {
			globalAllocator.free(ch);
		}
		globalAllocator.free(self.saveFolder);
		globalAllocator.destroy(self);
	}
    pub fn storeChunk(self: *RegionFile, ch: []const u8, relX: usize, relY: usize, relZ: usize) void {
		const index = getIndex(relX, relY, relZ);
		self.chunks[index] = globalAllocator.realloc(self.chunks[index], ch.len);
		@memcpy(self.chunks[index], ch);
	}
};