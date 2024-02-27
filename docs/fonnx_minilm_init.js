// Get the number of logical processors available.
const miniLmCores = navigator.hardwareConcurrency;

let cachedMiniLmModelPath = null;
let cachedMiniLmModelPromise = null;

const miniLmWorker = new Worker('fonnx_minilm_worker.js', { type: 'module' });

// Simplified logs for brevity; can be extended to log each property if required.
miniLmWorker.onmessage = function (e) {
  const { messageId, action, embeddings, error } = e.data;
  if (action === "inferenceResult" && miniLmMessageIdToResolve.has(messageId)) {
    miniLmMessageIdToResolve.get(messageId)(embeddings);
    cleanup(messageId);
  } else if (action === "error" && miniLmMessageIdToReject.has(messageId)) {
    miniLmMessageIdToReject.get(messageId)(new Error(error));
    cleanup(messageId);
  }
};

const miniLmMessageIdToResolve = new Map();
const miniLmMessageIdToReject = new Map();

function cleanup(messageId) {
  miniLmMessageIdToResolve.delete(messageId);
  miniLmMessageIdToReject.delete(messageId);
}

function miniLmL6V2(modelPath, wordpieces) {
  return new Promise((resolve, reject) => {
    const messageId = Math.random().toString(36).substring(2);

    miniLmMessageIdToResolve.set(messageId, resolve);
    miniLmMessageIdToReject.set(messageId, reject);

    // If model path has changed or model is not yet loaded, fetch and load the model.
    if (cachedMiniLmModelPath !== modelPath || !cachedMiniLmModelPromise) {
      cachedMiniLmModelPath = modelPath;
      cachedMiniLmModelPromise = fetch(modelPath)
        .then(response => response.arrayBuffer())
        .then(modelArrayBuffer => {
          return new Promise((resolveLoad) => {
            // Post the load model message to the worker.
            miniLmWorker.postMessage({
              action: 'loadModel',
              modelArrayBuffer,
              messageId
            }, [modelArrayBuffer]);

            // Setup a one-time message listener for the "modelLoaded" message.
            const onModelLoaded = (e) => {
              if (e.data.action === 'modelLoaded' && e.data.messageId === messageId) {
                miniLmWorker.removeEventListener('message', onModelLoaded);
                resolveLoad();
              }
            };
            miniLmWorker.addEventListener('message', onModelLoaded);
          });
        })
        .catch(reject);
    }

    cachedMiniLmModelPromise.then(() => {
      // Once the model is loaded, send the run inference message to the worker.
      miniLmWorker.postMessage({
        action: 'runInference',
        wordpieces,
        messageId
      });
    }).catch(reject);
  });
}

window.miniLmL6V2 = miniLmL6V2;
