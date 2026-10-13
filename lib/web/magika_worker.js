// The query of this Worker URL holds the fonnx webVersion (native_prebuilt
// ADR 002 D7). ORT and its Wasm files load with the same query, so a browser
// does not use a cached file of another version.
const query = new URL(import.meta.url).search;
// Messages that arrive while ORT loads have no handler yet. Keep them, and
// dispatch them again at the end of this module.
const earlyMessages = [];
self.onmessage = ({ data }) => earlyMessages.push(data);
const ort = await import(`./ort.min.mjs${query}`);

let session = null;

const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));
ort.env.wasm.wasmPaths = {
  mjs: new URL(`./ort-wasm-simd-threaded.mjs${query}`, import.meta.url).href,
  wasm: new URL(`./ort-wasm-simd-threaded.wasm${query}`, import.meta.url).href,
};

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

for (const data of earlyMessages.splice(0)) {
  self.dispatchEvent(new MessageEvent('message', { data }));
}
