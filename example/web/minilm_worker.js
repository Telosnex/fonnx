import * as ort from 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.17.1/dist/esm/ort.min.js';

let session = null;

// Ensure at least 1 and at most half the number of hardwareConcurrency.
// Testing showed using all cores was 15% slower than using half.
// Tested on MBA M2 with a value of 8 for navigator.hardwareConcurrency.
const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));

self.onmessage = async e => {
    const { action, modelArrayBuffer, wordpieces, messageId } = e.data;
    try {
        if (action === 'loadModel' && modelArrayBuffer) {
            console.log('MiniLm loading model');
            session = await ort.InferenceSession.create(modelArrayBuffer, {
                executionProviders: ['wasm', 'cpu'],
            });
            console.log('MiniLm model loaded');
            self.postMessage({ messageId, action: 'modelLoaded' });
        } else if (action === 'runInference') {
            if (!session) {
                console.error('Session does not exist');
                self.postMessage({ messageId, action: 'error', error: 'Session does not exist' });
                return;
            }
            if (!wordpieces) {
                console.error('Wordpieces are not provided');
                self.postMessage({ messageId, action: 'error', error: 'Wordpieces are not provided' });
                return;
            }
            // Prepare tensors and run the inference session
            const shape = [1, wordpieces.length];
            const inputIdsTensor = new ort.Tensor('int64', wordpieces.map(x => BigInt(x)), shape);
            const tokenTypeIdsTensor = new ort.Tensor('int64', new BigInt64Array(shape[0] * shape[1]).fill(0n), shape);
            const attentionMaskTensor = new ort.Tensor('int64', new BigInt64Array(shape[0] * shape[1]).fill(1n), shape);

            const results = await session.run({
                input_ids: inputIdsTensor,
                token_type_ids: tokenTypeIdsTensor,
                attention_mask: attentionMaskTensor,
            });
            const embeddings = results.embeddings.data;
            const message = { messageId, action: 'inferenceResult', embeddings };
            self.postMessage(message);
        }
    } catch (error) {
        self.postMessage({ messageId, action: 'error', error: error.message });
    }
};