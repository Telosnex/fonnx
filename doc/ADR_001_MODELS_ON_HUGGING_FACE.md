# ADR 001 — Model files on Hugging Face, pins in Git
Status: FROZEN

## 1. Problem

fonnx keeps its model files in three places:

| Place | What is there | Who reads it |
|---|---|---|
| Git and Git LFS, `example/assets/models` | 17 models, 386 MB. 6 are in LFS. 11 are plain Git objects, for example `minishLab/potion8m.onnx` (30 MB). | Tests and CI |
| GitHub release `runtime-aae5c3ee879612eb` | The same 17 runtime models, as `.gz` files | `runtimeModelFile` and `ensureFonnxRuntimeModel` |
| Hugging Face `telosnex/fonnx` | Whisper tiny, base and small, MiniLM, MSMARCO, Silero VAD, NemoAsr | Telosnex, at the `main` revision |

This causes these problems:

- Each CI job that runs model tests downloads the LFS files again. A model in plain Git is in every clone, also when no test needs it.
- When a model changes, the old copy stays in LFS storage and in Git history.
- Parakeet TDT v3 (670 MB) is too large for Git. It is only on Hugging Face. A NemoAsr test of v3 can run only when a person gives a local directory.
- Telosnex downloads from Hugging Face at `main`. If a file on `main` changes, every Telosnex install gets the new bytes.
- To add a model, a person must change LFS attributes, `manifest.json`, `runtime_models.dart`, the hydrate tool, the artifact check and a GitHub release. NemoAsr needed all six.

## 2. Requirements

| ID | Requirement | Source | Hardness |
|----|-------------|--------|----------|
| R1 | Each model download is checked against a SHA-256 that is in Git. | founder | hard |
| R2 | One host serves every model that fonnx tests use and that apps download. | founder | hard |
| R3 | A clone of fonnx does not contain model files, except the small test fixtures in `test/models`. | founder | hard |
| R4 | Tests use the same bytes that apps download. | assumed | hard |
| R5 | A model of 1 GB or more can be added. | assumed | soft |
| R6 | A CI run does not download each model from the host again when the pins did not change. | platform | soft |
| R7 | Each model shows its source and license next to the file. CC-BY-4.0 models need attribution. | license | hard |
| R8 | A fonnx commit that is already published continues to download its models. | assumed | hard |

## 3. Decisions

```
D1: Model files are on Hugging Face in telosnex/fonnx. Git keeps only the
    name, SHA-256, size and Hugging Face commit of each file.
    Because: R2, R3, R5
    Instead of: GitHub release assets. The download code for them exists,
    but Telosnex already uses Hugging Face, so two hosts remain (R2).
    Instead of: Git LFS. Every clone that runs tests pays for the bytes (R3).

D2: Each URL contains a Hugging Face commit hash. No URL contains `main`.
    Because: R1, R8
    Instead of: `main`. A new file on `main` changes the bytes under an old
    pin. The SHA-256 check then fails for every user at the same time.

D3: The catalog stays in the kiln format: the `runtimeFiles`
    section of native_artifacts/prebuilt.json, and lib/src/kiln.g.dart.
    A fonnx tool writes them with Hugging Face URLs and no compression.
    Because: R1, R4
    Instead of: a new catalog format. `kiln:check --downloads`
    already checks each runtimeFiles entry, and runtimeModelFile already
    reads the generated Dart.

D4: The file names on Hugging Face are the current runtime release names,
    the values of runtimeModelNamesByPath. The files are in the root of the
    repository.
    Because: R8
    Instead of: the directory layout of example/assets/models. Telosnex and
    the existing files on Hugging Face use flat names.

D5: Tests read models from example/assets/models, as now. A tool downloads
    the files there from the catalog. Git ignores these files. CI caches the
    directory with a key from the hash of the catalog.
    Because: R4, R6
    Instead of: a separate cache directory. All tests and the web test
    server already use these paths.

D6: Model files leave the Git tree. Git history is not rewritten.
    The test fixtures in test/models stay in Git: identity.onnx (84 bytes),
    bpe_decoder.onnx (375 bytes) and magika.onnx (1 MB).
    Because: R3, R8
    Instead of: a history rewrite. Telosnex pins fonnx by Git commit, and a
    rewrite removes those commits.

D7: The GitHub release runtime-aae5c3ee879612eb stays. fonnx publishes no
    new model releases on GitHub.
    Because: R8

D8: The README of telosnex/fonnx lists each file, its source, its license
    and the attribution. Its source is tool/hf/README.md. LICENSE-FUTO.txt
    is next to it.
    Because: R7
```

## 4. Invariants

```
I1: Each catalog URL is
    https://huggingface.co/telosnex/fonnx/resolve/<40 hex>/<name>.
    If violated: a file can change under its pin (D2).
    Pinned by: tool/verify_artifacts.dart.

I2: For each model, the SHA-256 and size in manifest.json, in the catalog and
    on Hugging Face are the same.
    If violated: apps download bytes that the tests did not use.
    Pinned by: tool/verify_artifacts.dart (manifest and catalog), and
    tool/verify_artifacts.dart --downloads (Hugging Face paths-info API).

I3: Git tracks no .onnx file under example/assets/models.
    If violated: R3 fails again.
    Pinned by: tool/verify_artifacts.dart, with `git ls-files`.

I4: A download with the wrong SHA-256 does not replace a file.
    If violated: an app runs a model that is not pinned.
    Pinned by: kiln fetchVerified tests (existing).
```

## 5. Formats and names

- Hugging Face repository: `telosnex/fonnx`, type `model`.
- URL: `https://huggingface.co/telosnex/fonnx/resolve/<commit>/<name>`. `<commit>` is the 40-character commit hash.
- Each entry in the `models` section of `native_artifacts/manifest.json` gets two new keys:
  - `name`: the file name on Hugging Face.
  - `commit`: the Hugging Face commit that has the file. A new entry has no
    `commit` until `tool/publish_models.dart` uploads the file.
- The existing keys `path`, `sha256` and `bytes` do not change.
- The first commit with NemoAsr files is `bbecfb3bf170f508901dba5ae70afb482a3d65ca`.

## 6. Non-goals

```
NG1: Remove model files from Git history and LFS storage.
     Reopens when: GitHub bills for LFS storage of Telosnex/fonnx.

NG2: Move the models of the docs/ web demo (3 LFS files).
     Reopens when: the demo is deployed again.

NG3: Change how Telosnex downloads Whisper.
     Reopens when: Telosnex adds NemoAsr. Then Telosnex uses
     runtimeModelFile for all speech models.

NG4: A second host as a mirror.
     Reopens when: a Hugging Face outage stops a release or blocks users.
```

## 7. Risks

1. **Hugging Face history is deleted.** A "super-squash" of the repository, or the deletion of the repository, removes the commits. All pinned URLs then fail for all shipped apps. Recovery needs a new app release. Do not squash or delete `telosnex/fonnx`. Give the write token only to the people who publish.
2. **The account or token is lost.** No one can publish a new model. Published files continue to download.
3. **Hugging Face limits anonymous downloads.** CI fails when the cache is empty. The cache of D5 decreases this risk. A read token in CI removes it.
4. **The GitHub release is deleted.** Old fonnx commits stop downloading their models. D7 keeps the release.

## 8. Workplan

1. Done. Upload to `telosnex/fonnx` the 13 catalog models that are not there: `bpe_decoder.onnx`, the 4 FUTO Swipe files, the 3 keyword spotter files, `magika.onnx`, the 2 MinishLab files, `pyannote_seg3.onnx` and `silero_vad_v6.2.1.onnx`. The `silero_vad.onnx` on Hugging Face is a different file. Use the release names. Record the commit. The tool of step 4 uploaded all 17 in commit `4cd3bbfa3d43d88da1ccdd41ddbf3a03baaf3979`.
2. Done. Add `name` and `commit` to each entry in the `models` section of `manifest.json`. Add the CTC NemoAsr model and the 3 Parakeet TDT v3 files.
3. Done. Make sure that kiln accepts a Hugging Face URL in `runtimeFiles`. It does: a URL without `.gz` downloads unchanged. kiln did not change.
4. Done. Replace `tool/publish_models.dart` with a tool that checks the local files against `manifest.json`, uploads them with `hf upload`, and writes `prebuilt.json` `runtimeFiles` and `lib/src/kiln.g.dart`.
5. Done. Change `tool/fetch_hf_models.dart` so that it downloads every catalog model, not a fixed list. It also takes paths, so that a CI job downloads only the models of its tests.
6. Done. Add I1, I2 and I3 to `tool/verify_artifacts.dart`.
7. Done. In CI, replace the hydrate step with the fetch tool and `actions/cache`. The cache key has the hash of `manifest.json`, which has the pins.
8. Done. Remove the model files from the Git tree. Add `example/assets/models/**/*.onnx` to `.gitignore`. Delete `tool/hydrate_lfs_models.dart` and the `example/` LFS attributes.
9. Done. Write the README of `telosnex/fonnx` (D8).
10. Done. Remove the `FONNX_NEMO_ASR_DIR` skip from the v3 test. The fetch tool downloads v3.

## ──────── non-normative ────────

### A. Alternatives and notes

- **kiln `runtimeRelease` with an `assetUrl` for Hugging Face.** The tool uploads `.gz` copies. Hugging Face then stores a second copy of each file, and Telosnex cannot read the file by its plain name. Ruled out by R2.
- **Hugging Face deduplicates.** The NemoAsr upload sent 0 bytes, because Hugging Face already stores the same files for sherpa-onnx. An upload of an unchanged public export is fast and adds no storage.
- **Git LFS and plain Git.** 11 of the 17 models in `example/assets/models` are plain Git objects. A plain Git object is in every clone, even a clone that skips LFS.

### B. Revision history

- 2026-10-13: First draft, after NemoAsr. The CTC model went to Hugging Face instead of LFS, in commit 5642bbd.
- 2026-10-13: Frozen after the workplan. The 21 models are on Hugging Face; the catalog points there.
