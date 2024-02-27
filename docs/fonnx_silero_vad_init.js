 // Get the number of logical processors available.
 const sileroVadCores = navigator.hardwareConcurrency;

 let cachedSileroVadModelPath = null;
 let cachedSileroVadModelPromise = null;

 const sileroVadWorker = new Worker('fonnx_silero_vad_worker.js', { type: 'module' });

 const sileroVadMessageIdToResolve = new Map();
 const sileroVadMessageIdToReject = new Map();

 sileroVadWorker.onmessage = function (e) {
   const { messageId, action, resultMapAsJsonString, error } = e.data;
   if (action === "inferenceResult" && sileroVadMessageIdToResolve.has(messageId)) {
     sileroVadMessageIdToResolve.get(messageId)(resultMapAsJsonString);
     cleanup(messageId);
   } else if (action === "error" && sileroVadMessageIdToReject.has(messageId)) {
     sileroVadMessageIdToReject.get(messageId)(new Error(error));
     cleanup(messageId);
   }
 };

 function cleanup(messageId) {
   sileroVadMessageIdToResolve.delete(messageId);
   sileroVadMessageIdToReject.delete(messageId);
 }

 function sileroVad(modelPath, audioBytes, previousStateAsJsonString) {
   return new Promise((resolve, reject) => {
     const messageId = Math.random().toString(36).substring(2);

     sileroVadMessageIdToResolve.set(messageId, resolve);
     sileroVadMessageIdToReject.set(messageId, reject);

     // If model path has changed or model is not yet loaded, fetch and load the model.
     if (cachedSileroVadModelPath !== modelPath || !cachedSileroVadModelPromise) {
       cachedSileroVadModelPath = modelPath;
       cachedSileroVadModelPromise = fetch(modelPath)
         .then(response => response.arrayBuffer())
         .then(modelArrayBuffer => {
           return new Promise((resolveLoad) => {
             // Post the load model message to the worker.
             sileroVadWorker.postMessage({
               action: 'loadModel',
               modelArrayBuffer,
               messageId
             }, [modelArrayBuffer]);

             // Setup a one-time message listener for the "modelLoaded" message.
             const onModelLoaded = (e) => {
               if (e.data.action === 'modelLoaded' && e.data.messageId === messageId) {
                 sileroVadWorker.removeEventListener('message', onModelLoaded);
                 resolveLoad();
               }
             };
             sileroVadWorker.addEventListener('message', onModelLoaded);
           });
         })
         .catch(reject);
     }

     cachedSileroVadModelPromise.then(() => {
       // Once the model is loaded, send the run inference message to the worker.
       sileroVadWorker.postMessage({
         action: 'runInference',
         audioBytes,
         previousStateAsJsonString,
         messageId
       });
     }).catch(reject);
   });
 }

 window.sileroVad = sileroVad;
