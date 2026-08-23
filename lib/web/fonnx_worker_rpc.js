export const fonnxWebWorkerProtocolVersion = 1;

export class FonnxWorkerRpc {
  constructor(workerUrl, label) {
    this.label = label;
    this.nextId = 0;
    this.pending = new Map();
    this.fatalError = null;
    this.worker = new Worker(workerUrl, { type: 'module' });
    this.worker.onmessage = ({ data }) => {
      const pending = this.pending.get(data.messageId);
      if (!pending) return;
      this.pending.delete(data.messageId);
      if (data.action === 'error') {
        pending.reject(new Error(data.error || `${label} Worker failed`));
      } else {
        pending.resolve(data);
      }
    };
    this.worker.onerror = (event) => {
      event.preventDefault?.();
      this.fail(new Error(`${label} Worker crashed: ${event.message || 'unknown error'}`));
    };
    this.worker.onmessageerror = () => {
      this.fail(new Error(`${label} Worker produced an unreadable response`));
    };
  }

  request(action, payload = {}, transfer = []) {
    if (this.fatalError) return Promise.reject(this.fatalError);
    const messageId = `${this.label}-${this.nextId++}`;
    return new Promise((resolve, reject) => {
      this.pending.set(messageId, { resolve, reject });
      try {
        this.worker.postMessage(
          { protocolVersion: fonnxWebWorkerProtocolVersion, action, messageId, ...payload },
          transfer,
        );
      } catch (error) {
        this.pending.delete(messageId);
        reject(error);
      }
    });
  }

  fail(error) {
    if (this.fatalError) return;
    this.fatalError = error;
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
    this.worker.terminate();
  }
}

export async function fetchModel(path, label) {
  const response = await fetch(path);
  if (!response.ok) {
    throw new Error(`Unable to fetch ${label} model ${path}: HTTP ${response.status}`);
  }
  return response.arrayBuffer();
}
