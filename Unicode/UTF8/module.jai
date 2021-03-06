#scope_module

#import "Runtime";
#import "Unicode";
mem :: #import "Memory";
str :: #import "String";

#scope_export

Str :: struct
{
	count : s64;
	data  : *u8;
	#place count;
	#as as_string : string;
	#place count;
	#as as_array : []u8;
}

make_str :: inline (data : *u8, count : s64) -> Str #must
{
	result : Str = ---;
	result.data  = data;
	result.count = count;
	return result;
}

make_str :: inline (s : string) -> Str #must
{
	return make_str (s.data, s.count);
}

for_expansion :: (s : *Str, body : Code, flags : For_Flags) #expand
{
	fmt :: #import "Fmt";

	`it_index := 0;
	byte_offset := 0;
	while byte_offset < s.count
	{
		`it, advance, valid := decode (s.as_array, byte_offset);
		if !valid
			break;
		#insert body;
		byte_offset += advance;
		it_index += 1;
	}
}

decode :: inline (s : string, allocator : Allocator) -> []u32 #must, valid : bool
#no_abc
{
	valid_input := true;
	result := mem.alloc (u32, length (s), allocator);
	i := 0;
	offset := 0;
	while offset < s.count
	{
		codepoint, advance, valid := decode (str.to_array (s), offset);
		result[i] = codepoint;
		i += 1;
		offset += advance;
		valid_input &= valid;
	}

	return result, valid_input;
}

decode :: inline (buffer : []u8, byte_offset : s64) -> codepoint : u32, size : s64, valid : bool
{
	codepoint, size, valid := decode (mem.advance (buffer, byte_offset));
	return codepoint, size, valid;
}

decode :: (buffer : []u8) -> codepoint : u32, size : s64, valid : bool
#no_abc
{
	if buffer.count > 0
	{
		b0 := buffer[0];
		x  := UTF8_FIRST[b0];
		if x >= 0xf0
		{
			mask := (cast (u32) x << 31) >> 31;
			return (cast (u32) b0 & (~mask)) | (CODEPOINT_INVALID & mask), 1, true;
		}
		else if b0 < 0x80
			return b0, 1, true;

		sz := x & 7;
		range := UTF8_ACCEPT_RANGES[x >> 4];
		if buffer.count < 2 || buffer[1] < range.lo || buffer[1] > range.hi
			return CODEPOINT_INVALID, 1, false;
		b1 := buffer[1];
		if sz == 2
			return ((cast (u32) b0 & 0x1f) << 6) | (cast (u32) b1 & 0x3f), 2, true;

		if buffer.count < 3 || buffer[2] < 0x80 || buffer[2] > 0xbf
			return CODEPOINT_INVALID, 1, false;
		b2 := buffer[2];
		if sz == 3
			return ((cast (u32) b0 & 0x1f) << 12) | ((cast (u32) b1 & 0x3f) << 6) | (cast (u32) b2 & 0x3f), 3, true;

		if buffer.count < 4 || buffer[3] < 0x80 || buffer[3] > 0xbf
			return CODEPOINT_INVALID, 1, false;
		b3 := buffer[3];

		return ((cast (u32) b0 & 0x07) << 18) | ((cast (u32) b1 & 0x3f) << 12) | ((cast (u32) b2 & 0x3f) << 6) | ((cast (u32) b3 & 0x3f)), 4, true;
	}

	return CODEPOINT_INVALID, 1, false;

	UTF8_FIRST :: u8.[
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x00-0x0F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x10-0x1F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x20-0x2F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x30-0x3F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x40-0x4F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x50-0x5F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x60-0x6F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x70-0x7F
		0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, // 0x80-0x8F
		0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, // 0x90-0x9F
		0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, // 0xA0-0xAF
		0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, // 0xB0-0xBF
		0xf1, 0xf1, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, // 0xC0-0xCF
		0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, // 0xD0-0xDF
		0x13, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x23, 0x03, 0x03, // 0xE0-0xEF
		0x34, 0x04, 0x04, 0x04, 0x44, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, // 0xF0-0xFF
	];

	Utf8_Accept_Range :: struct
	{
		lo, hi : u8;
	}

	UTF8_ACCEPT_RANGES :: Utf8_Accept_Range.[
		Utf8_Accept_Range.{ 0x80, 0xbf },
		Utf8_Accept_Range.{ 0xa0, 0xbf },
		Utf8_Accept_Range.{ 0x80, 0x9f },
		Utf8_Accept_Range.{ 0x90, 0xbf },
		Utf8_Accept_Range.{ 0x80, 0x8f },
	];
}

encoding_length :: inline (codepoint : u32) -> size : s64 #must
{
	if codepoint <= 0x7f
		return 1;
	else if codepoint <= 0x7ff
		return 2;
	else if codepoint <= 0xffff
		return 3;
	else if codepoint <= 0x1fffff
		return 4;
	return 3;
}

encode :: inline (s : []u32, allocator : Allocator) -> string #must, valid : bool
{
	valid := true;
	result : string;
	for s
		result.count += encoding_length (it);
	result.data = mem.alloc (result.count, allocator);
	i := 0;
	for s
	{
		advance, ok := encode (str.to_array (result), i, it);
		valid &= ok;
		i += advance;
	}

	return result, valid;
}

encode :: inline (buffer : []u8, offset : s64, codepoint : u32) -> size : s64, valid : bool
{
	size, valid := encode (mem.advance (buffer, offset), codepoint);
	return size, valid;
}

encode :: (buffer : []u8, codepoint : u32) -> size : s64, valid : bool
{
	MASK : u8 : 0x3f;
	i := codepoint;
	if i <= (1 << 7) - 1
	{
		buffer[0] = cast (u8) codepoint;

		return 1, true;
	}
	else if i <= (1 << 11) - 1
	{
		buffer[0] = 0xc0 |  cast (u8) (codepoint >> 6);
		buffer[1] = 0x80 | (cast (u8) (codepoint) & MASK);

		return 2, true;
	}
	else if i > CODEPOINT_MAX || (i >= 0xd800 && i <= 0xdfff)
	{
		codepoint = CODEPOINT_INVALID;
		buffer[0] = 0xe0 |  cast (u8) (codepoint >> 12);
		buffer[1] = 0x80 | (cast (u8) (codepoint >> 6) & MASK);
		buffer[2] = 0x80 | (cast (u8) (codepoint) & MASK);
	
		return 3, false;
	}
	else if i <= (1 << 16) - 1
	{
		buffer[0] = 0xe0 |  cast (u8) (codepoint >> 12);
		buffer[1] = 0x80 | (cast (u8) (codepoint >> 6) & MASK);
		buffer[2] = 0x80 | (cast (u8) (codepoint) & MASK);

		return 3, true;
	}
	else
	{
		buffer[0] = 0xf0 |  cast (u8) (codepoint >> 18);
		buffer[1] = 0x80 | (cast (u8) (codepoint >> 12) & MASK);
		buffer[2] = 0x80 | (cast (u8) (codepoint >> 6) & MASK);
		buffer[3] = 0x80 | (cast (u8) (codepoint) & MASK);
	
		return 4, true;
	}
}

length :: inline (s : string) -> s64 #must, valid : bool
{
	len := 0;
	i := 0;
	while i < s.count
	{
		c := s[i];
		if c < 0x80
			i += 1;
		else if (c & 0xe0) == 0xc0 && i + 2 <= s.count
			i += 2;
		else if (c & 0xf0) == 0xe0 && i + 3 <= s.count
			i += 3;
		else if (c & 0xf8) == 0xf0 && i + 4 <= s.count
			i += 4;
		else
			return len, false;
		len += 1;
	}

	return len, true;
}
