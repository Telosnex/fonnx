importScripts("https://cdn.jsdelivr.net/npm/onnxruntime-web/dist/ort.min.js");

let session = null;

ort.env.wasm.wasmPaths = "";

// Ensure at least 1 and at most half the number of hardwareConcurrency.
// Testing showed using all cores was 15% slower than using half.
// Tested on MBA M2 with a value of 8 for navigator.hardwareConcurrency.
const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));

self.onmessage = async e => {
    const { action, modelArrayBuffer, wordpieces, messageId } = e.data;
    try {
        if (action === 'loadModel' && modelArrayBuffer) {
            session = await ort.InferenceSession.create(modelArrayBuffer, {
                executionProviders: ['cpu'],
            });
            self.postMessage({ messageId, action: 'modelLoaded' });
        } else if (action === 'runInference') {
            try {
                if (!this.session) {
                    console.error("Model session not initialised");
                    return null;
                }

                // Setup the input tensors
                const maxLengthData = new ort.Tensor("int32", new Int32Array([200]), [1]);
                const minLengthData = new ort.Tensor("int32", new Int32Array([0]), [1]);
                const numBeamsData = new ort.Tensor("int32", new Int32Array([2]), [1]);
                const numReturnSequencesData = new ort.Tensor("int32", new Int32Array([1]), [1]);
                const lengthPenaltyData = new ort.Tensor("float32", new Float32Array([1.0]), [1]);
                const repetitionPenaltyData = new ort.Tensor("float32", new Float32Array([1.0]), [1]);

                // Convert the audio bytes to a tensor. Assuming audioBytes is a Uint8Array
                const audioStreamTensor = new ort.Tensor("uint8", audioBytes, [1, audioBytes.length]);

                // Define the input map
                const inputs = {
                    audio_stream: audioStreamTensor,
                    max_length: maxLengthData,
                    min_length: minLengthData,
                    num_beams: numBeamsData,
                    num_return_sequences: numReturnSequencesData,
                    length_penalty: lengthPenaltyData,
                    repetition_penalty: repetitionPenaltyData
                };

                // Define the output names
                const outputNames = ["str"];

                // Run the model
                const results = await this.session.run(inputs, outputNames);
                const output = results.str.data;
                // Assuming the output is non-null and has at least one element
                const transcript = output.length > 0 ? output[0][0] : null;

                return transcript;

            } catch (e) {
                console.error("Error in getTranscription: ", e);
                return null;
            }
        }
    } catch (error) {
        self.postMessage({ messageId, action: 'error', error: error.message });
    }
};