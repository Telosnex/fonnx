import { FonnxWorkerRpc, fetchModel } from './fonnx_worker_rpc.js';

const rpc = new FonnxWorkerRpc(new URL('./pyannote_worker.js', import.meta.url), 'pyannote');
let modelPath = null;
let modelPromise = null;

async function load(path) {
  if (modelPath === path && modelPromise) return modelPromise;
  modelPath = path;
  modelPromise = fetchModel(path, 'Pyannote').then((modelArrayBuffer) =>
    rpc.request('loadModel', { modelArrayBuffer }, [modelArrayBuffer]),
  );
  return modelPromise;
}

window.pyannote = async (path, audioData) => {
  await load(path);
  return (await rpc.request('runInference', { audioData })).jsonEncoded;
};
