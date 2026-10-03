// Immutable source pins and attribution for the FUTO Swipe format conversion.
const revision = '18328c3042b066952c0936b3771d492fe2ec289a';
const etRevision = '0b0e2c5cdd67c8b4396a46ea1d1aa72ffb0128d7';
const sourceHashes = {
  'LICENSE.md':
      'ef6b4f6437efa0a2929de351b10c16a8c870b32e1c23054ac76af61531f5db21',
  'scoring.json':
      '8377ba6932882667da1e87717609f4ccd6bb78709b6b6ea898d3d4325c9c37f6',
  'honorable_sturgeon/model_fp32.pte':
      '725242bab5d14345e96ff214e8de2bfbc1f962c232d320df9c24cb82ffd1fbaf',
  'honorable_sturgeon/metadata.json':
      'd2c5aecd89d97e21125046eb1f311b5aed1bdb5805e97316bba70b13f1c7be2c',
  'magic_macaw/model_fp32.pte':
      '01eaf16ac4bc0f1ed0698c240807f0e95e6d427bcf6de04983ffc50736744d85',
  'magic_macaw/metadata.json':
      '65ffc8890de41782eb3322aa96f31df24463ea434a200d3ce84aad4fe7c28a11',
  'hungry_jellyfish/context_lm.pte':
      '74d29f56a513c0c60abcd43df3b16a6b68925cdf4e97e51b094a5275ec2810d7',
  'hungry_jellyfish/metadata.json':
      '3daee38ea94796b676e7f60c3e1cf22525d5ae4dbdfa2787979a99e4573d9495',
  'hungry_jellyfish/vocab.txt':
      'a7db66376783b5a23ee3d4a2aaa8f2499fd9b35f975e92bcb248664c2cf6ebd1',
};
const schemas = {
  'schema/program.fbs':
      '6a39e1bebe3db4e03d1b2d21d8cdaa645b0a2288df32ed86e862fc9d4477cd5e',
  'schema/scalar_type.fbs':
      'a4c83c25ee7da8eedf61f04fe3df979e5866035763f0ee8d3ed68463e3baad8f',
  'backends/xnnpack/serialization/schema.fbs':
      'a4dca505a91b7c9ff690d0f58d5f2a49dc044a44d9261743fc32331eb644102d',
};
const futoSwipeModelPaths = {
  'honorable_sturgeon/model_fp32.onnx',
  'magic_macaw/model_fp32.onnx',
  'hungry_jellyfish/context_lm.onnx',
  'hungry_jellyfish/get_embeddings.onnx',
};
const futoSwipeNotice =
    '''These models are derived from FUTO Swipe and are subject to the FUTO Model
Weights License 1.0. See LICENSE-FUTO.txt for the complete, unchanged terms.

This is an unofficial ONNX format conversion. It does not imply sponsorship,
affiliation, or endorsement by FUTO. No training or intentional weight changes
were performed. Source revisions, tensor contracts, and checksums are recorded
in manifest.json.

Products using these models must display a visible notice to end users stating
that the product is powered by "FUTO Swipe" technology, as required by the license.
''';
String distributedSourcePath(String source) =>
    source == 'LICENSE.md' ? 'LICENSE-FUTO.txt' : source;
String sourceUrl(String source) =>
    'https://huggingface.co/futo-org/futo-swipe/resolve/$revision/$source';
