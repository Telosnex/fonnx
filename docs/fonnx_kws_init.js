const worker = new Worker(new URL('./fonnx_kws_worker.js', import.meta.url), { type: 'module' });
const pending = new Map();
let nextMessageId = 0;

worker.onmessage = ({ data }) => {
  const request = pending.get(data.messageId);
  if (!request) return;
  pending.delete(data.messageId);
  if (data.action === 'error') {
    request.reject(new Error(data.error));
  } else {
    request.resolve(data.result);
  }
};

function request(action, payload = {}) {
  return new Promise((resolve, reject) => {
    const messageId = `kws-${nextMessageId++}`;
    pending.set(messageId, { resolve, reject });
    worker.postMessage({ action, messageId, ...payload });
  });
}

async function fetchModel(path) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`Unable to fetch KWS model ${path}: ${response.status}`);
  return response.arrayBuffer();
}

window.fonnxKwsLoad = async (engineId, encoderPath, decoderPath, joinerPath) => {
  const [encoder, decoder, joiner] = await Promise.all([
    fetchModel(encoderPath),
    fetchModel(decoderPath),
    fetchModel(joinerPath),
  ]);
  return request('load', { engineId, encoder, decoder, joiner });
};

window.fonnxKwsEncoder = (engineId, features) =>
  request('encoder', { engineId, features });

window.fonnxKwsDecoder = (engineId, contextsJson) =>
  request('decoder', { engineId, contextsJson });

window.fonnxKwsJoiner = (engineId, encoderVectors, decoderVectors) =>
  request('joiner', { engineId, encoderVectors, decoderVectors });

window.fonnxKwsReset = (engineId) => request('reset', { engineId });
window.fonnxKwsClose = (engineId) => request('close', { engineId });
