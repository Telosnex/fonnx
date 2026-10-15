import json, os, re, random, sys, torch, urllib.request
from misaki import en
from transformers import BartForConditionalGeneration

class FallbackNetwork:
    """misaki main's FallbackNetwork (unreleased in 0.9.4), greedy, max 64."""
    def __init__(self):
        self.model = BartForConditionalGeneration.from_pretrained("PeterReid/graphemes_to_phonemes_en_us", revision="a5631b285d18d59483c32c0c3379cb9fac924f4b").eval()
        self.g2t = {g: i for i, g in enumerate(self.model.config.grapheme_chars)}
        self.t2p = {i: p for i, p in enumerate(self.model.config.phoneme_chars)}
    def __call__(self, tk):
        ids = torch.tensor([[1] + [self.g2t.get(g, 3) for g in tk.text] + [2]])
        with torch.no_grad():
            out = self.model.generate(input_ids=ids, max_length=64)
        return ''.join(self.t2p.get(t, '') for t in out[0].tolist() if t > 3), 1

g2p = en.G2P(trf=False, british=False, fallback=None)
g2p_fb = en.G2P(trf=False, british=False, fallback=FallbackNetwork())

def gutenberg(path):
    t = open(path, encoding='utf-8-sig').read()
    a = t.find('*** START'); b = t.find('*** END')
    t = t[t.find('\n', a)+1:b]
    t = re.sub(r'\s+', ' ', t)
    sents = re.split(r'(?<=[.!?])\s+(?=[A-Z"“‘_])', t)
    return [s.strip() for s in sents if 20 <= len(s.strip()) <= 300]

random.seed(7)
here = os.path.dirname(os.path.abspath(__file__))
os.makedirs('corpus', exist_ok=True)
for name, num in [('alice', 11), ('pride', 1342)]:
    if not os.path.exists(f'corpus/{name}.txt'):
        urllib.request.urlretrieve(f'https://www.gutenberg.org/cache/epub/{num}/pg{num}.txt', f'corpus/{name}.txt')
lines = [l.strip() for l in open(os.path.join(here, 'misaki_handwritten.txt'), encoding='utf-8') if l.strip()]
lines += random.sample(gutenberg('corpus/alice.txt'), 300)
lines += random.sample(gutenberg('corpus/pride.txt'), 700)

out = []
for text in lines:
    pre_text, _, _ = en.G2P.preprocess(text)
    doc = g2p.nlp(pre_text)
    out.append({
        'text': text,
        'spacy': [[t.text, t.tag_, t.whitespace_, t.idx] for t in doc],
        'phonemes': g2p(text)[0],
        'phonemes_fallback': g2p_fb(text)[0],
    })
json.dump(out, open(sys.argv[1], 'w'), ensure_ascii=False, indent=0)
print(len(out), 'sentences', sum('❓' in x['phonemes_fallback'] for x in out), 'still with unk')
