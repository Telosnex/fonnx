## Original model  
https://huggingface.co/sentence-transformers/msmarco-MiniLM-L-6-v3

## Creating ONNX Model
Given experience with MiniLM-L6-V2, we tried txtai's HFOnnx class again.
It produced a model that was also 23 MB with quantization.
It has the same inputs and outputs as MiniLM-L6-V2, which is expected.

## Testing versus MiniLM-L6-V2
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


