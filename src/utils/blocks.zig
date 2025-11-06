
pub const Block = packed struct { // MARK: Block
	typ: u16,
	data: u16,

	pub const air = Block{.typ = 0, .data = 0};

	pub fn toInt(self: Block) u32 {
		return @as(u32, self.typ) | @as(u32, self.data) << 16;
	}
	pub fn fromInt(self: u32) Block {
		return Block{.typ = @truncate(self), .data = @intCast(self >> 16)};
	}
	pub fn fromPair(typ: u16,data: u16) Block {
		return Block{.typ = typ, .data = data};
	}
	
};
