importScripts("https://cdn.jsdelivr.net/npm/onnxruntime-web/dist/ort.all.min.js");

let session = null;

// Ensure at least 1 and at most half the number of hardeareConcurrency.
// Testing showed using all cores was 15% slower than using half.
// Tested on MBA M2 with a value of 8 for navigator.hardwareConcurrency.
const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));
ort.env.wasm.wasmPaths = "";

function convertAudioBytesToFloats(audioBytes) {
    // Assuming 'audioBytes' is a Uint8Array.
    // Initialize a Float32Array of half the size of 'audioBytes'
    // since we're combining every two bytes into one float.
    const audioData = new Float32Array(audioBytes.length / 2);

    // Create a DataView for handling the 16-bit short conversion.
    const dataView = new DataView(audioBytes.buffer, audioBytes.byteOffset, audioBytes.byteLength);

    for (let i = 0; i < audioData.length; i++) {
        // Combine two bytes to form a 16-bit integer value
        // 'true' in getUint16 denotes little-endian byte order.
        let valInt = dataView.getUint16(i * 2, true);

        // If the signed bit (bit 15) is set, convert 16-bit unsigned integer to a signed integer
        if (valInt >= 0x8000) {
            valInt = valInt - 0x10000;
        }

        // Normalize to the range [-1.0, 1.0] for Float32 representation
        audioData[i] = valInt / 32767.0;
    }

    return audioData;
}

self.onmessage = async e => {
    const { action, modelArrayBuffer, audioBytes, previousStateAsJsonString, messageId } = e.data;
    try {
        if (action === 'loadModel' && modelArrayBuffer) {
            console.log('SileroVad loading model');
            session = await ort.InferenceSession.create(modelArrayBuffer, {
                executionProviders: ['wasm', 'cpu'],
            });
            console.log('SileroVad model loaded');
            self.postMessage({ messageId, action: 'modelLoaded' });
        } else if (action === 'runInference') {
            if (!session) {
                console.error('Session does not exist');
                self.postMessage({ messageId, action: 'error', error: 'Session does not exist' });
                return;
            }
            if (!audioBytes) {
                console.error('audioBytes were not provided');
                self.postMessage({ messageId, action: 'error', error: 'Audio bytes were not provided' });
                return;
            }

            // Check for previous h and c
            const batchSize = 1;
            const stateSize = 2 * batchSize * 64;
            let h, c;
            const previousState = JSON.parse(previousStateAsJsonString);
            if (previousState != null && previousState.hn) {
                h = new Float32Array(previousState.hn);
            } else {
                h = new Float32Array(stateSize).fill(0);
            }
            if (previousState != null && previousState.cn) {
                c = new Float32Array(previousState.cn);
            } else {
                c = new Float32Array(stateSize).fill(0);
            }
            const hTensor = new ort.Tensor('float32', h, [2, 1, 64]);
            const cTensor = new ort.Tensor('float32', c, [2, 1, 64]);

            // Prepare tensors and run the inference session
            const audioBytesFloat32 = new convertAudioBytesToFloats(audioBytes);
            const shape = [1, audioBytesFloat32.length];
            const audioStreamTensor = new ort.Tensor('float32', audioBytesFloat32, shape);
            const sampleRateTensor = new ort.Tensor('int64', [16000], [1]);
            const results = await session.run({
                input: audioStreamTensor,
                sr: sampleRateTensor,
                h: hTensor,
                c: cTensor
            });
            let resultMap = {};

            // Loop through the results object to process each result tensor
            for (const [key, tensor] of Object.entries(results)) {
                // Cast down outputs to Array.
                //
                // They are Float32Arrays by default.
                //
                // However, JS objects don't transfer to Dart as Map<String, dynamic>.
                //
                // So the resultMap needs to be JSON.stringify'd to return to Dart.
                //
                // However, JSON.stringify will turn typed arrays into objects with
                // keys of indices and values of the array values.
                resultMap[key] = Array.from(tensor.data);
            }

            const resultMapAsJsonString = JSON.stringify(resultMap);
            const message = { messageId, action: 'inferenceResult', resultMapAsJsonString };
            self.postMessage(message);
        }
    } catch (error) {
        console.error('[silero_vad_worker.js] An error occurred:', error.message);
        console.error('[silero_vad_worker.js] Stack trace:', error.stack);
        self.postMessage({ messageId, action: 'error', error: error.toString() });
    }
};