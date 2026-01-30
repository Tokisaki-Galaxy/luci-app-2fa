#!/usr/bin/ucode

// Copyright (c) 2024 Christian Marangi <ansuelsmth@gmail.com>
import { cursor } from 'uci';

function sToc(s) {
	return ord(s);
}

function cTos(c) {
	return chr(c);
}

function create_base32_decode_table() {
	let table = {};
	
	// A-Z -> 0-25
	for (let i = 0; i < 26; i++) {
		table[ord('A') + i] = i;
		table[ord('a') + i] = i;
	}
	
	// 2-7 -> 26-31
	for (let i = 0; i < 6; i++) {
		table[ord('2') + i] = 26 + i;
	}
	
	return table;
}

const base32_decode_table = create_base32_decode_table();

function strToBin(string)
{
	let res = [];
	for (let i = 0; i < length(string); i++)
		res[i] = ord(string, i);
	return res;
}

function intToBin(int)
{
	let res = [];
	res[0] = (int >> 24) & 0xff;
	res[1] = (int >> 16) & 0xff;
	res[2] = (int >> 8) & 0xff;
	res[3] = int & 0xff;
	return res;
}

function binToStr(bin)
{
	return join("", map(bin, cTos));
}

function binToHex(bin)
{
	let hex = "";
	for (let i = 0; i < length(bin); i++) {
		let h = sprintf("%02X", bin[i]);
		hex = hex + h;
	}
	return hex;
}

function circular_shift(val, shift)
{
	return ((val << shift) | (val >> (32 - shift))) & 0xFFFFFFFF;
}

// Base32 解码函数
function decode_base32(string)
{
	if (length(string) == 0)
		return [];
	
	// 移除填充字符
	let clean = "";
	for (let i = 0; i < length(string); i++) {
		let c = substr(string, i, 1);
		if (c != "=" && c != " " && c != "\t" && c != "\n" && c != "\r") {
			clean = clean + c;
		}
	}
	
	if (length(clean) == 0)
		return [];
	
	let out = [];
	let buffer = 0;
	let bits_in_buffer = 0;
	
	for (let i = 0; i < length(clean); i++) {
		let char_code = ord(clean, i);
		
		if (!(char_code in base32_decode_table)) {
			continue;
		}
		
		let value = base32_decode_table[char_code];
		
		buffer = (buffer << 5) | value;
		bits_in_buffer += 5;
		
		if (bits_in_buffer >= 8) {
			bits_in_buffer -= 8;
			push(out, (buffer >> bits_in_buffer) & 0xff);
		}
	}
	
	return out;
}

function calculate_sha1(binary_string) {
	let len = length(binary_string);

	let h0 = 0x67452301;
	let h1 = 0xEFCDAB89;
	let h2 = 0x98BADCFE;
	let h3 = 0x10325476;
	let h4 = 0xC3D2E1F0;

	let padded_string = [];

	for (let i = 0; i < len; i++)
		padded_string[i] = binary_string[i];

	padded_string[len++] = 0x80;

	let to_pad = 64 - ((len + 8) % 64);
	for (let i = 0; i < to_pad; i++)
		padded_string[len++] = 0x0;

	padded_string[len++] = 0x0;
	padded_string[len++] = 0x0;
	padded_string[len++] = 0x0;
	padded_string[len++] = 0x0;
	padded_string[len++] = 0x0;
	padded_string[len++] = 0x0;
	padded_string[len++] = 0x0;
	padded_string[len++] = length(binary_string) * 8;

	for (let i = 0; i < len; i += 64) {
		let block = [];

		for (let i2 = 0, j = 0; i2 < 16; i2++, j += 4) {
			block[i2] = padded_string[i + j] << 24;
			block[i2] |= padded_string[i + j + 1] << 16;
			block[i2] |= padded_string[i + j + 2] << 8;
			block[i2] |= padded_string[i + j + 3];
		}

		for (let j = 16; j < 80; j++)
			block[j] = circular_shift(block[j - 3] ^ block[j - 8] ^ block[j - 14] ^ block[j - 16], 1);

		let a = h0;
		let b = h1;
		let c = h2;
		let d = h3;
		let e = h4;

		for (let j = 0; j < 80; j++) {
			let f = 0;
			let k = 0;

			if (j < 20) {
				f = (b & c) | ((~b) & d);
				k = 0x5A827999;
			} else if (j < 40) {
				f = b ^ c ^ d;
				k = 0x6ED9EBA1;
			} else if (j < 60) {
				f = (b & c) | (b & d) | (c & d);
				k = 0x8F1BBCDC;
			} else {
				f = b ^ c ^ d;
				k = 0xCA62C1D6;
			}

			let temp = circular_shift(a, 5) + f + e + k + block[j] & 0xFFFFFFFF;
			e = d;
			d = c;
			c = circular_shift(b, 30);
			b = a;
			a = temp;
		}

		h0 = (h0 + a) & 0xFFFFFFFF;
		h1 = (h1 + b) & 0xFFFFFFFF;
		h2 = (h2 + c) & 0xFFFFFFFF;
		h3 = (h3 + d) & 0xFFFFFFFF;
		h4 = (h4 + e) & 0xFFFFFFFF;
	}

	let sha1 = [];

	let h0_binary = intToBin(h0);
	for (let i = 0; i < length(h0_binary); i++)
		sha1[i] = h0_binary[i];

	let h1_binary = intToBin(h1);
	for (let i = 0; i < length(h1_binary); i++)
		sha1[i+4] = h1_binary[i];

	let h2_binary = intToBin(h2);
	for (let i = 0; i < length(h2_binary); i++)
		sha1[i+8] = h2_binary[i];

	let h3_binary = intToBin(h3);
	for (let i = 0; i < length(h3_binary); i++)
		sha1[i+12] = h3_binary[i];

	let h4_binary = intToBin(h4);
	for (let i = 0; i < length(h4_binary); i++)
		sha1[i+16] = h4_binary[i];

	return sha1;
}

function calculate_hmac_sha1(key, message) {
	const message_binary = strToBin(message);
	let binary_key = strToBin(key);

	if (length(key) > 64)
		binary_key = calculate_sha1(binary_key);

	for (let i = 0; i < 64 - length(key); i++)
		binary_key[length(key)+i] = 0x0;

	let ko = [];
	for (let i = 0; i < 64; i++)
		ko[i] = binary_key[i] ^ 0x36;

	for (let i = 0; i < length(message); i++)
		ko[64+i] = message_binary[i];

	const sha1_ko = calculate_sha1(ko);

	ko = [];

	for (let i = 0; i < 64; i++)
		ko[i] = binary_key[i] ^ 0x5c;

	for (let i = 0; i < length(sha1_ko); i++)
		ko[64+i] = sha1_ko[i];

	const hmac = calculate_sha1(ko);

	return hmac;
}

// 测试函数
function test_totp() {
	let key = "X6XB6XVLZLWWHX5G";
	
	// 解码密钥
	let secret_binary = decode_base32(key);
	
	printf("密钥 (Base32): %s\n", key);
	printf("密钥 (解码后): %s\n", binToHex(secret_binary));
	printf("密钥长度: %d 字节\n\n", length(secret_binary));
	
	// 2026-01-31 06:20:20 UTC = 1769840420
	let timestamp = 1769840420;
	let step = 30;
	let counter = int(timestamp / step);
	
	printf("时间戳: %d\n", timestamp);
	printf("计数器: %d\n", counter);
	printf("计数器 (hex): 0x%08X\n\n", counter);
	
	// 计数器字节
	let counter_bytes = [ 0x0, 0x0, 0x0, 0x0,
			      (counter >> 24) & 0xff,
			      (counter >> 16) & 0xff,
			      (counter >> 8) & 0xff,
			      counter & 0xff ];
	
	printf("计数器字节: %s\n\n", binToHex(counter_bytes));
	
	// 计算 HMAC-SHA1
	let digest = calculate_hmac_sha1(binToStr(secret_binary), binToStr(counter_bytes));
	
	printf("HMAC-SHA1: %s\n\n", binToHex(digest));
	
	// 动态截断
	let offset_bits = digest[19] & 0xf;
	
	printf("Offset: %d\n", offset_bits);
	
	let p = [];
	for (let i = 0; i < 4; i++)
		p[i] = digest[offset_bits+i];
	
	printf("截断 4 字节: %s\n", binToHex(p));
	
	let snum = (p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]) & 0x7fffffff;
	printf("32位整数: %d (0x%08X)\n", snum, snum);
	
	let otp = snum % 10 ** 6;
	
	printf("OTP: %06d\n", otp);
}

test_totp();
