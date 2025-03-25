7. (Optional) int8 quantization with sherpa-ncnn
This step is optional.

In this step, we describe how to quantize our model with int8.

Change 4. Export torchscript model via pnnx to disable fp16 when using pnnx:

cd icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/

pnnx ./encoder_jit_trace-pnnx.pt fp16=0
pnnx ./decoder_jit_trace-pnnx.pt
pnnx ./joiner_jit_trace-pnnx.pt fp16=0
Note

We add fp16=0 when exporting the encoder and joiner. ncnn does not support quantizing the decoder model yet. We will update this documentation once ncnn supports it. (Maybe in this year, 2023).

It will generate the following files

ls -lh icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/*_jit_trace-pnnx.ncnn.{param,bin}

-rw-r--r-- 1 kuangfangjun root 503K Jan 11 15:56 icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/decoder_jit_trace-pnnx.ncnn.bin
-rw-r--r-- 1 kuangfangjun root  437 Jan 11 15:56 icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/decoder_jit_trace-pnnx.ncnn.param
-rw-r--r-- 1 kuangfangjun root 283M Jan 11 15:56 icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/encoder_jit_trace-pnnx.ncnn.bin
-rw-r--r-- 1 kuangfangjun root  79K Jan 11 15:56 icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/encoder_jit_trace-pnnx.ncnn.param
-rw-r--r-- 1 kuangfangjun root 3.0M Jan 11 15:56 icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/joiner_jit_trace-pnnx.ncnn.bin
-rw-r--r-- 1 kuangfangjun root  488 Jan 11 15:56 icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/joiner_jit_trace-pnnx.ncnn.param
Let us compare again the file sizes:

File name

File size

encoder_jit_trace-pnnx.pt

283 MB

decoder_jit_trace-pnnx.pt

1010 KB

joiner_jit_trace-pnnx.pt

3.0 MB

encoder_jit_trace-pnnx.ncnn.bin (fp16)

142 MB

decoder_jit_trace-pnnx.ncnn.bin (fp16)

503 KB

joiner_jit_trace-pnnx.ncnn.bin (fp16)

1.5 MB

encoder_jit_trace-pnnx.ncnn.bin (fp32)

283 MB

joiner_jit_trace-pnnx.ncnn.bin (fp32)

3.0 MB

You can see that the file sizes are doubled when we disable fp16.

Note

You can again use streaming-ncnn-decode.py to test the exported models.

Next, follow 6. Modify the exported encoder for sherpa-ncnn to modify encoder_jit_trace-pnnx.ncnn.param.

Change

7767517
1060 1342
Input                    in0                      0 1 in0
to

7767517
1061 1342
SherpaMetaData           sherpa_meta_data1        0 0 0=1 1=12 2=32 3=31 4=8 5=32 6=8 7=512
Input                    in0                      0 1 in0
Caution

Please follow 6. Modify the exported encoder for sherpa-ncnn to change the values for SherpaMetaData if your model uses a different setting.

Next, let us compile sherpa-ncnn since we will quantize our models within sherpa-ncnn.

# We will download sherpa-ncnn to $HOME/open-source/
# You can change it to anywhere you like.
cd $HOME
mkdir -p open-source

cd open-source
git clone https://github.com/k2-fsa/sherpa-ncnn
cd sherpa-ncnn
mkdir build
cd build
cmake ..
make -j 4

./bin/generate-int8-scale-table

export PATH=$HOME/open-source/sherpa-ncnn/build/bin:$PATH
The output of the above commands are:

(py38) kuangfangjun:build$ generate-int8-scale-table
Please provide 10 arg. Currently given: 1
Usage:
generate-int8-scale-table encoder.param encoder.bin decoder.param decoder.bin joiner.param joiner.bin encoder-scale-table.txt joiner-scale-table.txt wave_filenames.txt

Each line in wave_filenames.txt is a path to some 16k Hz mono wave file.
We need to create a file wave_filenames.txt, in which we need to put some calibration wave files. For testing purpose, we put the test_wavs from the pre-trained model repository https://huggingface.co/Zengwei/icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05

cd egs/librispeech/ASR
cd icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/

cat <<EOF > wave_filenames.txt
../test_wavs/1089-134686-0001.wav
../test_wavs/1221-135766-0001.wav
../test_wavs/1221-135766-0002.wav
EOF
Now we can calculate the scales needed for quantization with the calibration data:

cd egs/librispeech/ASR
cd icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/

generate-int8-scale-table \
  ./encoder_jit_trace-pnnx.ncnn.param \
  ./encoder_jit_trace-pnnx.ncnn.bin \
  ./decoder_jit_trace-pnnx.ncnn.param \
  ./decoder_jit_trace-pnnx.ncnn.bin \
  ./joiner_jit_trace-pnnx.ncnn.param \
  ./joiner_jit_trace-pnnx.ncnn.bin \
  ./encoder-scale-table.txt \
  ./joiner-scale-table.txt \
  ./wave_filenames.txt
The output logs are in the following:

Don't Use GPU. has_gpu: 0, config.use_vulkan_compute: 1
num encoder conv layers: 88
num joiner conv layers: 3
num files: 3
Processing ../test_wavs/1089-134686-0001.wav
Processing ../test_wavs/1221-135766-0001.wav
Processing ../test_wavs/1221-135766-0002.wav
Processing ../test_wavs/1089-134686-0001.wav
Processing ../test_wavs/1221-135766-0001.wav
Processing ../test_wavs/1221-135766-0002.wav
----------encoder----------
conv_87                                  : max = 15.942385        threshold = 15.938493        scale = 7.968131
conv_88                                  : max = 35.442448        threshold = 15.549335        scale = 8.167552
conv_89                                  : max = 23.228289        threshold = 8.001738         scale = 15.871552
linear_90                                : max = 3.976146         threshold = 1.101789         scale = 115.267128
linear_91                                : max = 6.962030         threshold = 5.162033         scale = 24.602713
linear_92                                : max = 12.323041        threshold = 3.853959         scale = 32.953129
linear_94                                : max = 6.905416         threshold = 4.648006         scale = 27.323545
linear_93                                : max = 6.905416         threshold = 5.474093         scale = 23.200188
linear_95                                : max = 1.888012         threshold = 1.403563         scale = 90.483986
linear_96                                : max = 6.856741         threshold = 5.398679         scale = 23.524273
linear_97                                : max = 9.635942         threshold = 2.613655         scale = 48.590950
linear_98                                : max = 6.460340         threshold = 5.670146         scale = 22.398010
linear_99                                : max = 9.532276         threshold = 2.585537         scale = 49.119396
linear_101                               : max = 6.585871         threshold = 5.719224         scale = 22.205809
linear_100                               : max = 6.585871         threshold = 5.751382         scale = 22.081648
linear_102                               : max = 1.593344         threshold = 1.450581         scale = 87.551147
linear_103                               : max = 6.592681         threshold = 5.705824         scale = 22.257959
linear_104                               : max = 8.752957         threshold = 1.980955         scale = 64.110489
linear_105                               : max = 6.696240         threshold = 5.877193         scale = 21.608953
linear_106                               : max = 9.059659         threshold = 2.643138         scale = 48.048950
linear_108                               : max = 6.975461         threshold = 4.589567         scale = 27.671457
linear_107                               : max = 6.975461         threshold = 6.190381         scale = 20.515701
linear_109                               : max = 3.710759         threshold = 2.305635         scale = 55.082436
linear_110                               : max = 7.531228         threshold = 5.731162         scale = 22.159557
linear_111                               : max = 10.528083        threshold = 2.259322         scale = 56.211544
linear_112                               : max = 8.148807         threshold = 5.500842         scale = 23.087374
linear_113                               : max = 8.592566         threshold = 1.948851         scale = 65.166611
linear_115                               : max = 8.437109         threshold = 5.608947         scale = 22.642395
linear_114                               : max = 8.437109         threshold = 6.193942         scale = 20.503904
linear_116                               : max = 3.966980         threshold = 3.200896         scale = 39.676392
linear_117                               : max = 9.451303         threshold = 6.061664         scale = 20.951344
linear_118                               : max = 12.077262        threshold = 3.965800         scale = 32.023804
linear_119                               : max = 9.671615         threshold = 4.847613         scale = 26.198460
linear_120                               : max = 8.625638         threshold = 3.131427         scale = 40.556595
linear_122                               : max = 10.274080        threshold = 4.888716         scale = 25.978189
linear_121                               : max = 10.274080        threshold = 5.420480         scale = 23.429659
linear_123                               : max = 4.826197         threshold = 3.599617         scale = 35.281532
linear_124                               : max = 11.396383        threshold = 7.325849         scale = 17.335875
linear_125                               : max = 9.337198         threshold = 3.941410         scale = 32.221970
linear_126                               : max = 9.699965         threshold = 4.842878         scale = 26.224073
linear_127                               : max = 8.775370         threshold = 3.884215         scale = 32.696438
linear_129                               : max = 9.872276         threshold = 4.837319         scale = 26.254213
linear_128                               : max = 9.872276         threshold = 7.180057         scale = 17.687883
linear_130                               : max = 4.150427         threshold = 3.454298         scale = 36.765789
linear_131                               : max = 11.112692        threshold = 7.924847         scale = 16.025545
linear_132                               : max = 11.852893        threshold = 3.116593         scale = 40.749626
linear_133                               : max = 11.517084        threshold = 5.024665         scale = 25.275314
linear_134                               : max = 10.683807        threshold = 3.878618         scale = 32.743618
linear_136                               : max = 12.421055        threshold = 6.322729         scale = 20.086264
linear_135                               : max = 12.421055        threshold = 5.309880         scale = 23.917679
linear_137                               : max = 4.827781         threshold = 3.744595         scale = 33.915554
linear_138                               : max = 14.422395        threshold = 7.742882         scale = 16.402161
linear_139                               : max = 8.527538         threshold = 3.866123         scale = 32.849449
linear_140                               : max = 12.128619        threshold = 4.657793         scale = 27.266134
linear_141                               : max = 9.839593         threshold = 3.845993         scale = 33.021378
linear_143                               : max = 12.442304        threshold = 7.099039         scale = 17.889746
linear_142                               : max = 12.442304        threshold = 5.325038         scale = 23.849592
linear_144                               : max = 5.929444         threshold = 5.618206         scale = 22.605080
linear_145                               : max = 13.382126        threshold = 9.321095         scale = 13.625010
linear_146                               : max = 9.894987         threshold = 3.867645         scale = 32.836517
linear_147                               : max = 10.915313        threshold = 4.906028         scale = 25.886522
linear_148                               : max = 9.614287         threshold = 3.908151         scale = 32.496181
linear_150                               : max = 11.724932        threshold = 4.485588         scale = 28.312899
linear_149                               : max = 11.724932        threshold = 5.161146         scale = 24.606939
linear_151                               : max = 7.164453         threshold = 5.847355         scale = 21.719223
linear_152                               : max = 13.086471        threshold = 5.984121         scale = 21.222834
linear_153                               : max = 11.099524        threshold = 3.991601         scale = 31.816805
linear_154                               : max = 10.054585        threshold = 4.489706         scale = 28.286930
linear_155                               : max = 12.389185        threshold = 3.100321         scale = 40.963501
linear_157                               : max = 9.982999         threshold = 5.154796         scale = 24.637253
linear_156                               : max = 9.982999         threshold = 8.537706         scale = 14.875190
linear_158                               : max = 8.420287         threshold = 6.502287         scale = 19.531588
linear_159                               : max = 25.014746        threshold = 9.423280         scale = 13.477261
linear_160                               : max = 45.633553        threshold = 5.715335         scale = 22.220921
linear_161                               : max = 20.371849        threshold = 5.117830         scale = 24.815203
linear_162                               : max = 12.492933        threshold = 3.126283         scale = 40.623318
linear_164                               : max = 20.697504        threshold = 4.825712         scale = 26.317358
linear_163                               : max = 20.697504        threshold = 5.078367         scale = 25.008038
linear_165                               : max = 9.023975         threshold = 6.836278         scale = 18.577358
linear_166                               : max = 34.860619        threshold = 7.259792         scale = 17.493614
linear_167                               : max = 30.380934        threshold = 5.496160         scale = 23.107042
linear_168                               : max = 20.691216        threshold = 4.733317         scale = 26.831076
linear_169                               : max = 9.723948         threshold = 3.952728         scale = 32.129707
linear_171                               : max = 21.034811        threshold = 5.366547         scale = 23.665123
linear_170                               : max = 21.034811        threshold = 5.356277         scale = 23.710501
linear_172                               : max = 10.556884        threshold = 5.729481         scale = 22.166058
linear_173                               : max = 20.033039        threshold = 10.207264        scale = 12.442120
linear_174                               : max = 11.597379        threshold = 2.658676         scale = 47.768131
----------joiner----------
linear_2                                 : max = 19.293503        threshold = 14.305265        scale = 8.877850
linear_1                                 : max = 10.812222        threshold = 8.766452         scale = 14.487047
linear_3                                 : max = 0.999999         threshold = 0.999755         scale = 127.031174
ncnn int8 calibration table create success, best wish for your int8 inference has a low accuracy loss...\(^0^)/...233...
It generates the following two files:

$ ls -lh encoder-scale-table.txt joiner-scale-table.txt
-rw-r--r-- 1 kuangfangjun root 955K Jan 11 17:28 encoder-scale-table.txt
-rw-r--r-- 1 kuangfangjun root  18K Jan 11 17:28 joiner-scale-table.txt
Caution

Definitely, you need more calibration data to compute the scale table.

Finally, let us use the scale table to quantize our models into int8.

ncnn2int8

usage: ncnn2int8 [inparam] [inbin] [outparam] [outbin] [calibration table]
First, we quantize the encoder model:

cd egs/librispeech/ASR
cd icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/

ncnn2int8 \
  ./encoder_jit_trace-pnnx.ncnn.param \
  ./encoder_jit_trace-pnnx.ncnn.bin \
  ./encoder_jit_trace-pnnx.ncnn.int8.param \
  ./encoder_jit_trace-pnnx.ncnn.int8.bin \
  ./encoder-scale-table.txt
Next, we quantize the joiner model:

ncnn2int8 \
  ./joiner_jit_trace-pnnx.ncnn.param \
  ./joiner_jit_trace-pnnx.ncnn.bin \
  ./joiner_jit_trace-pnnx.ncnn.int8.param \
  ./joiner_jit_trace-pnnx.ncnn.int8.bin \
  ./joiner-scale-table.txt
The above two commands generate the following 4 files:

-rw-r--r-- 1 kuangfangjun root  99M Jan 11 17:34 encoder_jit_trace-pnnx.ncnn.int8.bin
-rw-r--r-- 1 kuangfangjun root  78K Jan 11 17:34 encoder_jit_trace-pnnx.ncnn.int8.param
-rw-r--r-- 1 kuangfangjun root 774K Jan 11 17:35 joiner_jit_trace-pnnx.ncnn.int8.bin
-rw-r--r-- 1 kuangfangjun root  496 Jan 11 17:35 joiner_jit_trace-pnnx.ncnn.int8.param
Congratulations! You have successfully quantized your model from float32 to int8.

Caution

ncnn.int8.param and ncnn.int8.bin must be used in pairs.

You can replace ncnn.param and ncnn.bin with ncnn.int8.param and ncnn.int8.bin in sherpa-ncnn if you like.

For instance, to use only the int8 encoder in sherpa-ncnn, you can replace the following invocation:

cd egs/librispeech/ASR
cd icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/

sherpa-ncnn \
  ../data/lang_bpe_500/tokens.txt \
  ./encoder_jit_trace-pnnx.ncnn.param \
  ./encoder_jit_trace-pnnx.ncnn.bin \
  ./decoder_jit_trace-pnnx.ncnn.param \
  ./decoder_jit_trace-pnnx.ncnn.bin \
  ./joiner_jit_trace-pnnx.ncnn.param \
  ./joiner_jit_trace-pnnx.ncnn.bin \
  ../test_wavs/1089-134686-0001.wav
with

cd egs/librispeech/ASR
cd icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05/exp/

sherpa-ncnn \
  ../data/lang_bpe_500/tokens.txt \
  ./encoder_jit_trace-pnnx.ncnn.int8.param \
  ./encoder_jit_trace-pnnx.ncnn.int8.bin \
  ./decoder_jit_trace-pnnx.ncnn.param \
  ./decoder_jit_trace-pnnx.ncnn.bin \
  ./joiner_jit_trace-pnnx.ncnn.param \
  ./joiner_jit_trace-pnnx.ncnn.bin \
  ../test_wavs/1089-134686-0001.wav
The following table compares again the file sizes:

File name

File size

encoder_jit_trace-pnnx.pt

283 MB

decoder_jit_trace-pnnx.pt

1010 KB

joiner_jit_trace-pnnx.pt

3.0 MB

encoder_jit_trace-pnnx.ncnn.bin (fp16)

142 MB

decoder_jit_trace-pnnx.ncnn.bin (fp16)

503 KB

joiner_jit_trace-pnnx.ncnn.bin (fp16)

1.5 MB

encoder_jit_trace-pnnx.ncnn.bin (fp32)

283 MB

joiner_jit_trace-pnnx.ncnn.bin (fp32)

3.0 MB

encoder_jit_trace-pnnx.ncnn.int8.bin

99 MB

joiner_jit_trace-pnnx.ncnn.int8.bin

774 KB

You can see that the file sizes of the model after int8 quantization are much smaller.

Hint

Currently, only linear layers and convolutional layers are quantized with int8, so you don’t see an exact 4x reduction in file sizes.

Note

You need to test the recognition accuracy after int8 quantization.

You can find the speed comparison at https://github.com/k2-fsa/sherpa-ncnn/issues/44.

That’s it! Have fun with sherpa-ncnn!