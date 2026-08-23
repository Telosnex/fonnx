import { parentPort, workerData } from 'node:worker_threads';

const queued = [];
let ready = false;
globalThis.self = globalThis;
Object.defineProperty(globalThis, 'navigator', {
  configurable: true,
  value: { hardwareConcurrency: 2 },
});
globalThis.postMessage = (message, transfer = []) =>
  parentPort.postMessage(message, transfer);
parentPort.on('message', (data) => {
  if (ready) globalThis.onmessage({ data });
  else queued.push(data);
});

await import(workerData);
ready = true;
for (const data of queued.splice(0)) globalThis.onmessage({ data });
