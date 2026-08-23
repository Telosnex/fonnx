import { FonnxWorkerRpc, fetchModel } from './fonnx_worker_rpc.js';

const rpc = new FonnxWorkerRpc(new URL('./minilm_worker.js', import.meta.url), 'minilm');
let modelPath = null;
let modelPromise = null;

async function load(path) {
  if (modelPath === path && modelPromise) return modelPromise;
  modelPath = path;
  modelPromise = fetchModel(path, 'MiniLM').then((modelArrayBuffer) =>
    rpc.request('loadModel', { modelArrayBuffer }, [modelArrayBuffer]),
  );
  return modelPromise;
}

window.miniLmL6V2 = async (path, wordpieces) => {
  await load(path);
  return (await rpc.request('runInference', { wordpieces })).embeddings;
};
