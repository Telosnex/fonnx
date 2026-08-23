import * as ort from './ort.min.mjs';

let session = null;

const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));
ort.env.wasm.wasmPaths = new URL('./', import.meta.url).href;

self.onmessage = async e => {
    const { action, modelArrayBuffer, fileBytes, messageId } = e.data;
    try {
    if (e.data.protocolVersion !== 1) throw new Error('Unsupported FONNX Worker protocol');
        if (action === 'loadModel' && modelArrayBuffer) {
            console.log('Magika loading model');
            const nextSession = await ort.InferenceSession.create(modelArrayBuffer, {
                executionProviders: ['wasm'],
            });
            if (session) await session.release();
            session = nextSession;
            console.log('Magika model loaded');
            self.postMessage({ messageId, action: 'modelLoaded' });
        } else if (action === 'runInference') {
            if (!session) {
                console.error('Session does not exist');
                self.postMessage({ messageId, action: 'error', error: 'Session does not exist' });
                return;
            }
            if (!fileBytes) {
                console.error('fileBytes were not provided');
                self.postMessage({ messageId, action: 'error', error: 'File bytes were not provided' });
                return;
            }

            const float32Array = fileBytes instanceof Float32Array
            ? fileBytes
            : new Float32Array(fileBytes);

            const bytesTensor = new ort.Tensor('float32', float32Array, [1, float32Array.length]);
            let results;
            try {
                results = await session.run({ bytes: bytesTensor });
                const targetLabel = Float32Array.from(results.target_label.data);
                self.postMessage(
                    { messageId, action: 'inferenceResult', targetLabel },
                    [targetLabel.buffer],
                );
            } finally {
                bytesTensor.dispose();
                for (const tensor of Object.values(results || {})) tensor.dispose();
            }
        }
    } catch (error) {
        console.error('[magika_worker.js] An error occurred:', error.message);
        console.error('[magika_worker.js] Stack trace:', error.stack);
        self.postMessage({ messageId, action: 'error', error: error.toString() });
    }
};
