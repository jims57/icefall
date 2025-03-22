Export streaming Zipformer transducer models to ncnn
We use the pre-trained model from the following repository as an example:

https://huggingface.co/Zengwei/icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29

We will show you step by step how to export it to ncnn and run it with sherpa-ncnn.

Hint

We use Ubuntu 18.04, torch 1.13, and Python 3.8 for testing.

Caution

torch > 2.0 may not work. If you get errors while building pnnx, please switch to torch < 2.0.

1. Download the pre-trained model
Hint

You have to install git-lfs before you continue.

cd egs/librispeech/ASR
GIT_LFS_SKIP_SMUDGE=1 git clone https://huggingface.co/Zengwei/icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29
cd icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29

git lfs pull --include "exp/pretrained.pt"
git lfs pull --include "data/lang_bpe_500/bpe.model"

cd ..
Note

We downloaded exp/pretrained-xxx.pt, not exp/cpu-jit_xxx.pt.

In the above code, we downloaded the pre-trained model into the directory egs/librispeech/ASR/icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29.

2. Install ncnn and pnnx
Please refer to 2. Install ncnn and pnnx .

3. Export the model via torch.jit.trace()
First, let us rename our pre-trained model:

cd egs/librispeech/ASR

cd icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp

ln -s pretrained.pt epoch-99.pt

cd ../..
Next, we use the following code to export our model:

dir=./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29

./pruned_transducer_stateless7_streaming/export-for-ncnn.py \
  --tokens $dir/data/lang_bpe_500/tokens.txt \
  --exp-dir $dir/exp \
  --use-averaged-model 0 \
  --epoch 99 \
  --avg 1 \
  --decode-chunk-len 32 \
  --num-left-chunks 4 \
  --num-encoder-layers "2,4,3,2,4" \
  --feedforward-dims "1024,1024,2048,2048,1024" \
  --nhead "8,8,8,8,8" \
  --encoder-dims "384,384,384,384,384" \
  --attention-dims "192,192,192,192,192" \
  --encoder-unmasked-dims "256,256,256,256,256" \
  --zipformer-downsampling-factors "1,2,4,8,2" \
  --cnn-module-kernels "31,31,31,31,31" \
  --decoder-dim 512 \
  --joiner-dim 512
Caution

If your model has different configuration parameters, please change them accordingly.

Hint

We have renamed our model to epoch-99.pt so that we can use --epoch 99. There is only one pre-trained model, so we use --avg 1 --use-averaged-model 0.

If you have trained a model by yourself and if you have all checkpoints available, please first use decode.py to tune --epoch --avg and select the best combination with with --use-averaged-model 1.

Note

You will see the following log output:

2023-02-27 20:23:07,473 INFO [export-for-ncnn.py:246] device: cpu
2023-02-27 20:23:07,477 INFO [export-for-ncnn.py:255] {'best_train_loss': inf, 'best_valid_loss': inf, 'best_train_epoch': -1, 'best_valid_epoch': -1, 'batch_idx_train': 0, 'log_interval': 50, 'reset_interval': 200, 'valid_interval': 3000, 'feature_dim': 80, 'subsampling_factor': 4, 'warm_step': 2000, 'env_info': {'k2-version': '1.23.4', 'k2-build-type': 'Release', 'k2-with-cuda': True, 'k2-git-sha1': '62e404dd3f3a811d73e424199b3408e309c06e1a', 'k2-git-date': 'Mon Jan 30 10:26:16 2023', 'lhotse-version': '1.12.0.dev+missing.version.file', 'torch-version': '1.10.0+cu102', 'torch-cuda-available': True, 'torch-cuda-version': '10.2', 'python-version': '3.8', 'icefall-git-branch': 'master', 'icefall-git-sha1': '6d7a559-clean', 'icefall-git-date': 'Thu Feb 16 19:47:54 2023', 'icefall-path': '/star-fj/fangjun/open-source/icefall-2', 'k2-path': '/star-fj/fangjun/open-source/k2/k2/python/k2/__init__.py', 'lhotse-path': '/star-fj/fangjun/open-source/lhotse/lhotse/__init__.py', 'hostname': 'de-74279-k2-train-3-1220120619-7695ff496b-s9n4w', 'IP address': '10.177.6.147'}, 'epoch': 99, 'iter': 0, 'avg': 1, 'exp_dir': PosixPath('icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp'), 'bpe_model': './icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/data/lang_bpe_500/bpe.model', 'context_size': 2, 'use_averaged_model': False, 'num_encoder_layers': '2,4,3,2,4', 'feedforward_dims': '1024,1024,2048,2048,1024', 'nhead': '8,8,8,8,8', 'encoder_dims': '384,384,384,384,384', 'attention_dims': '192,192,192,192,192', 'encoder_unmasked_dims': '256,256,256,256,256', 'zipformer_downsampling_factors': '1,2,4,8,2', 'cnn_module_kernels': '31,31,31,31,31', 'decoder_dim': 512, 'joiner_dim': 512, 'short_chunk_size': 50, 'num_left_chunks': 4, 'decode_chunk_len': 32, 'blank_id': 0, 'vocab_size': 500}
2023-02-27 20:23:07,477 INFO [export-for-ncnn.py:257] About to create model
2023-02-27 20:23:08,023 INFO [zipformer2.py:419] At encoder stack 4, which has downsampling_factor=2, we will combine the outputs of layers 1 and 3, with downsampling_factors=2 and 8.
2023-02-27 20:23:08,037 INFO [checkpoint.py:112] Loading checkpoint from icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/epoch-99.pt
2023-02-27 20:23:08,655 INFO [export-for-ncnn.py:346] encoder parameters: 68944004
2023-02-27 20:23:08,655 INFO [export-for-ncnn.py:347] decoder parameters: 260096
2023-02-27 20:23:08,655 INFO [export-for-ncnn.py:348] joiner parameters: 716276
2023-02-27 20:23:08,656 INFO [export-for-ncnn.py:349] total parameters: 69920376
2023-02-27 20:23:08,656 INFO [export-for-ncnn.py:351] Using torch.jit.trace()
2023-02-27 20:23:08,656 INFO [export-for-ncnn.py:353] Exporting encoder
2023-02-27 20:23:08,656 INFO [export-for-ncnn.py:174] decode_chunk_len: 32
2023-02-27 20:23:08,656 INFO [export-for-ncnn.py:175] T: 39
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1344: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_len.size(0) == self.num_layers, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1348: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_avg.size(0) == self.num_layers, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1352: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_key.size(0) == self.num_layers, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1356: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_val.size(0) == self.num_layers, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1360: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_val2.size(0) == self.num_layers, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1364: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_conv1.size(0) == self.num_layers, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1368: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_conv2.size(0) == self.num_layers, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1373: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert self.left_context_len == cached_key.shape[1], (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1884: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert self.x_size == x.size(0), (self.x_size, x.size(0))
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:2442: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_key.shape[0] == self.left_context_len, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:2449: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_key.shape[0] == cached_val.shape[0], (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:2469: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_key.shape[0] == left_context_len, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:2473: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_val.shape[0] == left_context_len, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:2483: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert kv_len == k.shape[0], (kv_len, k.shape)
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:2570: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert list(attn_output.size()) == [bsz * num_heads, seq_len, head_dim // 2]
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:2926: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cache.shape == (x.size(0), x.size(1), self.lorder), (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:2652: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert x.shape[0] == self.x_size, (x.shape[0], self.x_size)
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:2653: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert x.shape[2] == self.embed_dim, (x.shape[2], self.embed_dim)
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:2666: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert cached_val.shape[0] == self.left_context_len, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1543: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert src.shape[0] == self.in_x_size, (src.shape[0], self.in_x_size)
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1637: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert src.shape[0] == self.in_x_size, (
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1643: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert src.shape[2] == self.in_channels, (src.shape[2], self.in_channels)
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1571: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  if src.shape[0] != self.in_x_size:
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1763: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert src1.shape[:-1] == src2.shape[:-1], (src1.shape, src2.shape)
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1779: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert src1.shape[-1] == self.dim1, (src1.shape[-1], self.dim1)
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/zipformer2.py:1780: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert src2.shape[-1] == self.dim2, (src2.shape[-1], self.dim2)
/star-fj/fangjun/py38/lib/python3.8/site-packages/torch/jit/_trace.py:958: TracerWarning: Encountering a list at the output of the tracer might cause the trace to be incorrect, this is only valid if the container structure does not change based on the module's inputs. Consider using a constant container instead (e.g. for `list`, use a `tuple` instead. for `dict`, use a `NamedTuple` instead). If you absolutely need this and know the side effects, pass strict=False to trace() to allow this behavior.
  module._c._create_method_from_trace(
2023-02-27 20:23:19,640 INFO [export-for-ncnn.py:182] Saved to icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/encoder_jit_trace-pnnx.pt
2023-02-27 20:23:19,646 INFO [export-for-ncnn.py:357] Exporting decoder
/star-fj/fangjun/open-source/icefall-2/egs/librispeech/ASR/pruned_transducer_stateless7_streaming/decoder.py:102: TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  assert embedding_out.size(-1) == self.context_size
2023-02-27 20:23:19,686 INFO [export-for-ncnn.py:204] Saved to icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/decoder_jit_trace-pnnx.pt
2023-02-27 20:23:19,686 INFO [export-for-ncnn.py:361] Exporting joiner
2023-02-27 20:23:19,735 INFO [export-for-ncnn.py:231] Saved to icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/joiner_jit_trace-pnnx.pt
The log shows the model has 69920376 parameters, i.e., ~69.9 M.

ls -lh icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/pretrained.pt
-rw-r--r-- 1 kuangfangjun root 269M Jan 12 12:53 icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/pretrained.pt
You can see that the file size of the pre-trained model is 269 MB, which is roughly equal to 69920376*4/1024/1024 = 266.725 MB.

After running pruned_transducer_stateless7_streaming/export-for-ncnn.py, we will get the following files:

ls -lh icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/*pnnx.pt

-rw-r--r-- 1 kuangfangjun root 1022K Feb 27 20:23 icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/decoder_jit_trace-pnnx.pt
-rw-r--r-- 1 kuangfangjun root  266M Feb 27 20:23 icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/encoder_jit_trace-pnnx.pt
-rw-r--r-- 1 kuangfangjun root  2.8M Feb 27 20:23 icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/joiner_jit_trace-pnnx.pt
4. Export torchscript model via pnnx
Hint

Make sure you have set up the PATH environment variable in 2. Install ncnn and pnnx. Otherwise, it will throw an error saying that pnnx could not be found.

Now, it’s time to export our models to ncnn via pnnx.

cd icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/

pnnx ./encoder_jit_trace-pnnx.pt
pnnx ./decoder_jit_trace-pnnx.pt
pnnx ./joiner_jit_trace-pnnx.pt
It will generate the following files:

ls -lh  icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/*ncnn*{bin,param}

-rw-r--r-- 1 kuangfangjun root 509K Feb 27 20:31 icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/decoder_jit_trace-pnnx.ncnn.bin
-rw-r--r-- 1 kuangfangjun root  437 Feb 27 20:31 icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/decoder_jit_trace-pnnx.ncnn.param
-rw-r--r-- 1 kuangfangjun root 133M Feb 27 20:30 icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/encoder_jit_trace-pnnx.ncnn.bin
-rw-r--r-- 1 kuangfangjun root 152K Feb 27 20:30 icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/encoder_jit_trace-pnnx.ncnn.param
-rw-r--r-- 1 kuangfangjun root 1.4M Feb 27 20:31 icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/joiner_jit_trace-pnnx.ncnn.bin
-rw-r--r-- 1 kuangfangjun root  488 Feb 27 20:31 icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/joiner_jit_trace-pnnx.ncnn.param
There are two types of files:

param: It is a text file containing the model architectures. You can use a text editor to view its content.

bin: It is a binary file containing the model parameters.

We compare the file sizes of the models below before and after converting via pnnx:

File name

File size

encoder_jit_trace-pnnx.pt

266 MB

decoder_jit_trace-pnnx.pt

1022 KB

joiner_jit_trace-pnnx.pt

2.8 MB

encoder_jit_trace-pnnx.ncnn.bin

133 MB

decoder_jit_trace-pnnx.ncnn.bin

509 KB

joiner_jit_trace-pnnx.ncnn.bin

1.4 MB

You can see that the file sizes of the models after conversion are about one half of the models before conversion:

encoder: 266 MB vs 133 MB

decoder: 1022 KB vs 509 KB

joiner: 2.8 MB vs 1.4 MB

The reason is that by default pnnx converts float32 parameters to float16. A float32 parameter occupies 4 bytes, while it is 2 bytes for float16. Thus, it is twice smaller after conversion.

Hint

If you use pnnx ./encoder_jit_trace-pnnx.pt fp16=0, then pnnx won’t convert float32 to float16.

5. Test the exported models in icefall
Note

We assume you have set up the environment variable PYTHONPATH when building ncnn.

Now we have successfully converted our pre-trained model to ncnn format. The generated 6 files are what we need. You can use the following code to test the converted models:

python3 ./pruned_transducer_stateless7_streaming/streaming-ncnn-decode.py \
  --tokens ./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/data/lang_bpe_500/tokens.txt \
  --encoder-param-filename ./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/encoder_jit_trace-pnnx.ncnn.param \
  --encoder-bin-filename ./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/encoder_jit_trace-pnnx.ncnn.bin \
  --decoder-param-filename ./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/decoder_jit_trace-pnnx.ncnn.param \
  --decoder-bin-filename ./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/decoder_jit_trace-pnnx.ncnn.bin \
  --joiner-param-filename ./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/joiner_jit_trace-pnnx.ncnn.param \
  --joiner-bin-filename ./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/joiner_jit_trace-pnnx.ncnn.bin \
  ./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/test_wavs/1089-134686-0001.wav
Hint

ncnn supports only batch size == 1, so streaming-ncnn-decode.py accepts only 1 wave file as input.

The output is given below:

2023-02-27 20:43:40,283 INFO [streaming-ncnn-decode.py:349] {'tokens': './icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/data/lang_bpe_500/tokens.txt', 'encoder_param_filename': './icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/encoder_jit_trace-pnnx.ncnn.param', 'encoder_bin_filename': './icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/encoder_jit_trace-pnnx.ncnn.bin', 'decoder_param_filename': './icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/decoder_jit_trace-pnnx.ncnn.param', 'decoder_bin_filename': './icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/decoder_jit_trace-pnnx.ncnn.bin', 'joiner_param_filename': './icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/joiner_jit_trace-pnnx.ncnn.param', 'joiner_bin_filename': './icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/exp/joiner_jit_trace-pnnx.ncnn.bin', 'sound_filename': './icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/test_wavs/1089-134686-0001.wav'}
2023-02-27 20:43:41,260 INFO [streaming-ncnn-decode.py:357] Constructing Fbank computer
2023-02-27 20:43:41,264 INFO [streaming-ncnn-decode.py:360] Reading sound files: ./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/test_wavs/1089-134686-0001.wav
2023-02-27 20:43:41,269 INFO [streaming-ncnn-decode.py:365] torch.Size([106000])
2023-02-27 20:43:41,280 INFO [streaming-ncnn-decode.py:372] number of states: 35
2023-02-27 20:43:45,026 INFO [streaming-ncnn-decode.py:410] ./icefall-asr-librispeech-pruned-transducer-stateless7-streaming-2022-12-29/test_wavs/1089-134686-0001.wav
2023-02-27 20:43:45,026 INFO [streaming-ncnn-decode.py:411] AFTER EARLY NIGHTFALL THE YELLOW LAMPS WOULD LIGHT UP HERE AND THERE THE SQUALID QUARTER OF THE BROTHELS
Congratulations! You have successfully exported a model from PyTorch to ncnn!

6. Modify the exported encoder for sherpa-ncnn
In order to use the exported models in sherpa-ncnn, we have to modify encoder_jit_trace-pnnx.ncnn.param.

Let us have a look at the first few lines of encoder_jit_trace-pnnx.ncnn.param:

7767517
2028 2547
Input                    in0                      0 1 in0
Explanation of the above three lines:

7767517, it is a magic number and should not be changed.

2028 2547, the first number 2028 specifies the number of layers in this file, while 2547 specifies the number of intermediate outputs of this file

Input in0 0 1 in0, Input is the layer type of this layer; in0 is the layer name of this layer; 0 means this layer has no input; 1 means this layer has one output; in0 is the output name of this layer.

We need to add 1 extra line and also increment the number of layers. The result looks like below:

7767517
2029 2547
SherpaMetaData           sherpa_meta_data1        0 0 0=2 1=32 2=4 3=7 15=1 -23316=5,2,4,3,2,4 -23317=5,384,384,384,384,384 -23318=5,192,192,192,192,192 -23319=5,1,2,4,8,2 -23320=5,31,31,31,31,31
Input                    in0                      0 1 in0
Explanation

7767517, it is still the same

2029 2547, we have added an extra layer, so we need to update 2028 to 2029. We don’t need to change 2547 since the newly added layer has no inputs or outputs.

SherpaMetaData  sherpa_meta_data1  0 0 0=2 1=32 2=4 3=7 -23316=5,2,4,3,2,4 -23317=5,384,384,384,384,384 -23318=5,192,192,192,192,192 -23319=5,1,2,4,8,2 -23320=5,31,31,31,31,31 This line is newly added. Its explanation is given below:

SherpaMetaData is the type of this layer. Must be SherpaMetaData.

sherpa_meta_data1 is the name of this layer. Must be sherpa_meta_data1.

0 0 means this layer has no inputs or output. Must be 0 0

0=2, 0 is the key and 2 is the value. MUST be 0=2

1=32, 1 is the key and 32 is the value of the parameter --decode-chunk-len that you provided when running ./pruned_transducer_stateless7_streaming/export-for-ncnn.py.

2=4, 2 is the key and 4 is the value of the parameter --num-left-chunks that you provided when running ./pruned_transducer_stateless7_streaming/export-for-ncnn.py.

3=7, 3 is the key and 7 is the value of for the amount of padding used in the Conv2DSubsampling layer. It should be 7 for zipformer if you don’t change zipformer.py.

15=1, attribute 15, this is the model version. Starting from sherpa-ncnn v2.0, we require that the model version has to be >= 1.

-23316=5,2,4,3,2,4, attribute 16, this is an array attribute. It is attribute 16 since -23300 - (-23316) = 16. The first element of the array is the length of the array, which is 5 in our case. 2,4,3,2,4 is the value of --num-encoder-layers``that you provided when running ``./pruned_transducer_stateless7_streaming/export-for-ncnn.py.

-23317=5,384,384,384,384,384, attribute 17. The first element of the array is the length of the array, which is 5 in our case. 384,384,384,384,384 is the value of --encoder-dims``that you provided when running ``./pruned_transducer_stateless7_streaming/export-for-ncnn.py.

-23318=5,192,192,192,192,192, attribute 18. The first element of the array is the length of the array, which is 5 in our case. 192,192,192,192,192 is the value of --attention-dims that you provided when running ./pruned_transducer_stateless7_streaming/export-for-ncnn.py.

-23319=5,1,2,4,8,2, attribute 19. The first element of the array is the length of the array, which is 5 in our case. 1,2,4,8,2 is the value of --zipformer-downsampling-factors that you provided when running ./pruned_transducer_stateless7_streaming/export-for-ncnn.py.

-23320=5,31,31,31,31,31, attribute 20. The first element of the array is the length of the array, which is 5 in our case. 31,31,31,31,31 is the value of --cnn-module-kernels that you provided when running ./pruned_transducer_stateless7_streaming/export-for-ncnn.py.

For ease of reference, we list the key-value pairs that you need to add in the following table. If your model has a different setting, please change the values for SherpaMetaData accordingly. Otherwise, you will be SAD.

key

value

0

2 (fixed)

1

-decode-chunk-len

2

--num-left-chunks

3

7 (if you don’t change code)

15

1 (The model version)

-23316

--num-encoder-layer

-23317

--encoder-dims

-23318

--attention-dims

-23319

--zipformer-downsampling-factors

-23320

--cnn-module-kernels

Input in0 0 1 in0. No need to change it.

Caution

When you add a new layer SherpaMetaData, please remember to update the number of layers. In our case, update 2028 to 2029. Otherwise, you will be SAD later.

Hint

After adding the new layer SherpaMetaData, you cannot use this model with streaming-ncnn-decode.py anymore since SherpaMetaData is supported only in sherpa-ncnn.

Hint

ncnn is very flexible. You can add new layers to it just by text-editing the param file! You don’t need to change the bin file.

Now you can use this model in sherpa-ncnn. Please refer to the following documentation:

Linux/macOS/Windows/arm/aarch64: https://k2-fsa.github.io/sherpa/ncnn/install/index.html

Android: https://k2-fsa.github.io/sherpa/ncnn/android/index.html

iOS: https://k2-fsa.github.io/sherpa/ncnn/ios/index.html

Python: https://k2-fsa.github.io/sherpa/ncnn/python/index.html

We have a list of pre-trained models that have been exported for sherpa-ncnn:

https://k2-fsa.github.io/sherpa/ncnn/pretrained_models/index.html

You can find more usages there.