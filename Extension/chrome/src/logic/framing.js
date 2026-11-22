// The two framings on the link (PROTOCOL.md, "Framing"). The extension itself never frames anything: Chrome
// does it between the extension and the host. These are here so the tests and the mock host speak exactly what
// Chrome and Cool Head speak, and so Cool Head's host can be checked against the same rules.
// Uses Uint8Array and TextEncoder only, so it runs in Node and in a browser alike.

// Chrome's native messaging: a 4-byte little-endian length, then UTF-8 JSON. At most 1 MB from the host.
export const MAX_FROM_HOST = 1024 * 1024;

const enc = new TextEncoder();
const dec = new TextDecoder('utf-8', { fatal: true });

export function encodeNative(obj, max = MAX_FROM_HOST) {
  const body = enc.encode(JSON.stringify(obj));
  if (body.length > max) throw new RangeError(`message is ${body.length} bytes; the limit is ${max}`);
  const out = new Uint8Array(4 + body.length);
  new DataView(out.buffer).setUint32(0, body.length, true);
  out.set(body, 4);
  return out;
}

// Feeds bytes as they arrive (reads can split anywhere) and returns whole messages.
export class NativeDecoder {
  constructor(max = MAX_FROM_HOST) {
    this.max = max;
    this.buf = new Uint8Array(0);
  }

  push(chunk) {
    const joined = new Uint8Array(this.buf.length + chunk.length);
    joined.set(this.buf, 0);
    joined.set(chunk, this.buf.length);
    this.buf = joined;
    const out = [];
    while (this.buf.length >= 4) {
      const len = new DataView(this.buf.buffer, this.buf.byteOffset, 4).getUint32(0, true);
      if (len > this.max) throw new RangeError(`message length ${len} is over the limit of ${this.max}`);
      if (this.buf.length < 4 + len) break;
      out.push(JSON.parse(dec.decode(this.buf.subarray(4, 4 + len))));
      this.buf = this.buf.slice(4 + len);
    }
    return out;
  }
}

// Host to Cool Head and back: one JSON object per line, UTF-8.
export function encodeLine(obj) {
  return enc.encode(JSON.stringify(obj) + '\n');
}

export class LineDecoder {
  constructor() { this.bytes = new Uint8Array(0); }

  push(chunk) {
    // Keep bytes until a newline arrives, so a character split across reads is decoded whole.
    const joined = new Uint8Array(this.bytes.length + chunk.length);
    joined.set(this.bytes, 0);
    joined.set(chunk, this.bytes.length);
    const out = [];
    let start = 0;
    for (let i = 0; i < joined.length; i += 1) {
      if (joined[i] === 0x0a) {
        const line = dec.decode(joined.subarray(start, i)).trim();
        if (line) out.push(JSON.parse(line));
        start = i + 1;
      }
    }
    this.bytes = joined.slice(start);
    return out;
  }
}
