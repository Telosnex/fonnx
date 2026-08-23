import { FonnxWorkerRpc, fetchModel } from './fonnx_worker_rpc.js';

const rpc = new FonnxWorkerRpc(new URL('./magika_worker.js', import.meta.url), 'magika');
let modelPath = null;
let modelPromise = null;

async function load(path) {
  if (modelPath === path && modelPromise) return modelPromise;
  modelPath = path;
  modelPromise = fetchModel(path, 'Magika').then((modelArrayBuffer) =>
    rpc.request('loadModel', { modelArrayBuffer }, [modelArrayBuffer]),
  );
  return modelPromise;
}

window.magikaInferenceAsyncJs = async (path, fileBytes) => {
  await load(path);
  return (await rpc.request('runInference', { fileBytes })).targetLabel;
};
