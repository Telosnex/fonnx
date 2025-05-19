// Get the number of logical processors available for potential tuning (not used directly here)
const minishLabCores = navigator.hardwareConcurrency;

let cachedMinishLabModelPath = null;
let cachedMinishLabModelPromise = null;

const minishLabWorker = new Worker('minish_lab_worker.js', { type: 'module' });

minishLabWorker.onmessage = (e) => {
  const { messageId, action, embeddings, error } = e.data;
  if (action === 'inferenceResult' && minishLabResolveMap.has(messageId)) {
    minishLabResolveMap.get(messageId)(embeddings);
    cleanup(messageId);
  } else if (action === 'error' && minishLabRejectMap.has(messageId)) {
    minishLabRejectMap.get(messageId)(new Error(error));
    cleanup(messageId);
  }
};

const minishLabResolveMap = new Map();
const minishLabRejectMap = new Map();

function cleanup(messageId) {
  minishLabResolveMap.delete(messageId);
  minishLabRejectMap.delete(messageId);
}

// Returns a promise resolving to embeddings Float32Array
function minishLab(modelPath, wordpieces) {
  return new Promise((resolve, reject) => {
    const messageId = Math.random().toString(36).slice(2);

    minishLabResolveMap.set(messageId, resolve);
    minishLabRejectMap.set(messageId, reject);

    // (Re)load the model only if path changed or first time.
    if (cachedMinishLabModelPath !== modelPath || !cachedMinishLabModelPromise) {
      cachedMinishLabModelPath = modelPath;
      console.log('MinishLab: loading model from', modelPath);
      cachedMinishLabModelPromise = fetch(modelPath)
        .then((resp) => resp.arrayBuffer())
        .then((modelArrayBuffer) => {
          return new Promise((resLoad) => {
            minishLabWorker.postMessage({ action: 'loadModel', modelArrayBuffer, messageId }, [modelArrayBuffer]);

            const onLoaded = (e) => {
              if (e.data.action === 'modelLoaded' && e.data.messageId === messageId) {
                minishLabWorker.removeEventListener('message', onLoaded);
                resLoad();
              }
            };
            minishLabWorker.addEventListener('message', onLoaded);
          });
        })
        .catch(reject);
    }

    cachedMinishLabModelPromise
      .then(() => {
        minishLabWorker.postMessage({ action: 'runInference', wordpieces, messageId });
      })
      .catch(reject);
  });
}

window.minishLab = minishLab;