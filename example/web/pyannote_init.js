// Get the number of logical processors available.
const pyannoteCores = navigator.hardwareConcurrency;

let cachedPyannoteModelPath = null;
let cachedPyannoteModelPromise = null;

const pyannoteWorker = new Worker('pyannote_worker.js', { type: 'module' });

const pyannoteMessageIdToResolve = new Map();
const pyannoteMessageIdToReject = new Map();

pyannoteWorker.onmessage = function (e) {
  const { messageId, action, results, error } = e.data;
  if (action === "inferenceResult" && pyannoteMessageIdToResolve.has(messageId)) {
    pyannoteMessageIdToResolve.get(messageId)(results);
    cleanup(messageId);
  } else if (action === "error" && pyannoteMessageIdToReject.has(messageId)) {
    pyannoteMessageIdToReject.get(messageId)(new Error(error));
    cleanup(messageId);
  }
};

function cleanup(messageId) {
  pyannoteMessageIdToResolve.delete(messageId);
  pyannoteMessageIdToReject.delete(messageId);
}

function pyannote(modelPath, audioData) {
  return new Promise((resolve, reject) => {
    const messageId = Math.random().toString(36).substring(2);

    pyannoteMessageIdToResolve.set(messageId, resolve);
    pyannoteMessageIdToReject.set(messageId, reject);

    // If model path has changed or model is not yet loaded, fetch and load the model.
    if (cachedPyannoteModelPath !== modelPath || !cachedPyannoteModelPromise) {
      cachedPyannoteModelPath = modelPath;
      cachedPyannoteModelPromise = fetch(modelPath)
        .then(response => response.arrayBuffer())
        .then(modelArrayBuffer => {
          return new Promise((resolveLoad) => {
            // Post the load model message to the worker.
            pyannoteWorker.postMessage({
              action: 'loadModel',
              modelArrayBuffer,
              messageId
            }, [modelArrayBuffer]);

            // Setup a one-time message listener for the "modelLoaded" message.
            const onModelLoaded = (e) => {
              if (e.data.action === 'modelLoaded' && e.data.messageId === messageId) {
                pyannoteWorker.removeEventListener('message', onModelLoaded);
                resolveLoad();
              }
            };
            pyannoteWorker.addEventListener('message', onModelLoaded);
          });
        })
        .catch(reject);
    }

    cachedPyannoteModelPromise.then(() => {
      // Once the model is loaded, send the run inference message to the worker.
      pyannoteWorker.postMessage({
        action: 'runInference',
        audioData,
        messageId
      });
    }).catch(reject);
  });
}

window.pyannote = pyannote;