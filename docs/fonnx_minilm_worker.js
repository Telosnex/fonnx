import * as ort from 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.19.0/dist/ort.all.min.mjs';

let session = null;

// Ensure at least 1 and at most half the number of hardwareConcurrency.
// Testing showed using all cores was 15% slower than using half.
// Tested on MBA M2 with a value of 8 for navigator.hardwareConcurrency.
const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));

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
        if (action === 'loadModel' && modelArrayBuffer) {
            console.log('MiniLm loading model');
            session = await ort.InferenceSession.create(modelArrayBuffer, {
                executionProviders: ['wasm', 'cpu'],
            });
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
            console.time("Creating tensors");
            console.time("inputIdsTensor");
            const inputIdsTensor = new ort.Tensor('int64', toBigInt64Array(wordpieces), shape);
            console.timeEnd("inputIdsTensor");
            console.time("tokenTypeIdsTensor");
            const tokenTypeIdsTensor = new ort.Tensor('int64', new BigInt64Array(shape[0] * shape[1]).fill(0n), shape);
            console.timeEnd("tokenTypeIdsTensor");
            console.time("attentionMaskTensor");
            const attentionMaskTensor = new ort.Tensor('int64', new BigInt64Array(shape[0] * shape[1]).fill(1n), shape);
            console.timeEnd("attentionMaskTensor");
            console.timeEnd("Creating tensors");

            console.time("Inference");

            const results = await session.run({
                input_ids: inputIdsTensor,
                token_type_ids: tokenTypeIdsTensor,
                attention_mask: attentionMaskTensor,
            });
            console.timeEnd("Inference");
            console.time("Posting result");
            const embeddings = results.embeddings.data;
            const message = { messageId, action: 'inferenceResult', embeddings };
            self.postMessage(message);
            console.timeEnd("Posting result");
        }
    } catch (error) {
        self.postMessage({ messageId, action: 'error', error: error.message });
    }
};
