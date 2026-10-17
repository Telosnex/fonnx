// The query of this Worker URL holds the fonnx webVersion (native_prebuilt
// ADR 002 D7). ORT, its Wasm files and the compiled Dart engine load with the
// same query, so a browser does not use a cached file of another version.
const query = new URL(import.meta.url).search;
// Messages that arrive while ORT and the engine load have no handler yet.
// Keep them, and dispatch them again at the end of this module.
const earlyMessages = [];
self.onmessage = ({ data }) => earlyMessages.push(data);
const ort = await import(`./ort.min.mjs${query}`);

// Half the cores: testing showed all cores was 15% slower than half
// (MacBook Air M2, hardwareConcurrency 8).
const cores = navigator.hardwareConcurrency || 1;
ort.env.wasm.numThreads = Math.max(1, Math.floor(cores / 2));
ort.env.wasm.wasmPaths = {
  mjs: new URL(`./ort-wasm-simd-threaded.mjs${query}`, import.meta.url).href,
  wasm: new URL(`./ort-wasm-simd-threaded.wasm${query}`, import.meta.url).href,
};

// engineId -> { prosody, decoder, fallback } ORT sessions.
const sessions = new Map();

function requireSessions(engineId) {
  const s = sessions.get(engineId);
  if (!s) throw new Error(`Unknown Kokoro engine: ${engineId}`);
  return s;
}

async function createSession(url, label) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Unable to fetch Kokoro ${label} ${url}: HTTP ${response.status}`);
  const model = new Uint8Array(await response.arrayBuffer());
  return ort.InferenceSession.create(model, { executionProviders: ['wasm'] });
}

async function releaseAll(s) {
  for (const session of [s.prosody, s.decoder, s.fallback]) await session?.release();
}

const int64 = (values) => BigInt64Array.from(values, (v) => BigInt(v));

async function runSession(session, inputs, outputs) {
  try {
    return await session.run(inputs, outputs);
  } finally {
    for (const tensor of Object.values(inputs)) tensor.dispose?.();
  }
}

// The ORT calls of the Dart engine (lib/models/kokoro/web/kokoro_engine_worker.dart).
// Each resolves to a value: the compiled Dart code rejects undefined.
self.fonnxKokoroOrt = {
  async load(engineId, prosodyUrl, decoderUrl, fallbackUrl) {
    const s = {};
    try {
      s.prosody = await createSession(prosodyUrl, 'prosody model');
      s.decoder = await createSession(decoderUrl, 'decoder model');
      s.fallback = await createSession(fallbackUrl, 'fallback model');
    } catch (error) {
      await releaseAll(s);
      throw error;
    }
    const previous = sessions.get(engineId);
    sessions.set(engineId, s);
    if (previous) await releaseAll(previous);
    return true;
  },

  // ids holds the pad tokens.
  async prosody(engineId, ids, style, speed) {
    const r = await runSession(requireSessions(engineId).prosody, {
      input_ids: new ort.Tensor('int64', int64(ids), [1, ids.length]),
      style: new ort.Tensor('float32', style, [1, 256]),
      speed: new ort.Tensor('float32', Float32Array.of(speed), [1]),
    }, ['asr', 'f0', 'n']);
    const [batch, channels, frames] = r.asr.dims;
    if (batch !== 1 || channels !== 512 || r.f0.data.length !== 2 * frames ||
        r.n.data.length !== 2 * frames) {
      throw new Error('Unsupported Kokoro stage shapes');
    }
    const out = { asr: r.asr.data.slice(), f0: r.f0.data.slice(), n: r.n.data.slice(), frames };
    for (const tensor of Object.values(r)) tensor.dispose?.();
    return out;
  },

  async decode(engineId, asr, f0, n, style, frames) {
    const r = await runSession(requireSessions(engineId).decoder, {
      asr: new ort.Tensor('float32', asr, [1, 512, frames]),
      f0: new ort.Tensor('float32', f0, [1, 2 * frames]),
      n: new ort.Tensor('float32', n, [1, 2 * frames]),
      style: new ort.Tensor('float32', style, [1, 256]),
    }, ['waveform']);
    const waveform = r.waveform.data.slice();
    r.waveform.dispose?.();
    return waveform;
  },

  // The most likely token after dec. Ties go to the lower id, as on native.
  async fallbackNext(engineId, src, dec) {
    const r = await runSession(requireSessions(engineId).fallback, {
      input_ids: new ort.Tensor('int64', int64(src), [1, src.length]),
      decoder_input_ids: new ort.Tensor('int64', int64(dec), [1, dec.length]),
    }, ['logits']);
    const logits = r.logits.data;
    const vocab = logits.length / dec.length;
    const o = (dec.length - 1) * vocab;
    let best = 0;
    for (let i = 1; i < vocab; i++) if (logits[o + i] > logits[o + best]) best = i;
    r.logits.dispose?.();
    return best;
  },

  async close(engineId) {
    const s = sessions.get(engineId);
    sessions.delete(engineId);
    if (s) await releaseAll(s);
    return true;
  },
};

// The compiled Dart engine calls fonnxKokoroEngineReady from its main. Each
// of its functions resolves to { value } or { error }.
const dartEngine = await new Promise((resolve, reject) => {
  self.fonnxKokoroEngineReady = resolve;
  import(`./kokoro_engine.dart.js${query}`).catch(reject);
});
const engine = Object.fromEntries(['load', 'begin', 'next', 'cancel', 'close'].map((name) => [
  name,
  async (...args) => {
    const { value, error } = await dartEngine[name](...args);
    if (error !== undefined && error !== null) throw new Error(error);
    return value;
  },
]));

// For the browser test of the ?v= query on every loaded file. This listener
// is added before onmessage, so its reply comes first.
self.addEventListener('message', ({ data }) => {
  if (data?.action !== 'resourceUrls') return;
  self.postMessage({
    messageId: data.messageId,
    action: 'resourceUrls',
    urls: performance.getEntriesByType('resource').map((e) => e.name),
  });
});

async function handle({ action, engineId, ...data }) {
  switch (action) {
    case 'load': return { result: await engine.load(engineId, data.request) };
    case 'begin':
      await engine.begin(engineId, data.text, data.voice, data.speed, data.normalize);
      return {};
    case 'next': {
      const chunk = await engine.next(engineId);
      if (!chunk) return { result: null };
      // A copy: the Dart engine may keep views of the decoded buffer.
      const samples = chunk.samples.slice();
      return {
        result: { samples, isFinal: chunk.isFinal, phonemes: chunk.phonemes ?? null },
        transfer: [samples.buffer],
      };
    }
    case 'cancel': await engine.cancel(engineId); return {};
    case 'close': await engine.close(engineId); return {};
    default: throw new Error(`Unknown action: ${action}`);
  }
}

// The engine keeps state per request, so requests run one at a time, in order.
let queue = Promise.resolve();
self.onmessage = ({ data }) => {
  const { action, messageId } = data;
  if (action === 'resourceUrls') return;
  queue = queue.then(async () => {
    try {
      if (data.protocolVersion !== 1) throw new Error('Unsupported FONNX Worker protocol');
      const { result, transfer = [] } = await handle(data);
      self.postMessage({ action: 'result', messageId, result }, transfer);
    } catch (error) {
      self.postMessage({ action: 'error', messageId, error: `${error?.message ?? error}\n${error?.stack || ''}` });
    }
  });
};

for (const data of earlyMessages.splice(0)) {
  self.dispatchEvent(new MessageEvent('message', { data }));
}
