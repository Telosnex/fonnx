let magikaCachedModelPath = null;
let magikaCachedModelPromise = null;
const magikaWorker = new Worker(new URL('fonnx_magika_worker.js', import.meta.url), { type: 'module' });
const magikaMessageIdToResolve = new Map();
const magikaMessageIdToReject = new Map();

magikaWorker.onmessage = function (e) {
  const { messageId, action, targetLabel, error } = e.data;
  if (action === "inferenceResult" && magikaMessageIdToResolve.has(messageId)) {
    magikaMessageIdToResolve.get(messageId)(targetLabel);
    cleanup(messageId);
  } else if (action === "error" && magikaMessageIdToReject.has(messageId)) {
    magikaMessageIdToReject.get(messageId)(new Error(error));
    cleanup(messageId);
  } else if (action === "modelLoaded") {
    // no-op, one-time message handler will handle
  } else {
    console.error('[magikaInferenceAsyncJs] unexpected message', e.data);
  }
};

function cleanup(messageId) {
  magikaMessageIdToResolve.delete(messageId);
  magikaMessageIdToReject.delete(messageId);
}

function magikaInferenceAsyncJs(modelPath, fileBytes) {
  return new Promise(async (resolve, reject) =>  {
    const messageId = Math.random().toString(36).substring(2);
    magikaMessageIdToResolve.set(messageId, resolve);
    magikaMessageIdToReject.set(messageId, reject);

    if (magikaCachedModelPath !== modelPath || !magikaCachedModelPromise) {
      magikaCachedModelPath = modelPath;
      magikaCachedModelPromise = fetch(modelPath)
        .then(response => response.arrayBuffer())
        .then(modelArrayBuffer => {
          return new Promise((resolveLoad) => {
            // Post the load model message to the worker.
            magikaWorker.postMessage({
              action: 'loadModel',
              modelArrayBuffer,
              messageId
            }, [modelArrayBuffer]);

            // Setup a one-time message listener for the "modelLoaded" message.
            const onModelLoaded = (e) => {
              if (e.data.action === 'modelLoaded' && e.data.messageId === messageId) {
                magikaWorker.removeEventListener('message', onModelLoaded);
                resolveLoad();
              }
            };
            magikaWorker.addEventListener('message', onModelLoaded);
          });
        })
        .catch(reject);
    }

    magikaCachedModelPromise.then(() => {
      // Once the model is loaded, send the run inference message to the worker.
      magikaWorker.postMessage({
        action: 'runInference',
        fileBytes,
        messageId
      });
    }).catch(reject);
  });
}

window.magikaInferenceAsyncJs = magikaInferenceAsyncJs;