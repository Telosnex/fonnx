 // Get the number of logical processors available.
 const whisperCores = navigator.hardwareConcurrency;

 let cachedWhisperModelPath = null;
 let cachedWhisperModelPromise = null;

 const whisperWorker = new Worker('fonnx_whisper_worker.js', { type: 'module' });

 // Simplified logs for brevity; can be extended to log each property if required.
 whisperWorker.onmessage = function (e) {
   const { messageId, action, transcript, error } = e.data;
   if (action === "inferenceResult" && whisperMessageIdToResolve.has(messageId)) {
     whisperMessageIdToResolve.get(messageId)(transcript);
     cleanup(messageId);
   } else if (action === "error" && whisperMessageIdToReject.has(messageId)) {
     whisperMessageIdToReject.get(messageId)(new Error(error));
     cleanup(messageId);
   }
 };

 const whisperMessageIdToResolve = new Map();
 const whisperMessageIdToReject = new Map();

 function cleanup(messageId) {
   whisperMessageIdToResolve.delete(messageId);
   whisperMessageIdToReject.delete(messageId);
 }

 function whisper(modelPath, audioBytes) {
   return new Promise((resolve, reject) => {
     const messageId = Math.random().toString(36).substring(2);

     whisperMessageIdToResolve.set(messageId, resolve);
     whisperMessageIdToReject.set(messageId, reject);

     // If model path has changed or model is not yet loaded, fetch and load the model.
     if (cachedWhisperModelPath !== modelPath || !cachedWhisperModelPromise) {
       cachedWhisperModelPath = modelPath;
       cachedWhisperModelPromise = fetch(modelPath)
         .then(response => response.arrayBuffer())
         .then(modelArrayBuffer => {
           return new Promise((resolveLoad) => {
             // Post the load model message to the worker.
             whisperWorker.postMessage({
               action: 'loadModel',
               modelArrayBuffer,
               messageId
             }, [modelArrayBuffer]);

             // Setup a one-time message listener for the "modelLoaded" message.
             const onModelLoaded = (e) => {
               if (e.data.action === 'modelLoaded' && e.data.messageId === messageId) {
                 whisperWorker.removeEventListener('message', onModelLoaded);
                 resolveLoad();
               }
             };
             whisperWorker.addEventListener('message', onModelLoaded);
           });
         })
         .catch(reject);
     }

     cachedWhisperModelPromise.then(() => {
       // Once the model is loaded, send the run inference message to the worker.
       whisperWorker.postMessage({
         action: 'runInference',
         audioBytes,
         messageId
       });
     }).catch(reject);
   });
 }

 window.whisper = whisper;