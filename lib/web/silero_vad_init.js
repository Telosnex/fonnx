// The query of this module URL holds the fonnx webVersion (native_prebuilt
// ADR 002 D7). Each file that it loads gets the same query.
const query = new URL(import.meta.url).search;
const { FonnxWorkerRpc, fetchModel } = await import(`./fonnx_worker_rpc.js${query}`);

const rpc = new FonnxWorkerRpc(
  new URL(`./silero_vad_worker.js${query}`, import.meta.url),
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
