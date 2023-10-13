## Original model  
https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2


## Creating ONNX Model
### Known-good
philschmid provides a [ONNX version](https://huggingface.co/philschmid/all-MiniLM-L6-v2-optimum-embeddings). It was roughly a year old, so it was likely there is opportunity to optimize it further.  
### Olive
Initially, tried converting + optimizing the original Pytorch using [Olive](https://github.com/microsoft/Olive).
There were consistent errors, which may be due to:
- an [issue converting subgraphs in HF Optimum and ORT 1.16.0](https://github.com/huggingface/optimum/pull/1405)
- it seemed the shape of inputs was being optimized based on the test data. For example, instead of input tokens have a max of 256, it was arbitarily.
### Optimum
[HF Optimum](https://github.com/huggingface/optimum) was tried via optimum-cli.

It worked, but, the resulting models were larger than ex. the [known-good ONNX version from philschmid](https://huggingface.co/philschmid/all-MiniLM-L6-v2-optimum-embeddings)
### txtai
[txtai](https://github.com/neuml/txtai) provides a [example Colab notebook](https://github.com/neuml/txtai/blob/master/examples/18_Export_and_run_models_with_ONNX.ipynb) for converting a model to ONNX using their HFOnnx class.

This produced a model that was 90 MB without quantization, and 23 MB with quantization.
The quantized model produced outputs different from the known-good model.
This is expected.

To confirm the model was still working as expected, we compared test results from the Phil Schmid model to the quantized model.

## Testing versus MSMARCO-MiniLM-L6-V3
##### Inputs
__Answer__: WeatherChannel Spain the weather is sunny and warm  
__Random__: jabberwocky awaits: lets not be late lest the lillies bloom in the garden of eden
__SF__: shipping forecast  
__WF__: weather forecast  
__SpainWF__: spain weather forecast  
__WFinSpain__: weather forecast in Spain  
__BuffaloWF__: buffalo weather forecast  

##### Data

###### Similarity
Compared with __Answer__

|phrase   |L6V2 |MSMARCO |
|---------|-----|--------|
|Random   |0.055|0.054   |
|SF       |0.189|0.313   |
|BuffaloWF|0.278|0.344   |
|WF       |0.470|0.493   |
|SpainWF  |0.730|0.778   |
|WFInSpain|0.744|0.787   |



