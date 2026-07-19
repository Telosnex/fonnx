# Silero VAD model

This directory contains the official **Silero VAD v6.2.1** ONNX model.

- Source: https://github.com/snakers4/silero-vad/blob/v6.2.1/src/silero_vad/data/silero_vad.onnx
- Release: https://github.com/snakers4/silero-vad/releases/tag/v6.2.1
- Upstream commit: `7e30209a3e901f9842f81b225f3e93d8199902b1`
- SHA-256: `1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3`
- License: MIT (see the upstream repository)

The model consumes 512 new 16-kHz samples plus 64 samples of context and a
`[2, 1, 128]` recurrent state for each streaming inference frame.
