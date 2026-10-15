# Exports misaki's OOV fallback (PeterReid/graphemes_to_phonemes_en_us, BART,
# Apache-2.0) to ONNX as (input_ids, decoder_input_ids) -> logits, plus its
# character tables. Usage: python export_misaki_fallback.py <out_dir>
import json, os, sys, torch
from transformers import BartForConditionalGeneration

out = sys.argv[1]
m = BartForConditionalGeneration.from_pretrained('PeterReid/graphemes_to_phonemes_en_us', revision='a5631b285d18d59483c32c0c3379cb9fac924f4b').eval()

class Full(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, input_ids, decoder_input_ids):
        return self.m(input_ids=input_ids, decoder_input_ids=decoder_input_ids, use_cache=False).logits

torch.onnx.export(
    Full(m), (torch.tensor([[1, 10, 11, 2]]), torch.tensor([[1, 5]])),
    os.path.join(out, 'g2p_fallback_en_us.onnx'),
    input_names=['input_ids', 'decoder_input_ids'], output_names=['logits'],
    dynamic_axes={'input_ids': {1: 'src'}, 'decoder_input_ids': {1: 'tgt'}, 'logits': {1: 'tgt'}},
    opset_version=17, dynamo=False)
json.dump({
    'grapheme_chars': m.config.grapheme_chars, 'phoneme_chars': m.config.phoneme_chars,
    'max_positions': m.config.max_position_embeddings,
    'source': 'https://huggingface.co/PeterReid/graphemes_to_phonemes_en_us', 'license': 'apache-2.0',
}, open(os.path.join(out, 'g2p_fallback_en_us.json'), 'w'), ensure_ascii=False, indent=1)
