const std= @import("std");
const vec = @import("vec.zig");
const utils = @import("utils.zig");
const heap = @import("heap.zig");
const Main = @import("../main.zig");
const blocks = @import("blocks.zig");
const Block = blocks.Block;
const Vec3i = vec.Vec3i;
const Vec3d = vec.Vec3d;


pub const chunkShift: u5 = 5;
pub const chunkShift2: u5 = chunkShift*2;
pub const chunkSize: u31 = 1 << chunkShift;
pub const chunkSizeIterator: [chunkSize]u0 = undefined;
pub const chunkVolume: u31 = 1 << 3*chunkShift;
pub const chunkMask: i32 = chunkSize - 1;

pub const ChunkPosition = struct { // MARK: ChunkPosition
	wx: i32,
	wy: i32,
	wz: i32,
	voxelSize: u31,

	pub fn initFromWorldPos(pos: Vec3i, voxelSize: u31) ChunkPosition {
		const mask = ~@as(i32, voxelSize*chunkSize - 1);
		return .{.wx = pos[0] & mask, .wy = pos[1] & mask, .wz = pos[2] & mask, .voxelSize = voxelSize};
	}

	pub fn hashCode(self: ChunkPosition) u32 {
		const shift: u5 = @truncate(@min(@ctz(self.wx), @ctz(self.wy), @ctz(self.wz)));
		return (((@as(u32, @bitCast(self.wx)) >> shift)*%31 +% (@as(u32, @bitCast(self.wy)) >> shift))*%31 +% (@as(u32, @bitCast(self.wz)) >> shift))*%31 +% self.voxelSize; // TODO: Can I use one of zigs standard hash functions?
	}

	pub fn getMinDistanceSquared(self: ChunkPosition, playerPosition: Vec3i) i64 {
		const halfWidth: i32 = self.voxelSize*@divExact(chunkSize, 2);
		var dx: i64 = @abs(self.wx +% halfWidth -% playerPosition[0]);
		var dy: i64 = @abs(self.wy +% halfWidth -% playerPosition[1]);
		var dz: i64 = @abs(self.wz +% halfWidth -% playerPosition[2]);
		dx = @max(0, dx - halfWidth);
		dy = @max(0, dy - halfWidth);
		dz = @max(0, dz - halfWidth);
		return dx*dx + dy*dy + dz*dz;
	}

	fn getMinDistanceSquaredFloat(self: ChunkPosition, playerPosition: Vec3d) f64 {
		const adjustedPosition = @mod(playerPosition + @as(Vec3d, @splat(1 << 31)), @as(Vec3d, @splat(1 << 32))) - @as(Vec3d, @splat(1 << 31));
		const halfWidth: f64 = @floatFromInt(self.voxelSize*@divExact(chunkSize, 2));
		var dx = @abs(@as(f64, @floatFromInt(self.wx)) + halfWidth - adjustedPosition[0]);
		var dy = @abs(@as(f64, @floatFromInt(self.wy)) + halfWidth - adjustedPosition[1]);
		var dz = @abs(@as(f64, @floatFromInt(self.wz)) + halfWidth - adjustedPosition[2]);
		dx = @max(0, dx - halfWidth);
		dy = @max(0, dy - halfWidth);
		dz = @max(0, dz - halfWidth);
		return dx*dx + dy*dy + dz*dz;
	}

	pub fn getMaxDistanceSquared(self: ChunkPosition, playerPosition: Vec3d) f64 {
		const adjustedPosition = @mod(playerPosition + @as(Vec3d, @splat(1 << 31)), @as(Vec3d, @splat(1 << 32))) - @as(Vec3d, @splat(1 << 31));
		const halfWidth: f64 = @floatFromInt(self.voxelSize*@divExact(chunkSize, 2));
		var dx = @abs(@as(f64, @floatFromInt(self.wx)) + halfWidth - adjustedPosition[0]);
		var dy = @abs(@as(f64, @floatFromInt(self.wy)) + halfWidth - adjustedPosition[1]);
		var dz = @abs(@as(f64, @floatFromInt(self.wz)) + halfWidth - adjustedPosition[2]);
		dx = dx + halfWidth;
		dy = dy + halfWidth;
		dz = dz + halfWidth;
		return dx*dx + dy*dy + dz*dz;
	}

	pub fn getCenterDistanceSquared(self: ChunkPosition, playerPosition: Vec3d) f64 {
		const adjustedPosition = @mod(playerPosition + @as(Vec3d, @splat(1 << 31)), @as(Vec3d, @splat(1 << 32))) - @as(Vec3d, @splat(1 << 31));
		const halfWidth: f64 = @floatFromInt(self.voxelSize*@divExact(chunkSize, 2));
		const dx = @as(f64, @floatFromInt(self.wx)) + halfWidth - adjustedPosition[0];
		const dy = @as(f64, @floatFromInt(self.wy)) + halfWidth - adjustedPosition[1];
		const dz = @as(f64, @floatFromInt(self.wz)) + halfWidth - adjustedPosition[2];
		return dx*dx + dy*dy + dz*dz;
	}

	pub fn getPriority(self: ChunkPosition, playerPos: Vec3d) f32 {
		return -@as(f32, @floatCast(self.getMinDistanceSquaredFloat(playerPos)))/@as(f32, @floatFromInt(self.voxelSize*self.voxelSize)) + 2*@as(f32, @floatFromInt(std.math.log2_int(u31, self.voxelSize)*chunkSize*chunkSize));
	}
};

var memoryPool: heap.MemoryPool(Chunk) = undefined;

pub fn init() void {
	memoryPool = .init(Main.globalAllocator);
}

pub fn deinit() void {
	memoryPool.deinit();
}
/// Gets the index of a given position inside this chunk.
pub fn getIndex(x: i32, y: i32, z: i32) u32 {
	std.debug.assert((x & chunkMask) == x and (y & chunkMask) == y and (z & chunkMask) == z);
	return (@as(u32, @intCast(x)) << chunkShift2) | (@as(u32, @intCast(y)) << chunkShift) | @as(u32, @intCast(z));
}

/// Gets the x coordinate from a given index inside this chunk.
fn extractXFromIndex(index: usize) i32 {
	return @intCast(index >> chunkShift2 & chunkMask);
}
/// Gets the y coordinate from a given index inside this chunk.
fn extractYFromIndex(index: usize) i32 {
	return @intCast(index >> chunkShift & chunkMask);
}
/// Gets the z coordinate from a given index inside this chunk.
fn extractZFromIndex(index: usize) i32 {
	return @intCast(index & chunkMask);
}

pub const Chunk = struct { // MARK: Chunk
	pos: ChunkPosition,
	data: utils.PaletteCompressedRegion(Block, chunkVolume) = undefined,

	width: u31,
	voxelSizeShift: u5,
	voxelSizeMask: i32,
	widthShift: u5,

	pub fn init(pos: ChunkPosition) *Chunk {
		const self = memoryPool.create();
		std.debug.assert((pos.voxelSize - 1 & pos.voxelSize) == 0);
		std.debug.assert(@mod(pos.wx, pos.voxelSize) == 0 and @mod(pos.wy, pos.voxelSize) == 0 and @mod(pos.wz, pos.voxelSize) == 0);
		const voxelSizeShift: u5 = @intCast(std.math.log2_int(u31, pos.voxelSize));
		self.* = Chunk{
			.pos = pos,
			.width = pos.voxelSize*chunkSize,
			.voxelSizeShift = voxelSizeShift,
			.voxelSizeMask = pos.voxelSize - 1,
			.widthShift = voxelSizeShift + chunkShift
		};
		self.data.init();
		return self;
	}

	pub fn deinit(self: *Chunk) void {
		self.deinitContent();
		memoryPool.destroy(@alignCast(self));
	}

	fn deinitContent(self: *Chunk) void {
		self.data.deferredDeinit();
	}


	/// Updates a block if it is inside this chunk.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn updateBlock(self: *Chunk, _x: i32, _y: i32, _z: i32, newBlock: Block) void {
		const x = _x >> self.voxelSizeShift;
		const y = _y >> self.voxelSizeShift;
		const z = _z >> self.voxelSizeShift;
		const index = getIndex(x, y, z);
		self.data.setValue(index, newBlock);
	}

	/// Gets a block if it is inside this chunk.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn getBlock(self: *const Chunk, _x: i32, _y: i32, _z: i32) Block {
		const x = _x >> self.voxelSizeShift;
		const y = _y >> self.voxelSizeShift;
		const z = _z >> self.voxelSizeShift;
		const index = getIndex(x, y, z);
		return self.data.getValue(index);
	}

	/// Checks if the given relative coordinates lie within the bounds of this chunk.
	pub fn liesInChunk(self: *const Chunk, x: i32, y: i32, z: i32) bool {
		return x >= 0 and x < self.width and y >= 0 and y < self.width and z >= 0 and z < self.width;
	}

	pub fn getLocalBlockIndex(self: *const Chunk, worldPos: Vec3i) u32 {
		return getIndex(
			(worldPos[0] - self.pos.wx) >> self.voxelSizeShift,
			(worldPos[1] - self.pos.wy) >> self.voxelSizeShift,
			(worldPos[2] - self.pos.wz) >> self.voxelSizeShift,
		);
	}

	pub fn getGlobalBlockPosFromIndex(self: *const Chunk, index: u16) Vec3i {
		return .{
			(extractXFromIndex(index) << self.voxelSizeShift) + self.pos.wx,
			(extractYFromIndex(index) << self.voxelSizeShift) + self.pos.wy,
			(extractZFromIndex(index) << self.voxelSizeShift) + self.pos.wz,
		};
	}
};