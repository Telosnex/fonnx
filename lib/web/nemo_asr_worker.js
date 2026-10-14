// The query of this Worker URL holds the fonnx webVersion (native_prebuilt
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

// Parakeet TDT v3: encoder width, prediction network layers and width.
const encoderWidth = 1024;
const predictionLayers = 2;
const predictionWidth = 640;

const engines = new Map();

function disposeTensor(tensor) {
  if (tensor && typeof tensor.dispose === 'function') tensor.dispose();
}

function releaseState(engine) {
  disposeTensor(engine.prediction);
  for (const tensor of engine.state) disposeTensor(tensor);
  engine.encoded = null;
  engine.prediction = null;
  engine.state = [];
}

async function releaseEngine(engine) {
  releaseState(engine);
  for (const session of engine.sessions) await session.release();
}

async function createEngine({ kind, models }) {
  const options = { executionProviders: ['wasm'] };
  const engine = { kind, sessions: [], encoded: null, prediction: null, state: [] };
  try {
    for (const model of models) engine.sessions.push(await ort.InferenceSession.create(model, options));
    return engine;
  } catch (error) {
    await releaseEngine(engine);
    throw error;
  }
}

function requireEngine(engineId) {
  const engine = engines.get(engineId);
  if (!engine) throw new Error(`Unknown NemoAsr engine: ${engineId}`);
  return engine;
}

// Returns the CTC log-probabilities, or, for TDT, the number of encoder
// frames.
async function encode(engine, features, frames) {
  releaseState(engine);
  const [encoder] = engine.sessions;
  const inputs = {
    audio_signal: new ort.Tensor('float32', features, [1, features.length / frames, frames]),
    length: new ort.Tensor('int64', BigInt64Array.from([BigInt(frames)]), [1]),
  };
  let result;
  try {
    result = await encoder.run(inputs, [engine.kind === 'ctc' ? 'logprobs' : 'outputs']);
  } finally {
    for (const tensor of Object.values(inputs)) disposeTensor(tensor);
  }
  if (engine.kind === 'ctc') {
    const logprobs = result.logprobs.data.slice();
    disposeTensor(result.logprobs);
    return logprobs;
  }
  // outputs is 1 × width × frames. The joiner reads one frame at a time.
  const data = result.outputs.data;
  const encodedFrames = data.length / encoderWidth;
  const encoded = new Float32Array(data.length);
  for (let c = 0; c < encoderWidth; c++) {
    for (let t = 0; t < encodedFrames; t++) encoded[t * encoderWidth + c] = data[c * encodedFrames + t];
  }
  disposeTensor(result.outputs);
  engine.encoded = encoded;
  engine.state = [0, 1].map(
    () => new ort.Tensor('float32', new Float32Array(predictionLayers * predictionWidth), [predictionLayers, 1, predictionWidth]),
  );
  await predict(engine, engine.blank);
  return Float32Array.of(encodedFrames);
}

async function joint(engine, frame) {
  if (!engine.encoded || !engine.prediction) throw new Error('Call encode first');
  const input = new ort.Tensor(
    'float32',
    engine.encoded.slice(frame * encoderWidth, (frame + 1) * encoderWidth),
    [1, encoderWidth, 1],
  );
  let result;
  try {
    result = await engine.sessions[2].run({ encoder_outputs: input, decoder_outputs: engine.prediction });
  } finally {
    disposeTensor(input);
  }
  const logits = result.outputs.data.slice();
  disposeTensor(result.outputs);
  return logits;
}

// The input and output names are those of the sherpa-onnx export: the LSTM's
// hidden state, then its cell state.
async function predict(engine, token) {
  if (engine.state.length !== 2) throw new Error('Call encode first');
  const inputs = {
    targets: new ort.Tensor('int32', Int32Array.of(token), [1, 1]),
    target_length: new ort.Tensor('int32', Int32Array.of(1), [1]),
  };
  let result;
  try {
    result = await engine.sessions[1].run(
      { ...inputs, 'states.1': engine.state[0], 'onnx::Slice_3': engine.state[1] },
      ['outputs', 'states', '162'],
    );
  } finally {
    for (const tensor of Object.values(inputs)) disposeTensor(tensor);
  }
  disposeTensor(engine.prediction);
  for (const tensor of engine.state) disposeTensor(tensor);
  engine.prediction = result.outputs;
  engine.state = [result.states, result['162']];
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
      engine.blank = data.blank;
      const previous = engines.get(engineId);
      if (previous) await releaseEngine(previous);
      engines.set(engineId, engine);
      self.postMessage({ action: 'result', messageId });
      return;
    }
    const engine = requireEngine(engineId);
    if (action === 'encode') {
      const result = await encode(engine, data.features, data.frames);
      self.postMessage({ action: 'result', messageId, result }, [result.buffer]);
    } else if (action === 'joint') {
      const result = await joint(engine, data.frame);
      self.postMessage({ action: 'result', messageId, result }, [result.buffer]);
    } else if (action === 'predict') {
      await predict(engine, data.token);
      self.postMessage({ action: 'result', messageId });
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
