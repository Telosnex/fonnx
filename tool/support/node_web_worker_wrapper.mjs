import { parentPort, workerData } from 'node:worker_threads';

// A minimal DedicatedWorkerGlobalScope for the fonnx Workers: postMessage,
// onmessage, addEventListener('message') and dispatchEvent. A browser holds
// messages until the Worker script runs; this queues them until the module
// has loaded.
globalThis.self = globalThis;
Object.defineProperty(globalThis, 'navigator', {
  configurable: true,
  value: { hardwareConcurrency: 2 },
});
globalThis.performance ??= { getEntriesByType: () => [] };
globalThis.postMessage = (message, transfer = []) =>
  parentPort.postMessage(message, transfer);

const listeners = [];
globalThis.addEventListener = (type, listener) => {
  if (type === 'message') listeners.push(listener);
};
globalThis.dispatchEvent = (event) => {
  for (const listener of [...listeners]) listener(event);
  globalThis.onmessage?.(event);
  return true;
};
const queued = [];
let ready = false;
const deliver = (data) =>
  globalThis.dispatchEvent(new MessageEvent('message', { data }));
parentPort.on('message', (data) => (ready ? deliver(data) : queued.push(data)));

await import(workerData);
ready = true;
for (const data of queued.splice(0)) deliver(data);
