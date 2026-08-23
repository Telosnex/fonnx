import * as ort from './ort.min.mjs';

let session = null;

// Ensure at least 1 and at most half the number of hardwareConcurrency.
// Testing showed using all cores was 15% slower than using half.
// Tested on MBA M2 with a value of 8 for navigator.hardwareConcurrency.
const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));
ort.env.wasm.wasmPaths = new URL('./', import.meta.url).href;

function toBigInt64Array(wordpieces) {
    // Create a buffer with the correct size
    const buffer = new ArrayBuffer(wordpieces.length * 8); // 8 bytes per BigInt64
    const view = new BigInt64Array(buffer);

    for (let i = 0; i < wordpieces.length; i++) {
        const value = wordpieces[i];
        // console.log(`Original value at index ${i}:`, value, "of type", typeof value);

        if (typeof value === 'bigint') {
            view[i] = value;
        } else if (typeof value === 'number') {
            view[i] = BigInt(Math.floor(value)); // Ensure integer
        } else {
            throw new Error(`Unsupported type at index ${i}: ${typeof value}`);
        }

        // console.log(`Converted value at index ${i}:`, view[i], "of type", typeof view[i]);
    }

    return view;
}

self.onmessage = async e => {
    const { action, modelArrayBuffer, wordpieces, messageId } = e.data;
    try {
    if (e.data.protocolVersion !== 1) throw new Error('Unsupported FONNX Worker protocol');
        if (action === 'loadModel' && modelArrayBuffer) {
            console.log('MiniLm loading model');
            const nextSession = await ort.InferenceSession.create(modelArrayBuffer, {
                executionProviders: ['wasm'],
            });
            if (session) await session.release();
            session = nextSession;
            console.log('MiniLm model loaded');
            self.postMessage({ messageId, action: 'modelLoaded' });
            console.log('New log line appearing');
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
            const inputIdsTensor = new ort.Tensor('int64', toBigInt64Array(wordpieces), shape);
            const tokenTypeIdsTensor = new ort.Tensor('int64', new BigInt64Array(shape[0] * shape[1]).fill(0n), shape);
            const attentionMaskTensor = new ort.Tensor('int64', new BigInt64Array(shape[0] * shape[1]).fill(1n), shape);
            let results;
            try {
                results = await session.run({
                    input_ids: inputIdsTensor,
                    token_type_ids: tokenTypeIdsTensor,
                    attention_mask: attentionMaskTensor,
                });
                const embeddings = Float32Array.from(results.embeddings.data);
                self.postMessage(
                    { messageId, action: 'inferenceResult', embeddings },
                    [embeddings.buffer],
                );
            } finally {
                inputIdsTensor.dispose();
                tokenTypeIdsTensor.dispose();
                attentionMaskTensor.dispose();
                for (const tensor of Object.values(results || {})) tensor.dispose();
            }
        }
    } catch (error) {
        self.postMessage({ messageId, action: 'error', error: error.message });
    }
};
