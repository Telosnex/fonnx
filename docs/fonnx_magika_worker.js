import * as ort from 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.17.1/dist/esm/ort.min.js';

let session = null;

const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));
ort.env.wasm.wasmPaths = "";

self.onmessage = async e => {
    const { action, modelArrayBuffer, fileBytes, messageId } = e.data;
    try {
        if (action === 'loadModel' && modelArrayBuffer) {
            console.log('Magika loading model');
            session = await ort.InferenceSession.create(modelArrayBuffer, {
                executionProviders: ['wasm', 'cpu'],
            });
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

            console.log('Magika running inference');
            const bytesTensor = new ort.Tensor('float32', fileBytes, [1, fileBytes.length]);
            const results = await session.run({ bytes: bytesTensor });
            const targetLabel = results['target_label'].data;
            const message = { messageId, action: 'inferenceResult', targetLabel };
            self.postMessage(message);
        }
    } catch (error) {
        console.error('[magika_worker.js] An error occurred:', error.message);
        console.error('[magika_worker.js] Stack trace:', error.stack);
        self.postMessage({ messageId, action: 'error', error: error.toString() });
    }
};