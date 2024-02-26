import * as ort from 'https://cdn.jsdelivr.net/npm/onnxruntime-web/dist/esm/ort.min.js';

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
    const { action, modelArrayBuffer, audioBytes, messageId } = e.data;
    try {
        if (action === 'loadModel' && modelArrayBuffer) {
            console.log('Whisper loading model');
            session = await ort.InferenceSession.create(modelArrayBuffer, {
                executionProviders: ['wasm', 'cpu'],
            });
            console.log('Whisper model loaded');
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
            // Prepare tensors and run the inference session
            const audioBytesFloat32 = new convertAudioBytesToFloats(audioBytes);
            const shape = [1, audioBytesFloat32.length];
            const audioStreamTensor = new ort.Tensor('float32', audioBytesFloat32, shape);
            const maxLengthTensor = new ort.Tensor('int32', [200], [1]);
            const minLengthTensor = new ort.Tensor('int32', [0], [1]);
            const numBeamsTensor = new ort.Tensor('int32', [2], [1]);
            const numReturnSequencesTensor = new ort.Tensor('int32', [1], [1]);
            const lengthPenaltyTensor = new ort.Tensor('float32', [1.0], [1]);
            const repetitionPenaltyTensor = new ort.Tensor('float32', [1.0], [1]);
            const logitsProcessorTensor = new ort.Tensor('int32', [0], [1]);
            const results = await session.run({
                audio_pcm: audioStreamTensor,
                max_length: maxLengthTensor,
                min_length: minLengthTensor,
                num_beams: numBeamsTensor,
                num_return_sequences: numReturnSequencesTensor,
                length_penalty: lengthPenaltyTensor,
                repetition_penalty: repetitionPenaltyTensor,
                logits_processor: logitsProcessorTensor
            });
            const transcript = results.str.cpuData[0];
            const message = { messageId, action: 'inferenceResult', transcript };
            self.postMessage(message);
        }
    } catch (error) {
        console.error('[whisper_worker.js] An error occurred:', error.message);
        console.error('[whisper_worker.js] Stack trace:', error.stack);
        self.postMessage({ messageId, action: 'error', error: error.toString() });
    }
};