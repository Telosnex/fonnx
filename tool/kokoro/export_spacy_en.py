import spacy, json, re, numpy as np, sys, os
from spacy.symbols import IDS
from spacy.lang.norm_exceptions import BASE_NORMS
nlp = spacy.load('en_core_web_sm', enable=['tok2vec','tagger'])
tok = nlp.tokenizer
out_dir = sys.argv[1]

SYNTAX = set('^$\\.*+?()[]{}|/')
def to_dart(p):
    out, i, in_cls = [], 0, False
    if p.startswith('(?u)'): p = p[4:]
    while i < len(p):
        c = p[i]
        if c == '\\':
            n = p[i+1]
            if n == 'U': out.append('\\u{%X}' % int(p[i+2:i+10], 16)); i += 10; continue
            if n == 'u': out.append(p[i:i+6]); i += 6; continue
            if n == 'w': out.append(r'\p{L}\p{N}_' if in_cls else r'[\p{L}\p{N}_]'); i += 2; continue
            if n == 'd': out.append(r'\p{Nd}'); i += 2; continue
            if n in 'sSbB': out.append(p[i:i+2]); i += 2; continue
            if n.isalnum(): raise ValueError('unhandled escape \\' + n)
            out.append(p[i:i+2] if (n in SYNTAX or (in_cls and n == '-')) else n)
            i += 2; continue
        if in_cls:
            if c == ']': in_cls = False
            out.append(c); i += 1; continue
        if c == '[':
            in_cls = True; out.append(c); i += 1
            if p[i] == '^': out.append('^'); i += 1
            if p[i] == ']': out.append('\\]'); i += 1
            continue
        if c == '{':
            q = re.match(r'\{\d+(,\d*)?\}', p[i:])
            if q: out.append(q.group()); i += len(q.group()); continue
            out.append('\\{'); i += 1; continue
        if c in '}]': out.append('\\' + c); i += 1; continue
        out.append(c); i += 1
    return ''.join(out)

# Weights, in forward order.
sp = nlp.get_pipe('tok2vec').model; tg = nlp.get_pipe('tagger').model
layers = []
def walk(m):
    if m.name == 'hashembed': layers.append({'type': 'hashembed', 'seed': m.attrs['seed'], 'params': [m.get_param('E')]})
    elif m.name in ('maxout', 'layernorm', 'softmax'): layers.append({'type': m.name, 'params': [m.get_param('W' if m.name != 'layernorm' else 'G'), m.get_param('b')]})
    for c in m.layers: walk(c)
walk(sp); walk(tg)
blob = bytearray(); manifest = []
for l in layers:
    entry = {'type': l['type'], 'tensors': []}
    if 'seed' in l: entry['seed'] = l['seed']
    for p in l['params']:
        a = np.ascontiguousarray(p, dtype='<f4')
        entry['tensors'].append({'offset': len(blob), 'shape': list(a.shape)})
        blob += a.tobytes()
    manifest.append(entry)
open(os.path.join(out_dir, 'en_core_web_sm_tagger.bin'), 'wb').write(blob)

table = nlp.vocab.lookups.get_table('lexeme_norm')
json.dump({
    'spacy_version': spacy.__version__, 'model_version': nlp.meta['version'], 'license': nlp.meta['license'],
    'prefix': to_dart(tok.prefix_search.__self__.pattern),
    'suffix': to_dart(tok.suffix_search.__self__.pattern),
    'infix': to_dart(tok.infix_finditer.__self__.pattern),
    'url': to_dart(tok.url_match.__self__.pattern),
    'rules': {k: [[d[65], d.get(67)] for d in v] for k, v in tok.rules.items()},
    'lexeme_norm': {'%016x' % k: v for k, v in table.items()},
    'base_norms': BASE_NORMS,
    'symbols': {k: v for k, v in IDS.items() if k},
    'labels': list(nlp.get_pipe('tagger').labels),
    'layers': manifest,
}, open(os.path.join(out_dir, 'en_core_web_sm.json'), 'w'), ensure_ascii=False)
print(len(blob), 'bytes of weights;', [l['type'] for l in manifest])
print('url tail', tok.url_match.__self__.pattern[-40:])
