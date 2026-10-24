// The query of this module URL holds the fonnx webVersion (kiln
// ADR 002 D7). Each file that it loads gets the same query.
const query = new URL(import.meta.url).search;
const { FonnxWorkerRpc } = await import(`./fonnx_worker_rpc.js${query}`);

// One Worker runs every Kokoro engine of the page: the phonemizer, the
// chunking and both ORT stages (fonnx ADR 002 D10).
const rpc = new FonnxWorkerRpc(new URL(`./kokoro_worker.js${query}`, import.meta.url), 'kokoro');

// request: JSON of the bundle URLs and the chunk policy.
window.fonnxKokoroLoad = (engineId, request) => rpc.request('load', { engineId, request });
window.fonnxKokoroBegin = (engineId, text, voice, speed, normalize) =>
  rpc.request('begin', { engineId, text, voice, speed, normalize });
// Resolves to { samples, isFinal, phonemes }, or null after the last chunk.
window.fonnxKokoroNext = async (engineId) => (await rpc.request('next', { engineId })).result;
window.fonnxKokoroCancel = (engineId) => rpc.request('cancel', { engineId });
window.fonnxKokoroClose = (engineId) => rpc.request('close', { engineId });
