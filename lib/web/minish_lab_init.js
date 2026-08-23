import { FonnxWorkerRpc, fetchModel } from './fonnx_worker_rpc.js';

const rpc = new FonnxWorkerRpc(
  new URL('./minish_lab_worker.js', import.meta.url),
  'minish-lab',
);
let modelPath = null;
let modelPromise = null;

async function load(path) {
  if (modelPath === path && modelPromise) return modelPromise;
  modelPath = path;
  modelPromise = fetchModel(path, 'MinishLab').then((modelArrayBuffer) =>
    rpc.request('loadModel', { modelArrayBuffer }, [modelArrayBuffer]),
  );
  return modelPromise;
}

window.minishLab = async (path, wordpieces) => {
  await load(path);
  return (await rpc.request('runInference', { wordpieces })).embeddings;
};
