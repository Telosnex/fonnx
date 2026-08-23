import { FonnxWorkerRpc, fetchModel } from './fonnx_worker_rpc.js';

const rpc = new FonnxWorkerRpc(
  new URL('./silero_vad_worker.js', import.meta.url),
  'silero-vad',
);
let modelPath = null;
let modelPromise = null;

async function load(path) {
  if (modelPath === path && modelPromise) return modelPromise;
  modelPath = path;
  modelPromise = fetchModel(path, 'Silero VAD').then((modelArrayBuffer) =>
    rpc.request('loadModel', { modelArrayBuffer }, [modelArrayBuffer]),
  );
  return modelPromise;
}

window.sileroVad = async (path, audioBytes, previousStateAsJsonString) => {
  await load(path);
  return (
    await rpc.request('runInference', {
      audioBytes,
      previousStateAsJsonString,
    })
  ).resultMapAsJsonString;
};
