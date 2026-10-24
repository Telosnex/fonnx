// The query of this module URL holds the fonnx webVersion (kiln
// ADR 002 D7). Each file that it loads gets the same query.
const query = new URL(import.meta.url).search;
const { FonnxWorkerRpc, fetchModel } = await import(`./fonnx_worker_rpc.js${query}`);

const rpc = new FonnxWorkerRpc(new URL(`./sense_voice_worker.js${query}`, import.meta.url), 'sense_voice');

window.fonnxSenseVoiceLoad = async (engineId, path) => {
  const model = await fetchModel(path, 'SenseVoice');
  await rpc.request('load', { engineId, model }, [model]);
};

window.fonnxSenseVoiceRun = async (engineId, features, frames, language, textNorm) =>
  (await rpc.request('run', { engineId, features, frames, language, textNorm })).result;
window.fonnxSenseVoiceClose = (engineId) => rpc.request('close', { engineId });
