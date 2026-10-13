// The query of this module URL holds the fonnx webVersion (native_prebuilt
// ADR 002 D7). Each file that it loads gets the same query.
const query = new URL(import.meta.url).search;
const { FonnxWorkerRpc, fetchModel } = await import(`./fonnx_worker_rpc.js${query}`);

const rpc = new FonnxWorkerRpc(new URL(`./whisper_worker.js${query}`, import.meta.url), 'whisper');

window.fonnxWhisperLoad = async (engineId, encoderPath, decoderPath, layers, heads) => {
  const [encoder, decoder] = await Promise.all([
    fetchModel(encoderPath, 'Whisper encoder'),
    fetchModel(decoderPath, 'Whisper decoder'),
  ]);
  await rpc.request('load', { engineId, encoder, decoder, layers, heads }, [encoder, decoder]);
};

window.fonnxWhisperEncode = (engineId, features, batch) =>
  rpc.request('encode', { engineId, features, batch });
window.fonnxWhisperDecode = async (engineId, tokens, length, parents) =>
  (await rpc.request('decode', { engineId, tokens, length, parents })).result;
window.fonnxWhisperClose = (engineId) => rpc.request('close', { engineId });
