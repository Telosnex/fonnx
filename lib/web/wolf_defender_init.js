// The query of this module URL holds the fonnx webVersion (kiln
// ADR 002 D7). Each file that it loads gets the same query.
const query = new URL(import.meta.url).search;
const { FonnxWorkerRpc, fetchModel } = await import(`./fonnx_worker_rpc.js${query}`);

const rpc = new FonnxWorkerRpc(new URL(`./wolf_defender_worker.js${query}`, import.meta.url), 'wolf_defender');

window.fonnxWolfDefenderLoad = async (engineId, path) => {
  const model = await fetchModel(path, 'Wolf Defender');
  await rpc.request('load', { engineId, model }, [model]);
};

window.fonnxWolfDefenderRun = async (engineId, ids) =>
  (await rpc.request('run', { engineId, ids })).result;
window.fonnxWolfDefenderClose = (engineId) => rpc.request('close', { engineId });
