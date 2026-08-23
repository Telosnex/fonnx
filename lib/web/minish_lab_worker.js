import * as ort from './ort.min.mjs';

let session = null;

// Configure thread count similar to MiniLM worker – use half of logical cores but at least 1.
const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));
ort.env.wasm.wasmPaths = new URL('./', import.meta.url).href;

function toBigInt64Array(arr) {
  const buffer = new ArrayBuffer(arr.length * 8); // 8 bytes per int64
  const view = new BigInt64Array(buffer);
  for (let i = 0; i < arr.length; i++) {
    const value = arr[i];
    if (typeof value === 'bigint') {
      view[i] = value;
    } else if (typeof value === 'number') {
      view[i] = BigInt(Math.floor(value));
    } else {
      throw new Error(`Unsupported type at index ${i}: ${typeof value}`);
    }
  }
  return view;
}

self.onmessage = async (e) => {
  const { action, modelArrayBuffer, wordpieces, messageId } = e.data;
  try {
    if (e.data.protocolVersion !== 1) throw new Error('Unsupported FONNX Worker protocol');
    if (action === 'loadModel' && modelArrayBuffer) {
      console.log('MinishLab loading model');
      const nextSession = await ort.InferenceSession.create(modelArrayBuffer, {
                executionProviders: ['wasm'],
            });
            if (session) await session.release();
            session = nextSession;
      console.log('MinishLab model loaded');
      self.postMessage({ messageId, action: 'modelLoaded' });
    } else if (action === 'runInference') {
      if (!session) {
        self.postMessage({ messageId, action: 'error', error: 'Session does not exist' });
        return;
      }
      if (!wordpieces) {
        self.postMessage({ messageId, action: 'error', error: 'Wordpieces are not provided' });
        return;
      }

      // Model expects 1-D int64 input_ids and 1-D offsets (single zero).
      const inputIdsShape = [wordpieces.length];
      const inputIdsTensor = new ort.Tensor('int64', toBigInt64Array(wordpieces), inputIdsShape);

      // Offsets tensor is a single 0 (int64)
      const offsetsTensor = new ort.Tensor('int64', new BigInt64Array([0n]), [1]);

      let results;
      try {
        results = await session.run({
          input_ids: inputIdsTensor,
          offsets: offsetsTensor,
        });
        const embeddings = Float32Array.from(results.embeddings.data);
        self.postMessage(
          { messageId, action: 'inferenceResult', embeddings },
          [embeddings.buffer],
        );
      } finally {
        inputIdsTensor.dispose();
        offsetsTensor.dispose();
        for (const tensor of Object.values(results || {})) tensor.dispose();
      }
    }
  } catch (error) {
    self.postMessage({ messageId, action: 'error', error: error.message });
  }
};
