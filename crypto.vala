namespace Airtunes
{
	public uint8[] aes_encrypt(uint8[] key, uint8[] iv, uint8[] data)
	{
		return_if_fail(iv.length == Nettle.AES_BLOCK_SIZE);
		
		// nettle overrites the iv, so make a copy
		uint8[] iv_copy = {};
		iv_copy.resize(iv.length);
		Posix.memcpy(iv_copy, iv, iv.length);
		
		var encrypt_part = data.length / Nettle.AES_BLOCK_SIZE;
		encrypt_part *= Nettle.AES_BLOCK_SIZE;
		
		var aes = Nettle.AES();
		aes.set_encrypt_key(key.length, key);
		uint8[] result = {};
		result.resize(data.length);

		Nettle.cbc_encrypt(&aes, aes.encrypt, Nettle.AES_BLOCK_SIZE, iv_copy, encrypt_part, result, data);
		
		if (encrypt_part != data.length)
			Posix.memcpy(&result[encrypt_part], &data[encrypt_part], data.length - encrypt_part);
		
		return result;
	}
}
