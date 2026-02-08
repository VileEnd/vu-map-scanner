---@diagnostic disable: undefined-global
-- AWS Signature Version 4 implementation for S3 PUT requests
-- Reused from positionTracking mod (TelemetryS3Signer)
-- Reference: https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
-- Pure Lua SHA-256 adapted from kikito/sha2 (MIT License)

local S3Signer = {}

-- SHA-256 constants (round constants)
local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

-- SHA-256 initial hash values
local H_INIT = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19}

local function rrotate(n, b)
	return ((n >> b) | (n << (32 - b))) & 0xffffffff
end

local function sha256(msg)
	local H = {H_INIT[1], H_INIT[2], H_INIT[3], H_INIT[4], H_INIT[5], H_INIT[6], H_INIT[7], H_INIT[8]}
	local len = #msg
	local msgLen = len * 8
	msg = msg .. '\x80'
	local padLen = 56 - ((len + 1) % 64)
	if padLen < 0 then padLen = padLen + 64 end
	msg = msg .. string.rep('\0', padLen)
	for i = 7, 0, -1 do
		msg = msg .. string.char((msgLen >> (i * 8)) & 0xff)
	end
	for chunkStart = 1, #msg, 64 do
		local w = {}
		for i = 0, 15 do
			local offset = chunkStart + i * 4
			w[i] = (msg:byte(offset) << 24) | (msg:byte(offset + 1) << 16) |
			       (msg:byte(offset + 2) << 8) | msg:byte(offset + 3)
		end
		for i = 16, 63 do
			local s0 = rrotate(w[i-15], 7) ~ rrotate(w[i-15], 18) ~ (w[i-15] >> 3)
			local s1 = rrotate(w[i-2], 17) ~ rrotate(w[i-2], 19) ~ (w[i-2] >> 10)
			w[i] = (w[i-16] + s0 + w[i-7] + s1) & 0xffffffff
		end
		local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
		for i = 0, 63 do
			local S1 = rrotate(e, 6) ~ rrotate(e, 11) ~ rrotate(e, 25)
			local ch = (e & f) ~ ((~e) & g)
			local temp1 = (h + S1 + ch + K[i+1] + w[i]) & 0xffffffff
			local S0 = rrotate(a, 2) ~ rrotate(a, 13) ~ rrotate(a, 22)
			local maj = (a & b) ~ (a & c) ~ (b & c)
			local temp2 = (S0 + maj) & 0xffffffff
			h = g; g = f; f = e
			e = (d + temp1) & 0xffffffff
			d = c; c = b; b = a
			a = (temp1 + temp2) & 0xffffffff
		end
		H[1] = (H[1] + a) & 0xffffffff; H[2] = (H[2] + b) & 0xffffffff
		H[3] = (H[3] + c) & 0xffffffff; H[4] = (H[4] + d) & 0xffffffff
		H[5] = (H[5] + e) & 0xffffffff; H[6] = (H[6] + f) & 0xffffffff
		H[7] = (H[7] + g) & 0xffffffff; H[8] = (H[8] + h) & 0xffffffff
	end
	local result = {}
	for i = 1, 8 do
		for j = 3, 0, -1 do
			result[#result + 1] = string.char((H[i] >> (j * 8)) & 0xff)
		end
	end
	return table.concat(result)
end

local function hmac_sha256(key, message)
	local blockSize = 64
	local opad = string.char(0x5c):rep(blockSize)
	local ipad = string.char(0x36):rep(blockSize)
	local derivedKey = key
	if #derivedKey > blockSize then derivedKey = sha256(key) end
	if #derivedKey < blockSize then derivedKey = derivedKey .. string.char(0):rep(blockSize - #derivedKey) end
	local innerKey, outerKey = {}, {}
	for i = 1, blockSize do
		local keyByte = derivedKey:byte(i)
		innerKey[i] = string.char(keyByte ~ ipad:byte(i))
		outerKey[i] = string.char(keyByte ~ opad:byte(i))
	end
	return sha256(table.concat(outerKey) .. sha256(table.concat(innerKey) .. message))
end

local function hex_encode(str)
	return (str:gsub('.', function(c) return string.format('%02x', string.byte(c)) end))
end

local function sha256_hex(str) return hex_encode(sha256(str)) end

local function uri_encode(str)
	return str:gsub('[^A-Za-z0-9%-_.~]', function(c) return string.format('%%%02X', string.byte(c)) end)
end

local function uri_encode_path(path)
	local segments = {}
	for segment in string.gmatch(path, '[^/]+') do
		segments[#segments + 1] = uri_encode(segment)
	end
	return table.concat(segments, '/')
end

local function get_signing_key(secretKey, dateStamp, region, service)
	local kDate = hmac_sha256('AWS4' .. secretKey, dateStamp)
	local kRegion = hmac_sha256(kDate, region)
	local kService = hmac_sha256(kRegion, service)
	return hmac_sha256(kService, 'aws4_request')
end

--- Generate AWS Signature V4 authorization header for S3 PUT request
function S3Signer.SignPutRequest(accessKey, secretKey, region, bucket, objectKey, contentType, payload, endpoint, pathStyle)
	local nowUnix = os.time()
	local requestDateTime = os.date('!%Y%m%dT%H%M%SZ', nowUnix)
	local dateStamp = os.date('!%Y%m%d', nowUnix)

	local host, canonicalUri
	if pathStyle then
		host = (endpoint and endpoint ~= '') and endpoint or ('s3.' .. region .. '.amazonaws.com')
		canonicalUri = '/' .. bucket .. '/' .. uri_encode_path(objectKey)
	else
		if endpoint and endpoint ~= '' then
			host = bucket .. '.' .. endpoint
		else
			host = bucket .. '.s3.' .. region .. '.amazonaws.com'
		end
		canonicalUri = '/' .. uri_encode_path(objectKey)
	end

	local payloadHash = sha256_hex(payload)
	local canonicalHeaders = 'content-type:' .. contentType .. '\n' ..
	                         'host:' .. host .. '\n' ..
	                         'x-amz-content-sha256:' .. payloadHash .. '\n' ..
	                         'x-amz-date:' .. requestDateTime
	local signedHeaders = 'content-type;host;x-amz-content-sha256;x-amz-date'

	local canonicalRequest = table.concat({
		'PUT', canonicalUri, '', canonicalHeaders, '', signedHeaders, payloadHash
	}, '\n')

	local credentialScope = dateStamp .. '/' .. region .. '/s3/aws4_request'
	local stringToSign = table.concat({
		'AWS4-HMAC-SHA256', requestDateTime, credentialScope, sha256_hex(canonicalRequest)
	}, '\n')

	local signingKey = get_signing_key(secretKey, dateStamp, region, 's3')
	local signature = hex_encode(hmac_sha256(signingKey, stringToSign))

	local authorizationHeader = 'AWS4-HMAC-SHA256 ' ..
		'Credential=' .. accessKey .. '/' .. credentialScope .. ', ' ..
		'SignedHeaders=' .. signedHeaders .. ', ' ..
		'Signature=' .. signature

	return {
		['Host'] = host,
		['Content-Type'] = contentType,
		['x-amz-content-sha256'] = payloadHash,
		['x-amz-date'] = requestDateTime,
		['Authorization'] = authorizationHeader
	}, {
		host = host, canonicalUri = canonicalUri,
		credentialScope = credentialScope, signature = signature
	}
end

return S3Signer
