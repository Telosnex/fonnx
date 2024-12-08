import * as ort from 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.17.1/dist/esm/ort.min.js';

let session = null;

// Ensure at least 1 and at most half the number of hardwareConcurrency
const cores = navigator.hardwareConcurrency;
ort.env.wasm.numThreads = Math.max(1, Math.min(Math.floor(cores / 2), cores));
ort.env.wasm.wasmPaths = "";

// Constants for Pyannote processing
const SAMPLE_RATE = 16000;
const DURATION = 160000; // 10 seconds window
const NUM_SPEAKERS = 3;

function sampleToFrame(samples) {
    return Math.floor((samples - 721) / 270);
}

function frameToSample(frames) {
    return (frames * 270) + 721;
}

function createSlidingWindows(audioData, windowSize, stepSize) {
    const windows = [];
    let start = 0;

    while (start <= audioData.length - windowSize) {
        windows.push({
            size: windowSize,
            data: audioData.slice(start, start + windowSize)
        });
        start += stepSize;
    }

    // Handle last window if needed
    if (audioData.length < windowSize || (audioData.length - windowSize) % stepSize > 0) {
        const lastWindow = audioData.slice(start);
        const lastWindowSize = lastWindow.length;

        if (lastWindow.length < windowSize) {
            const paddedWindow = new Float32Array(windowSize);
            paddedWindow.set(lastWindow);
            windows.push({
                size: lastWindowSize,
                data: paddedWindow
            });
        } else {
            windows.push({
                size: lastWindowSize,
                data: lastWindow
            });
        }
    }

    return windows;
}

function processOutputData(logits) {
    const frameOutputs = [];
    const numCompleteFrames = Math.floor(logits.length / 7);

    for (let frame = 0; frame < numCompleteFrames; frame++) {
        const i = frame * 7;
        const probs = logits.slice(i, i + 7).map(x => Math.exp(x));
        
        const speakerProbs = new Array(NUM_SPEAKERS);
        speakerProbs[0] = probs[1] + probs[4] + probs[5]; // spk1
        speakerProbs[1] = probs[2] + probs[4] + probs[6]; // spk2
        speakerProbs[2] = probs[3] + probs[5] + probs[6]; // spk3
        
        frameOutputs.push(speakerProbs);
    }

    return frameOutputs;
}

function generatePermutations(n) {
    if (n === 1) return [[0]];
    
    const result = [];
    for (let i = 0; i < n; i++) {
        const subPerms = generatePermutations(n - 1);
        for (const perm of subPerms) {
            const newPerm = [i, ...perm.map(x => x >= i ? x + 1 : x)];
            result.push(newPerm);
        }
    }
    return result;
}

function transpose(matrix) {
    if (matrix.length === 0) return [];
    const rows = matrix.length;
    const cols = matrix[0].length;
    
    return Array.from({ length: cols }, (_, j) => 
        Array.from({ length: rows }, (_, i) => matrix[i][j])
    );
}

function reorder(x, y) {
    const perms = generatePermutations(NUM_SPEAKERS);
    const yTransposed = transpose(y);
    
    let minDiff = Infinity;
    let bestPerm = y;
    
    for (const perm of perms) {
        const permuted = Array.from({ length: y.length }, (_, i) => 
            Array.from({ length: NUM_SPEAKERS }, (_, j) => yTransposed[perm[j]][i])
        );
        
        let diff = 0;
        for (let i = 0; i < x.length; i++) {
            for (let j = 0; j < NUM_SPEAKERS; j++) {
                diff += Math.abs(x[i][j] - permuted[i][j]);
            }
        }
        
        if (diff < minDiff) {
            minDiff = diff;
            bestPerm = permuted;
        }
    }
    
    return bestPerm;
}

function reorderAndBlend(overlapChunk, newFrames) {
    const reorderedFrames = reorder(overlapChunk, newFrames);
    
    // Blend overlapping sections
    for (let i = 0; i < overlapChunk.length; i++) {
        for (let j = 0; j < NUM_SPEAKERS; j++) {
            reorderedFrames[i][j] = (reorderedFrames[i][j] + overlapChunk[i][j]) / 2;
        }
    }
    
    return reorderedFrames;
}

self.onmessage = async e => {
    const { action, modelArrayBuffer, audioData, messageId } = e.data;
    try {
        if (action === 'loadModel' && modelArrayBuffer) {
            console.log('Pyannote loading model');
            session = await ort.InferenceSession.create(modelArrayBuffer, {
                executionProviders: ['wasm', 'cpu'],
            });
            console.log('Pyannote model loaded');
            self.postMessage({ messageId, action: 'modelLoaded' });
        } else if (action === 'runInference') {
            if (!session) {
                console.error('Session does not exist');
                self.postMessage({ messageId, action: 'error', error: 'Session does not exist' });
                return;
            }
            if (!audioData) {
                console.error('Audio data was not provided');
                self.postMessage({ messageId, action: 'error', error: 'Audio data was not provided' });
                return;
            }

            const step = Math.min(DURATION / 2, Math.floor(0.9 * DURATION));
            const results = [];
            const isActive = new Array(NUM_SPEAKERS).fill(false);
            const startSamples = new Array(NUM_SPEAKERS).fill(0);
            let currentSamples = 721;

            // Calculate overlap
            const overlap = sampleToFrame(DURATION - step);
            let overlapChunk = Array.from({ length: overlap }, 
                () => new Array(NUM_SPEAKERS).fill(0));

            // Create sliding windows
            const windows = createSlidingWindows(audioData, DURATION, step);

            for (let windowIndex = 0; windowIndex < windows.length; windowIndex++) {
                const { size: windowSize, data: windowData } = windows[windowIndex];

                // Prepare input tensor
                const shape = [1, 1, windowData.length];
                const inputTensor = new ort.Tensor('float32', windowData, shape);

                // Run inference
                const outputs = await session.run({
                    'input_values': inputTensor
                });

                // Process outputs
                let frameOutputs = processOutputData(Array.from(outputs.logits.data));

                // Handle overlapping
                if (windowIndex > 0) {
                    frameOutputs = reorderAndBlend(overlapChunk, frameOutputs);
                }

                if (windowIndex < windows.length - 1) {
                    overlapChunk = frameOutputs.slice(-overlap);
                    frameOutputs = frameOutputs.slice(0, -overlap);
                } else {
                    frameOutputs = frameOutputs.slice(0, 
                        Math.min(frameOutputs.length, sampleToFrame(windowSize)));
                }

                // Track speaker segments
                for (const probs of frameOutputs) {
                    currentSamples += 270;
                    for (let speaker = 0; speaker < NUM_SPEAKERS; speaker++) {
                        if (isActive[speaker]) {
                            if (probs[speaker] < 0.5) {
                                results.push({
                                    speaker,
                                    start: startSamples[speaker] / SAMPLE_RATE,
                                    stop: currentSamples / SAMPLE_RATE
                                });
                                isActive[speaker] = false;
                            }
                        } else if (probs[speaker] > 0.5) {
                            startSamples[speaker] = currentSamples;
                            isActive[speaker] = true;
                        }
                    }
                }
            }

            // Handle any remaining active speakers
            for (let speaker = 0; speaker < NUM_SPEAKERS; speaker++) {
                if (isActive[speaker]) {
                    results.push({
                        speaker,
                        start: startSamples[speaker] / SAMPLE_RATE,
                        stop: currentSamples / SAMPLE_RATE
                    });
                }
            }

            self.postMessage({ messageId, action: 'inferenceResult', results });
        }
    } catch (error) {
        console.error('[pyannote_worker.js] An error occurred:', error.message);
        console.error('[pyannote_worker.js] Stack trace:', error.stack);
        self.postMessage({ messageId, action: 'error', error: error.toString() });
    }
};