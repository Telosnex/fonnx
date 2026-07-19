import * as ort from 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.17.1/dist/esm/ort.min.js';

let session = null;

const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));
ort.env.wasm.wasmPaths = '';

const chunkSamples = 512;
const contextSamples = 64;
const stateSize = 2 * 1 * 128;

function convertAudioBytesToFloats(audioBytes) {
  const audioData = new Float32Array(audioBytes.length / 2);
  const dataView = new DataView(
    audioBytes.buffer,
    audioBytes.byteOffset,
    audioBytes.byteLength,
  );
  for (let i = 0; i < audioData.length; i++) {
    audioData[i] = dataView.getInt16(i * 2, true) / 32767.0;
  }
  return audioData;
}

function restore(values, length) {
  return Array.isArray(values) && values.length === length
    ? new Float32Array(values)
    : new Float32Array(length);
}

async function runInference(audioBytes, previousStateAsJsonString) {
  if (!audioBytes || audioBytes.length === 0 || audioBytes.length % 2 !== 0) {
    throw new Error('Audio must contain a non-empty, even number of PCM16 bytes');
  }
  const previous = JSON.parse(previousStateAsJsonString || '{}');
  let state = restore(previous.state, stateSize);
  let context = restore(previous.context, contextSamples);
  const audio = convertAudioBytesToFloats(audioBytes);
  const output = [];

  for (let offset = 0; offset < audio.length; offset += chunkSamples) {
    const chunk = new Float32Array(chunkSamples);
    chunk.set(audio.subarray(offset, Math.min(offset + chunkSamples, audio.length)));
    const input = new Float32Array(contextSamples + chunkSamples);
    input.set(context);
    input.set(chunk, contextSamples);
    const results = await session.run({
      input: new ort.Tensor('float32', input, [1, input.length]),
      state: new ort.Tensor('float32', state, [2, 1, 128]),
      // The model declares a scalar but also accepts this one-value tensor.
      sr: new ort.Tensor('int64', [16000], [1]),
    });
    output.push(results.output.data[0]);
    state = new Float32Array(results.stateN.data);
    context = chunk.slice(chunkSamples - contextSamples);
  }

  return JSON.stringify({
    output,
    state: Array.from(state),
    context: Array.from(context),
  });
}

self.onmessage = async (event) => {
  const {
    action,
    modelArrayBuffer,
    audioBytes,
    previousStateAsJsonString,
    messageId,
  } = event.data;
  try {
    if (action === 'loadModel' && modelArrayBuffer) {
      session = await ort.InferenceSession.create(modelArrayBuffer, {
        executionProviders: ['wasm', 'cpu'],
      });
      self.postMessage({ messageId, action: 'modelLoaded' });
      return;
    }
    if (action === 'runInference') {
      if (!session) throw new Error('Session does not exist');
      const resultMapAsJsonString = await runInference(
        audioBytes,
        previousStateAsJsonString,
      );
      self.postMessage({
        messageId,
        action: 'inferenceResult',
        resultMapAsJsonString,
      });
    }
  } catch (error) {
    console.error('[silero_vad_worker.js]', error);
    self.postMessage({
      messageId,
      action: 'error',
      error: error.toString(),
    });
  }
};
