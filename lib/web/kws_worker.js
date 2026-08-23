import * as ort from './ort.min.mjs';

const cores = navigator.hardwareConcurrency || 1;
ort.env.wasm.numThreads = Math.max(1, Math.floor(cores / 2));
ort.env.wasm.wasmPaths = new URL('./', import.meta.url).href;

const engines = new Map();
const leftContexts = [64, 32, 16, 8, 16, 32];
const keyDimensions = [128, 128, 128, 256, 128, 128];
const valueDimensions = [48, 48, 48, 96, 48, 48];
const convolutionKernels = [31, 31, 15, 15, 15, 31];

const stateInputNames = [];
const stateOutputNames = [];
for (let layer = 0; layer < 6; layer++) {
  stateInputNames.push(
    `cached_key_${layer}`,
    `cached_nonlin_attn_${layer}`,
    `cached_val1_${layer}`,
    `cached_val2_${layer}`,
    `cached_conv1_${layer}`,
    `cached_conv2_${layer}`,
  );
  stateOutputNames.push(
    `new_cached_key_${layer}`,
    `new_cached_nonlin_attn_${layer}`,
    `new_cached_val1_${layer}`,
    `new_cached_val2_${layer}`,
    `new_cached_conv1_${layer}`,
    `new_cached_conv2_${layer}`,
  );
}
stateInputNames.push('embed_states', 'processed_lens');
stateOutputNames.push('new_embed_states', 'new_processed_lens');

function zeros(shape, type = 'float32') {
  const size = shape.reduce((total, dimension) => total * dimension, 1);
  const data = type === 'int64' ? new BigInt64Array(size) : new Float32Array(size);
  return new ort.Tensor(type, data, shape);
}

function initialStates() {
  const states = [];
  for (let layer = 0; layer < 6; layer++) {
    const left = leftContexts[layer];
    const key = keyDimensions[layer];
    const value = valueDimensions[layer];
    const convolution = Math.floor(convolutionKernels[layer] / 2);
    states.push(
      zeros([left, 1, key]),
      zeros([1, 1, left, 96]),
      zeros([left, 1, value]),
      zeros([left, 1, value]),
      zeros([1, 128, convolution]),
      zeros([1, 128, convolution]),
    );
  }
  states.push(zeros([1, 128, 3, 19]), zeros([1], 'int64'));
  return states;
}

function disposeTensor(tensor) {
  if (tensor && typeof tensor.dispose === 'function') tensor.dispose();
}

function reset(engine) {
  for (const state of engine.states || []) disposeTensor(state);
  engine.states = initialStates();
}

function requireEngine(engineId) {
  const engine = engines.get(engineId);
  if (!engine) throw new Error(`Unknown KWS engine: ${engineId}`);
  return engine;
}

async function releaseEngine(engine) {
  for (const state of engine.states || []) disposeTensor(state);
  await engine.encoder?.release();
  await engine.decoder?.release();
  await engine.joiner?.release();
}

async function createEngine(data) {
  const options = { executionProviders: ['wasm'] };
  const engine = { encoder: null, decoder: null, joiner: null, states: [] };
  try {
    engine.encoder = await ort.InferenceSession.create(data.encoder, options);
    engine.decoder = await ort.InferenceSession.create(data.decoder, options);
    engine.joiner = await ort.InferenceSession.create(data.joiner, options);
    reset(engine);
    return engine;
  } catch (error) {
    await releaseEngine(engine);
    throw error;
  }
}

self.onmessage = async ({ data }) => {
  const { action, messageId, engineId } = data;
  try {
    if (data.protocolVersion !== 1) throw new Error('Unsupported FONNX Worker protocol');
    if (action === 'load') {
      const engine = await createEngine(data);
      const previous = engines.get(engineId);
      if (previous) await releaseEngine(previous);
      engines.set(engineId, engine);
      self.postMessage({ action: 'result', messageId });
      return;
    }

    const engine = requireEngine(engineId);
    if (action === 'encoder') {
      const input = new ort.Tensor('float32', data.features, [1, 45, 80]);
      const feeds = { x: input };
      for (let i = 0; i < stateInputNames.length; i++) {
        feeds[stateInputNames[i]] = engine.states[i];
      }
      let result;
      try {
        result = await engine.encoder.run(feeds);
      } finally {
        input.dispose();
      }
      for (const state of engine.states) disposeTensor(state);
      engine.states = stateOutputNames.map(name => result[name]);
      const output = Float32Array.from(result.encoder_out.data);
      disposeTensor(result.encoder_out);
      self.postMessage({ action: 'result', messageId, result: output }, [output.buffer]);
    } else if (action === 'decoder') {
      const values = JSON.parse(data.contextsJson).map(BigInt);
      const contexts = new BigInt64Array(values);
      const batch = contexts.length / 2;
      const input = new ort.Tensor('int64', contexts, [batch, 2]);
      let result;
      try {
        result = await engine.decoder.run({ y: input });
      } finally {
        input.dispose();
      }
      const output = Float32Array.from(result.decoder_out.data);
      disposeTensor(result.decoder_out);
      self.postMessage({ action: 'result', messageId, result: output }, [output.buffer]);
    } else if (action === 'joiner') {
      const batch = data.encoderVectors.length / 320;
      const encoderInput = new ort.Tensor('float32', data.encoderVectors, [batch, 320]);
      const decoderInput = new ort.Tensor('float32', data.decoderVectors, [batch, 320]);
      let result;
      try {
        result = await engine.joiner.run({
          encoder_out: encoderInput,
          decoder_out: decoderInput,
        });
      } finally {
        encoderInput.dispose();
        decoderInput.dispose();
      }
      const output = Float32Array.from(result.logit.data);
      disposeTensor(result.logit);
      self.postMessage({ action: 'result', messageId, result: output }, [output.buffer]);
    } else if (action === 'reset') {
      reset(engine);
      self.postMessage({ action: 'result', messageId });
    } else if (action === 'close') {
      await releaseEngine(engine);
      engines.delete(engineId);
      self.postMessage({ action: 'result', messageId });
    } else {
      throw new Error(`Unknown action: ${action}`);
    }
  } catch (error) {
    self.postMessage({
      action: 'error',
      messageId,
      error: `${error.message}\n${error.stack || ''}`,
    });
  }
};
