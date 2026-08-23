import { FonnxWorkerRpc, fetchModel } from './fonnx_worker_rpc.js';

const rpc = new FonnxWorkerRpc(new URL('./kws_worker.js', import.meta.url), 'kws');

window.fonnxKwsLoad = async (engineId, encoderPath, decoderPath, joinerPath) => {
  const [encoder, decoder, joiner] = await Promise.all([
    fetchModel(encoderPath, 'KWS encoder'),
    fetchModel(decoderPath, 'KWS decoder'),
    fetchModel(joinerPath, 'KWS joiner'),
  ]);
  await rpc.request('load', { engineId, encoder, decoder, joiner });
};

window.fonnxKwsEncoder = async (engineId, features) =>
  (await rpc.request('encoder', { engineId, features })).result;
window.fonnxKwsDecoder = async (engineId, contextsJson) =>
  (await rpc.request('decoder', { engineId, contextsJson })).result;
window.fonnxKwsJoiner = async (engineId, encoderVectors, decoderVectors) =>
  (await rpc.request('joiner', { engineId, encoderVectors, decoderVectors })).result;
window.fonnxKwsReset = (engineId) => rpc.request('reset', { engineId });
window.fonnxKwsClose = (engineId) => rpc.request('close', { engineId });
