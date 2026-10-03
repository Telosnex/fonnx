import * as ort from './ort.min.mjs';

// The graphs are small; a large thread pool costs more than it saves.
ort.env.wasm.numThreads = 1;
ort.env.wasm.wasmPaths = new URL('./', import.meta.url).href;

const engines = new Map();
const embeddingNames = ['exactEmbeddings', 'exactBiases', 'hashedEmbeddings', 'hashedBiases'];
const embeddingOutputs = ['exact_embeddings', 'exact_biases', 'hashed_embeddings', 'hashed_biases'];

function disposeAll(tensors) {
  for (const tensor of Object.values(tensors || {})) tensor?.dispose?.();
}

async function run(session, feeds, outputNames) {
  let results;
  try {
    results = await session.run(feeds);
    return outputNames.map((name) => {
      const tensor = results[name];
      if (!tensor || tensor.type !== 'float32') {
        throw new Error(`FUTO Swipe output ${name} is missing or not float32`);
      }
      return Float32Array.from(tensor.data);
    });
  } finally {
    disposeAll(feeds);
    disposeAll(results);
  }
}

async function releaseEngine(engine) {
  await engine.encoder?.release();
  await engine.decoder?.release();
  await engine.context?.release();
}

async function createEngine(data) {
  const options = { executionProviders: ['wasm'] };
  const engine = { encoder: null, decoder: null, context: null };
  let embeddingSession = null;
  try {
    engine.encoder = await ort.InferenceSession.create(data.encoder, options);
    engine.decoder = await ort.InferenceSession.create(data.decoder, options);
    engine.context = await ort.InferenceSession.create(data.context, options);
    // Constant tables: copy once, then release the session.
    embeddingSession = await ort.InferenceSession.create(data.embeddings, options);
    const tables = await run(embeddingSession, {}, embeddingOutputs);
    const embeddings = {};
    embeddingNames.forEach((name, i) => { embeddings[name] = tables[i]; });
    return { engine, embeddings };
  } catch (error) {
    await releaseEngine(engine);
    throw error;
  } finally {
    await embeddingSession?.release();
  }
}

function requireEngine(engineId) {
  const engine = engines.get(engineId);
  if (!engine) throw new Error(`Unknown FUTO Swipe engine: ${engineId}`);
  return engine;
}

function reply(messageId, result, transfer = []) {
  self.postMessage({ action: 'result', messageId, result }, transfer);
}

self.onmessage = async ({ data }) => {
  const { action, messageId, engineId } = data;
  try {
    if (data.protocolVersion !== 1) throw new Error('Unsupported FONNX Worker protocol');
    if (action === 'load') {
      const { engine, embeddings } = await createEngine(data);
      const previous = engines.get(engineId);
      if (previous) await releaseEngine(previous);
      engines.set(engineId, engine);
      reply(messageId, embeddings, Object.values(embeddings).map((a) => a.buffer));
      return;
    }
    const engine = requireEngine(engineId);
    if (action === 'encoder') {
      const [logEmissions, coefficients, intention] = await run(
        engine.encoder,
        {
          features: new ort.Tensor('float32', data.features, [1, 2, 64]),
          layout_keys: new ort.Tensor('float32', data.layoutKeys, [1, 64, 2]),
          layout_mask: new ort.Tensor('bool', data.layoutMask, [1, 64]),
        },
        ['log_emissions', 'coefficients', 'intention'],
      );
      reply(
        messageId,
        { logEmissions, coefficients, intention },
        [logEmissions.buffer, coefficients.buffer, intention.buffer],
      );
    } else if (action === 'decoder') {
      const [output] = await run(
        engine.decoder,
        { features: new ort.Tensor('float32', data.features, [1, 32, 92]) },
        ['log_emissions'],
      );
      reply(messageId, output, [output.buffer]);
    } else if (action === 'context') {
      const ids = BigInt64Array.from(data.tokenIds, BigInt);
      const buckets = BigInt64Array.from(data.hashBuckets, BigInt);
      const [output] = await run(
        engine.context,
        {
          token_ids: new ort.Tensor('int64', ids, [1, 16]),
          hash_buckets: new ort.Tensor('int64', buckets, [1, 16, 2]),
        },
        ['context_states'],
      );
      reply(messageId, output, [output.buffer]);
    } else if (action === 'close') {
      await releaseEngine(engine);
      engines.delete(engineId);
      reply(messageId);
    } else {
      throw new Error(`Unknown action: ${action}`);
    }
  } catch (error) {
    self.postMessage({
      action: 'error',
      messageId,
      error: `${error.message}\n${error.stack || ''}`,
    });
  }
};
