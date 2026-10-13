// The query of this module URL holds the fonnx webVersion (native_prebuilt
// ADR 002 D7). Each file that it loads gets the same query.
const query = new URL(import.meta.url).search;
const { FonnxWorkerRpc, fetchModel } = await import(`./fonnx_worker_rpc.js${query}`);

const rpc = new FonnxWorkerRpc(
  new URL(`./futo_swipe_worker.js${query}`, import.meta.url),
  'futo-swipe',
);

async function fetchText(path, label) {
  const response = await fetch(path);
  if (!response.ok) {
    throw new Error(`Unable to fetch ${label} ${path}: HTTP ${response.status}`);
  }
  return response.text();
}

window.fonnxFutoSwipeLoad = async (
  engineId,
  encoderPath,
  decoderPath,
  contextPath,
  embeddingsPath,
  vocabularyPath,
  scoringPath,
) => {
  const [encoder, decoder, context, embeddings, vocabulary, scoring] =
    await Promise.all([
      fetchModel(encoderPath, 'FUTO Swipe encoder'),
      fetchModel(decoderPath, 'FUTO Swipe decoder'),
      fetchModel(contextPath, 'FUTO ContextLM'),
      fetchModel(embeddingsPath, 'FUTO ContextLM embeddings'),
      fetchText(vocabularyPath, 'FUTO ContextLM vocabulary'),
      fetchText(scoringPath, 'FUTO Swipe scoring'),
    ]);
  const { result } = await rpc.request(
    'load',
    { engineId, encoder, decoder, context, embeddings },
    [encoder, decoder, context, embeddings],
  );
  return { ...result, vocabulary, scoring };
};

window.fonnxFutoSwipeEncoder = async (engineId, features, layoutKeys, layoutMask) =>
  (await rpc.request('encoder', { engineId, features, layoutKeys, layoutMask })).result;
window.fonnxFutoSwipeDecoder = async (engineId, features) =>
  (await rpc.request('decoder', { engineId, features })).result;
window.fonnxFutoSwipeContext = async (engineId, tokenIds, hashBuckets) =>
  (await rpc.request('context', { engineId, tokenIds, hashBuckets })).result;
window.fonnxFutoSwipeClose = (engineId) => rpc.request('close', { engineId });
