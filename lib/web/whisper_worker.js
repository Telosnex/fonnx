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

// Whisper's encoder outputs 1500 frames. Each attention head has 64
// dimensions. The vocabulary is that of the multilingual models before
// large-v3.
const encoderFrames = 1500;
const headDimension = 64;
const vocabularySize = 51865;

const engines = new Map();

function disposeTensor(tensor) {
  if (tensor && typeof tensor.dispose === 'function') tensor.dispose();
}

function releaseState(engine) {
  disposeTensor(engine.hiddenStates);
  for (const tensor of [...engine.selfCache, ...engine.crossCache]) disposeTensor(tensor);
  engine.hiddenStates = null;
  engine.selfCache = [];
  engine.crossCache = [];
  engine.batch = 0;
  engine.cachedPositions = 0;
}

async function releaseEngine(engine) {
  releaseState(engine);
  await engine.encoder?.release();
  await engine.decoder?.release();
}

async function createEngine({ encoder, decoder, layers, heads }) {
  const options = { executionProviders: ['wasm'] };
  // Decoder self-attention caches first, then encoder cross-attention.
  const pastNames = [];
  for (const kind of ['decoder', 'encoder']) {
    for (let i = 0; i < layers; i++) {
      pastNames.push(`past_key_values.${i}.${kind}.key`, `past_key_values.${i}.${kind}.value`);
    }
  }
  const engine = {
    encoder: null,
    decoder: null,
    heads,
    pastNames,
    presentNames: pastNames.map((name) => name.replace('past_key_values', 'present')),
    selfCount: 2 * layers,
    hiddenStates: null,
    selfCache: [],
    crossCache: [],
    batch: 0,
    cachedPositions: 0,
  };
  try {
    engine.encoder = await ort.InferenceSession.create(encoder, options);
    engine.decoder = await ort.InferenceSession.create(decoder, options);
    return engine;
  } catch (error) {
    await releaseEngine(engine);
    throw error;
  }
}

function requireEngine(engineId) {
  const engine = engines.get(engineId);
  if (!engine) throw new Error(`Unknown Whisper engine: ${engineId}`);
  return engine;
}

async function encode(engine, features, batch) {
  releaseState(engine);
  const input = new ort.Tensor('float32', features, [1, 80, 3000]);
  let result;
  try {
    result = await engine.encoder.run({ input_features: input });
  } finally {
    input.dispose();
  }
  const hidden = result.last_hidden_state.data;
  const width = hidden.length / encoderFrames;
  disposeTensor(result.last_hidden_state);
  if (width !== engine.heads * headDimension) {
    throw new Error(`Whisper encoder width ${width} does not match ${engine.heads} attention heads`);
  }
  // Every row starts from the same audio.
  const tiled = new Float32Array(batch * hidden.length);
  for (let row = 0; row < batch; row++) tiled.set(hidden, row * hidden.length);
  engine.hiddenStates = new ort.Tensor('float32', tiled, [batch, encoderFrames, width]);
  engine.batch = batch;
}

// Makes cache row i a copy of the old row parents[i].
function reorder(engine, parents) {
  let identity = true;
  for (let i = 0; i < parents.length; i++) if (parents[i] !== i) identity = false;
  if (identity) return;
  engine.selfCache = engine.selfCache.map((tensor) => {
    const data = tensor.data;
    const rowLength = data.length / engine.batch;
    const gathered = new Float32Array(data.length);
    for (let row = 0; row < engine.batch; row++) {
      const start = parents[row] * rowLength;
      gathered.set(data.subarray(start, start + rowLength), row * rowLength);
    }
    const next = new ort.Tensor('float32', gathered, tensor.dims);
    disposeTensor(tensor);
    return next;
  });
}

async function decode(engine, tokens, length, parents) {
  if (!engine.hiddenStates) throw new Error('Call encode first');
  const batch = engine.batch;
  if (tokens.length !== batch * length) throw new Error(`Bad token count ${tokens.length}`);
  const first = engine.cachedPositions === 0;
  if (!first && parents) {
    if (parents.length !== batch) throw new Error(`Bad parent count ${parents.length}`);
    reorder(engine, parents);
  }

  const inputs = {
    input_ids: new ort.Tensor('int64', BigInt64Array.from(tokens, (t) => BigInt(t)), [batch, length]),
    use_cache_branch: new ort.Tensor('bool', [!first], [1]),
  };
  const feeds = { ...inputs, encoder_hidden_states: engine.hiddenStates };
  const past = first ? [] : [...engine.selfCache, ...engine.crossCache];
  engine.pastNames.forEach((name, i) => {
    if (first) {
      inputs[name] = new ort.Tensor('float32', new Float32Array(0), [batch, engine.heads, 0, headDimension]);
      feeds[name] = inputs[name];
    } else {
      feeds[name] = past[i];
    }
  });
  // After the first step the cross-attention cache does not change, so only
  // the self-attention cache is fetched.
  const fetches = ['logits', ...(first ? engine.presentNames : engine.presentNames.slice(0, engine.selfCount))];
  let result;
  try {
    result = await engine.decoder.run(feeds, fetches);
  } finally {
    for (const tensor of Object.values(inputs)) disposeTensor(tensor);
  }

  const logits = result.logits.data;
  if (logits.length !== batch * length * vocabularySize) {
    for (const tensor of Object.values(result)) disposeTensor(tensor);
    throw new Error(`Unexpected Whisper logits length ${logits.length}`);
  }
  const last = new Float32Array(batch * vocabularySize);
  for (let row = 0; row < batch; row++) {
    const start = (row * length + length - 1) * vocabularySize;
    last.set(logits.subarray(start, start + vocabularySize), row * vocabularySize);
  }
  disposeTensor(result.logits);

  for (const tensor of engine.selfCache) disposeTensor(tensor);
  engine.selfCache = engine.presentNames.slice(0, engine.selfCount).map((name) => result[name]);
  if (first) engine.crossCache = engine.presentNames.slice(engine.selfCount).map((name) => result[name]);
  engine.cachedPositions += length;
  return last;
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
      const engine = await createEngine(data);
      const previous = engines.get(engineId);
      if (previous) await releaseEngine(previous);
      engines.set(engineId, engine);
      self.postMessage({ action: 'result', messageId });
      return;
    }
    const engine = requireEngine(engineId);
    if (action === 'encode') {
      await encode(engine, data.features, data.batch);
      self.postMessage({ action: 'result', messageId });
    } else if (action === 'decode') {
      const result = await decode(engine, data.tokens, data.length, data.parents);
      self.postMessage({ action: 'result', messageId, result }, [result.buffer]);
    } else if (action === 'close') {
      await releaseEngine(engine);
      engines.delete(engineId);
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
