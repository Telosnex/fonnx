import fs from 'node:fs';
import { Worker as NodeWorker } from 'node:worker_threads';
import * as ort from '../example/web/ort.min.mjs';

class FakeWorker {
  static latest;
  constructor() {
    FakeWorker.latest = this;
  }
  postMessage(message) {
    this.lastMessage = message;
  }
  terminate() {
    this.terminated = true;
  }
}
globalThis.Worker = FakeWorker;
const { FonnxWorkerRpc } = await import('../example/web/fonnx_worker_rpc.js');
const rpc = new FonnxWorkerRpc(new URL('file:///fake-worker.js'), 'test');
const completed = rpc.request('identity', { value: 7 });
FakeWorker.latest.onmessage({
  data: {
    action: 'result',
    messageId: FakeWorker.latest.lastMessage.messageId,
    value: 7,
  },
});
if ((await completed).value !== 7) throw new Error('Worker RPC result mismatch');
const failed = rpc.request('crash');
FakeWorker.latest.onerror({ message: 'boom', preventDefault() {} });
await failed.then(
  () => { throw new Error('Worker crash unexpectedly resolved'); },
  (error) => {
    if (!error.message.includes('boom')) throw error;
  },
);
await rpc.request('after-crash').then(
  () => { throw new Error('Fatal Worker unexpectedly accepted new work'); },
  () => {},
);
if (!FakeWorker.latest.terminated) throw new Error('Fatal Worker was not terminated');

class BrowserWorkerAdapter {
  constructor(workerUrl) {
    this.worker = new NodeWorker(
      new URL('./support/node_web_worker_wrapper.mjs', import.meta.url),
      { type: 'module', workerData: workerUrl.href },
    );
    this.worker.on('message', (data) => this.onmessage?.({ data }));
    this.worker.on('messageerror', () => this.onmessageerror?.());
    this.worker.on('error', (error) =>
      this.onerror?.({ message: error.message, preventDefault() {} }),
    );
  }
  postMessage(message, transfer) {
    this.worker.postMessage(message, transfer);
  }
  terminate() {
    return this.worker.terminate();
  }
}

globalThis.Worker = BrowserWorkerAdapter;
const magikaRpc = new FonnxWorkerRpc(
  new URL('../example/web/magika_worker.js', import.meta.url),
  'magika-smoke',
);
const magikaModel = fs.readFileSync(
  new URL('../example/assets/models/magika/magika.onnx', import.meta.url),
);
const magikaBuffer = magikaModel.buffer.slice(
  magikaModel.byteOffset,
  magikaModel.byteOffset + magikaModel.byteLength,
);
await magikaRpc.request('loadModel', { modelArrayBuffer: magikaBuffer }, [magikaBuffer]);
const features = new Uint8Array(1536).fill(256 & 0xff);
const classification = await magikaRpc.request('runInference', {
  fileBytes: features,
});
if (!(classification.targetLabel instanceof Float32Array) ||
    classification.targetLabel.length !== 113) {
  throw new Error('Magika Worker output contract mismatch');
}
magikaRpc.fail(new Error('smoke complete'));

if (ort.env.versions.web !== '1.27.0' || ort.env.versions.common !== '1.27.0') {
  throw new Error(`Unexpected ORT Web versions: ${JSON.stringify(ort.env.versions)}`);
}
ort.env.wasm.numThreads = 1;
ort.env.wasm.wasmPaths = new URL('../example/web/', import.meta.url).href;

const model = fs.readFileSync(new URL('../test/models/identity.onnx', import.meta.url));
const session = await ort.InferenceSession.create(model, {
  executionProviders: ['wasm'],
});
try {
  const input = new ort.Tensor('float32', Float32Array.from([Math.PI]), [1]);
  const output = await session.run({ x: input });
  if (output.y.data.length !== 1 || output.y.data[0] !== Math.fround(Math.PI)) {
    throw new Error(`Identity inference mismatch: ${output.y.data}`);
  }
  output.y.dispose();
  input.dispose();
} finally {
  await session.release();
}
console.log('PASS: pinned local ONNX Runtime Web 1.27.0 identity inference');
console.log('PASS: Worker RPC resolves by ID and rejects every fatal pending call');
console.log('PASS: real Magika model executes through the pinned Worker protocol');
