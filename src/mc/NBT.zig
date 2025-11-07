const std = @import("std");
const files = @import("../utils/files.zig");
const utils = @import("../utils/utils.zig");
const main = @import("../main.zig");

const TagType = enum(u8) {
    END = 0,
    BYTE = 1,
    SHORT = 2,
    INT = 3,
    LONG = 4,
    FLOAT = 5,
    DOUBLE = 6,
    BYTE_ARRAY = 7,
    STRING = 8,
    LIST = 9,
    COMPOUND = 10,
    INT_ARRAY = 11,
    LONG_ARRAY = 12,
};
const Value = union{
    byte:i8,
    short:i16,
    int:i32,
    long:i64,
    float:f32,
    double:f64
};
const NBTError = error {OutOfBounds,IntOutOfBounds,InvalidFloat,OutOfMemory};
pub const NBT = struct{
    name:?[]const u8 =null,//name
    tagType:TagType,
    value:Value = Value{.byte = 0},
    bytes:?[]const u8=null, //byteArray,string
    int_array:?[]const i32=null ,
    long_array:?[]const i64=null,
    array:?[]NBT=null,
    map:?std.StringHashMap(NBT)=null,
    pub fn init(data:[]const u8)!NBT{
        var reader = utils.BinaryReader.init(data);
        
        return loadNBT(&reader);
        
    }
    pub fn loadNBT(reader:*utils.BinaryReader) NBTError!NBT {
        const typ:TagType = @enumFromInt(reader.readInt(u8) catch @panic("hier"));
    
        var name:?[]const u8 = null;    
        if(typ!=TagType.END){
            const nameLength = reader.readInt(u16) catch @panic("hier");
            name = reader.readSlice(nameLength) catch @panic("hier");
            //std.debug.print("{s} {s}\n", .{ @tagName(typ),name.?});
        }
        //else std.debug.print("{s}\n", .{ @tagName(typ)});
        
        return loadPayload(reader,typ,name) catch @panic("hier");
    }
    pub fn loadPayload(reader:*utils.BinaryReader,typ:TagType,name:?[]const u8)NBTError!NBT{
        var rv:NBT = NBT{.tagType = typ};

        if(typ == TagType.BYTE){
            rv.value = Value{.byte = reader.readInt(i8) catch @panic("hier")};
        }else if(typ == TagType.SHORT){
            rv.value = Value{.short = reader.readInt(i16) catch @panic("hier")};
        }else if(typ == TagType.INT){
            rv.value = Value{.int = reader.readInt(i32) catch @panic("hier")};
        }else if(typ == TagType.LONG){
            rv.value = Value{.long = reader.readInt(i64) catch @panic("hier")};
        }else if(typ == TagType.FLOAT){
            rv.value = Value{.float = reader.readFloat(f32) catch @panic("hier")};
        }else if(typ == TagType.DOUBLE){
            rv.value = Value{.double = reader.readFloat(f64) catch @panic("hier")};
        }else if(typ == TagType.BYTE_ARRAY){
            const array_size = @as(usize,@intCast(  reader.readInt(i32) catch @panic("hier")));
            var bytes = main.stackAllocator.alloc(u8,array_size);
            for (0..array_size) |i| {
                bytes[i] = reader.readInt(u8) catch @panic("hier");
            }
            rv.bytes = bytes;
        }else if(typ == TagType.STRING){
            const array_size = @as(usize,@intCast(reader.readInt(u16) catch @panic("hier")));
            var bytes = main.stackAllocator.alloc(u8,array_size);
            for (0..array_size) |i| {
                bytes[i] = reader.readInt(u8) catch @panic("hier");
            }
            rv.bytes = bytes;

            // const array_size = try reader.readInt(u16);
            // const bytes = try reader.readSlice(@as(usize,@intCast(array_size)));
            // //copy
            // rv.bytes = main.stackAllocator.dupe(u8, bytes);
        }else if(typ == TagType.LIST){
            const subtype:TagType = @enumFromInt( reader.readInt(u8) catch @panic("hier"));
            const array_size = @as(usize,@intCast( reader.readInt(i32) catch @panic("hier")));
            var array = main.stackAllocator.alloc(NBT,array_size);
            for (0..array_size)|i| {
                array[i] = loadPayload(reader, subtype,null) catch @panic("hier");
            }
            rv.array = array;
        }else if(typ == TagType.COMPOUND){
            var map = std.StringHashMap(NBT).init(main.globalAllocator.allocator);
            while (true) {
                var nbt = loadNBT(reader) catch @panic("hier");
                if(nbt.tagType == TagType.END){
                    nbt.deinit();
                    break;
                }else{
                    if(nbt.name)|n|{
                        if(map.getPtr(n))|old|{
                            old.deinit();
                        }
                        map.put(n,nbt) catch @panic("hier");
                    }
                }
            }
            rv.map = map;
        }
        else if(typ == TagType.INT_ARRAY){
            const array_size = @as(usize,@intCast(reader.readInt(i32) catch @panic("hier")));
            var int_array = main.stackAllocator.alloc(i32,array_size);
            for (0..array_size) |i| {
                int_array[i] = reader.readInt(i32) catch @panic("hier");
            }
            rv.int_array = int_array;
        }
        else if(typ == TagType.LONG_ARRAY){
                if(name)|n|
                std.debug.print(" {d}   {s}\n", .{reader.remaining.len,n});
            
            const array_size = @as(usize,@intCast(reader.readInt(i32) catch @panic("hier")));
            std.debug.print(" {d}\n", .{array_size});
            if(name)|n|
                std.debug.print(" {s}\n", .{n});
            var long_array = main.stackAllocator.alloc(i64,array_size);
            for (0..array_size) |i| {
                if(name)|n|
                std.debug.print(" {d}   {s}\n", .{reader.remaining.len,n});
                long_array[i] = reader.readInt(i64) catch @panic("{}");
            }
            rv.long_array = long_array;
        }
        
        var nameCopy:?[]u8 = null;
        if(name)|n|{
            nameCopy = main.stackAllocator.dupe(u8, n);
        }
        rv.name = nameCopy;

        return rv;
    }
    pub fn deinit(self:*NBT) void {
        if(self.bytes)|_|{
            main.stackAllocator.free(self.bytes.?);
            //main.stackAllocator.free(self.bytes.?);
        }
        if(self.name)|_|
            main.stackAllocator.free(self.name.?);
        if(self.array)|array|{
            for (0..array.len) |i| {
                array[i].deinit();
            }
            main.stackAllocator.free(array);
        }
        if(self.map)|map|{
            var it = map.valueIterator();            
            if(map.count()>0){
                while(it.next())|entry|{
                    entry.deinit();
                }
            }
            self.map.?.deinit();
        }
        if(self.int_array)|int_array|
            main.stackAllocator.free(int_array);
        if(self.long_array)|long_array|
            main.stackAllocator.free(long_array);
        
    }
    pub fn print(self:*const NBT,tab:[]const u8)void{
        std.debug.print("{s} ",.{tab});
        if(self.name)|n|{
            std.debug.print("{s} {s} ", .{@tagName(self.tagType),n});
        }else
            std.debug.print("{s} ", .{@tagName(self.tagType)});
        
        if(self.tagType == TagType.BYTE){
            std.debug.print("{d}", .{self.value.byte});
        }else if(self.tagType == TagType.SHORT){
            std.debug.print("{d}", .{self.value.short});
        }else if(self.tagType == TagType.INT){
            std.debug.print("{d}", .{self.value.int});
        }else if(self.tagType == TagType.LONG){
            std.debug.print("{d}", .{self.value.long});
        }else if(self.tagType == TagType.FLOAT){
            std.debug.print("{d}", .{self.value.float});
        }else if(self.tagType == TagType.DOUBLE){
            std.debug.print("{d}", .{self.value.double});
        }else if(self.tagType == TagType.STRING){
            std.debug.print("{s}", .{self.bytes.?});
        }  

        std.debug.print("\n", .{});
        if(self.array)|array|{
            for (array) |value| {
                const new_string = main.stackAllocator.alloc( u8, tab.len + 1);
                defer main.stackAllocator.free(new_string);
                @memcpy(new_string[0..tab.len], tab);
                @memcpy(new_string[tab.len..], "\t");
                value.print(new_string);

            }
        }
        if(self.map)|map|{
            var p = map.valueIterator();
            for(0..p.len)|i|{
                
                const new_string = main.stackAllocator.alloc( u8, tab.len + 1);
                defer main.stackAllocator.free(new_string);
                @memcpy(new_string[0..tab.len], tab);
                @memcpy(new_string[tab.len..], "\t");
                if(p.metadata[i].isUsed())
                    p.items[i].print(new_string);

            }
        }
        //bytes:?[]const u8=null, //byteArray,string
        //int_array:?[]const i32=null ,
        //long_array:?[]const i64=null,
        //map:?std.StringHashMap(NBT)=null,
    }
};