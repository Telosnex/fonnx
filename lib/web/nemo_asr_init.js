// The query of this module URL holds the fonnx webVersion (native_prebuilt
// ADR 002 D7). Each file that it loads gets the same query.
const query = new URL(import.meta.url).search;
const { FonnxWorkerRpc, fetchModel } = await import(`./fonnx_worker_rpc.js${query}`);

const rpc = new FonnxWorkerRpc(new URL(`./nemo_asr_worker.js${query}`, import.meta.url), 'nemo_asr');

window.fonnxNemoAsrLoad = async (engineId, kind, paths, blank) => {
  const models = await Promise.all(paths.map((path) => fetchModel(path, 'NemoAsr')));
  await rpc.request('load', { engineId, kind, models, blank }, models);
};

window.fonnxNemoAsrEncode = async (engineId, features, frames) =>
  (await rpc.request('encode', { engineId, features, frames })).result;
window.fonnxNemoAsrJoint = async (engineId, frame) =>
  (await rpc.request('joint', { engineId, frame })).result;
window.fonnxNemoAsrPredict = (engineId, token) => rpc.request('predict', { engineId, token });
window.fonnxNemoAsrClose = (engineId) => rpc.request('close', { engineId });
