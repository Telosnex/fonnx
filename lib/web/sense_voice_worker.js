// The query of this Worker URL holds the fonnx webVersion (kiln
// ADR 002 D7). ORT and its Wasm files load with the same query, so a browser
// does not use a cached file of another version.
const query = new URL(import.meta.url).search;
// Messages that arrive while ORT loads have no handler yet. Keep them, and
// dispatch them again at the end of this module.
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

const sessions = new Map();

function disposeTensor(tensor) {
  if (tensor && typeof tensor.dispose === 'function') tensor.dispose();
}

function requireSession(engineId) {
  const session = sessions.get(engineId);
  if (!session) throw new Error(`Unknown SenseVoice engine: ${engineId}`);
  return session;
}

// Returns the logits: (frames + 4) × vocabulary.
async function run(session, { features, frames, language, textNorm }) {
  const int32 = (value) => new ort.Tensor('int32', Int32Array.of(value), [1]);
  const inputs = {
    x: new ort.Tensor('float32', features, [1, frames, features.length / frames]),
    x_length: int32(frames),
    language: int32(language),
    text_norm: int32(textNorm),
  };
  let result;
  try {
    result = await session.run(inputs, ['logits']);
  } finally {
    for (const tensor of Object.values(inputs)) disposeTensor(tensor);
  }
  const logits = result.logits.data.slice();
  disposeTensor(result.logits);
  return logits;
}

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

self.onmessage = async ({ data }) => {
  const { action, messageId, engineId } = data;
  try {
    if (data.protocolVersion !== 1) throw new Error('Unsupported FONNX Worker protocol');
    if (action === 'resourceUrls') return;
    if (action === 'load') {
      const session = await ort.InferenceSession.create(data.model, { executionProviders: ['wasm'] });
      const previous = sessions.get(engineId);
      if (previous) await previous.release();
      sessions.set(engineId, session);
      self.postMessage({ action: 'result', messageId });
      return;
    }
    const session = requireSession(engineId);
    if (action === 'run') {
      const result = await run(session, data);
      self.postMessage({ action: 'result', messageId, result }, [result.buffer]);
    } else if (action === 'close') {
      await session.release();
      sessions.delete(engineId);
      self.postMessage({ action: 'result', messageId });
    } else {
      throw new Error(`Unknown action: ${action}`);
    }
  } catch (error) {
    self.postMessage({ action: 'error', messageId, error: `${error.message}\n${error.stack || ''}` });
  }
};

for (const data of earlyMessages.splice(0)) {
  self.dispatchEvent(new MessageEvent('message', { data }));
}
