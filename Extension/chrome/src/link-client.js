// The extension's end of the link to Cool Head (PROTOCOL.md). Chrome's own calls are passed in, so the tests
// drive it with a mock port (test/link-client.test.js) through the alone, together, and dropped cases.
import { HOST_NAME, parseIncoming, hello, result } from './logic/protocol.js';

// Status: 'connecting' | 'linked' | 'notRunning' (the host is there, Cool Head isn't open) |
//         'notInstalled' (Chrome found no host: Cool Head isn't installed or hasn't set up the link) |
//         'notLinked' (the link ended for another reason).
export class LinkClient {
  // deps: { connect(name) -> port, lastError() -> string | undefined, helloInfo() -> { version, level },
  //         onStatus(status, app), onState(state), onRequest({ id, action }) -> Promise<{ ok, done, count }> }
  constructor(deps) {
    this.deps = deps;
    this.port = null;
    this.status = 'notLinked';
  }

  get connected() { return this.port !== null; }

  start() {
    if (this.port) return;
    let port;
    try {
      port = this.deps.connect(HOST_NAME);
    } catch (e) {
      this.setStatus('notInstalled');
      return;
    }
    this.port = port;
    this.heardFromHost = false;
    this.setStatus('connecting');
    port.onMessage.addListener((msg) => this.receive(msg));
    port.onDisconnect.addListener(() => this.dropped());
  }

  stop() {
    const p = this.port;
    this.port = null;
    try { p?.disconnect(); } catch { /* already gone */ }
    this.setStatus('notLinked');
  }

  setStatus(status, app = '') {
    if (status === this.status && !app) return;
    this.status = status;
    this.deps.onStatus(status, app);
  }

  dropped() {
    // Chrome sets lastError when it couldn't start the host at all; reading it also keeps Chrome from logging it.
    const err = this.deps.lastError?.() || '';
    this.port = null;
    const missing = !this.heardFromHost && /not found|forbidden|not allowed/i.test(err);
    this.setStatus(missing ? 'notInstalled' : 'notLinked');
  }

  post(msg) {
    if (!this.port) return false;
    try {
      this.port.postMessage(msg);
      return true;
    } catch {
      // The port closed between our check and the send: treat it as a drop, so the extension carries on alone.
      this.dropped();
      return false;
    }
  }

  async receive(raw) {
    this.heardFromHost = true;
    const m = parseIncoming(raw);
    switch (m.kind) {
      case 'link':
        if (m.app === 'running') {
          this.setStatus('linked');
          const { version, level } = this.deps.helloInfo();
          this.post(hello(version, level));
        } else {
          this.setStatus('notRunning');
        }
        break;
      case 'hello':
        if (this.status !== 'linked') this.setStatus('linked', m.app);
        else this.deps.onStatus('linked', m.app);
        break;
      case 'state':
        // A reading only counts while linked; one that slips in after Cool Head closed is dropped.
        if (this.status === 'linked') await this.deps.onState(m.state);
        break;
      case 'request': {
        if (this.status !== 'linked') break;
        let r;
        try {
          r = await this.deps.onRequest({ id: m.id, action: m.action });
        } catch (e) {
          r = { ok: false, done: String(e?.message || ''), count: 0 };
        }
        this.post(result(m.id, r.ok, r.done, r.count));
        break;
      }
      default:
        break; // unknown types and fields are ignored, so either side can be newer
    }
  }

  send(msg) {
    return this.status === 'linked' ? this.post(msg) : false;
  }
}
