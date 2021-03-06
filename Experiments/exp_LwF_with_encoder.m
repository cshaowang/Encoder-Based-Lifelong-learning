%This is a demo  of Encoder Based Lifelong Learning showing how to learn a
%set of tasks in a sequence
%Task sequence: Imagenet -> Scenes -> Birds
%This code is based on matconvnet-b23.
%
%For more details, see A. Rannen Triki, R. Aljundi, M. B. Blaschko, and T. Tuytelaars, Encoder Based Lifelong 
%Learning. ICCV 2017
%
% Prerequisite: Please make sure that:
% 1. Imagenet data is stored correctly
%  The ILSVRC data ships in several TAR archives that can be
%    obtained from the ILSVRC challenge website. You will need:
%
%    ILSVRC2012_img_train.tar
%    ILSVRC2012_img_val.tar
%    ILSVRC2012_img_test.tar
%    ILSVRC2012_devkit.tar
%
%    Note that images in the CLS-LOC challenge are the same for the 2012, 2013,
%    and 2014 edition of ILSVRC, but that the development kit
%    is different. However, all devkit versions should work.
%
%    In order to use the ILSVRC data with these scripts, please
%    unpack it as follows. Create a root folder <DATA> 
%
%    (note that this can be a simlink). Use the 'dataDir' option to
%    specify a different path.
%
%    Within this folder, create the following hierarchy:
%
%    <DATA>/images/train/ : content of ILSVRC2012_img_train.tar
%    <DATA>/images/val/ : content of ILSVRC2012_img_val.tar
%    <DATA>/images/test/ : content of ILSVRC2012_img_test.tar
%    <DATA>/ILSVRC2012_devkit : content of ILSVRC2012_devkit.tar
%   Change the first opts.dataDir below to <DATA>.
% 2. Download Scenes and Birds datasets, and store them in a MatConvNet
% database := a structure of two fields:
%   - images: a structure of 3 fields data containing either the images of
%   links to the images, labels and sets (1= training, 2=validation (if any),
%   3=test)
%   - meta: contains several informations about the dataset Typically, it
%   has the fiels classes (the names of the classes), imageAverage and
%   inputSize.
% In the following code, we consider that this databases are stored under
% the folders Task2 and Task3 unde the name original_data.mat.
% Please make sure to change the paths if needed.
%
% Authors: Rahaf Aljundi & Amal Rannen Triki
% 
% See the COPYING file.

MatconvnetPath = '/path/to/matconvnet'; %Change this path
do_compile=1;
use_gpu=1;
setup_LwF_with_encoder(MatconvnetPath, do_compile,use_gpu );

%% Extract pool5 output for Imagenet
% We use a pretrained model for Imagenet, using AlexNet architecture
cd '/path/to/this/folder'; %Change this path
%opts: contains the parameters for recording the pool5 features
opts.dataDir = '/path/to/Imagenet'; %Change this path
opts.modelPath = 'imagenet-caffe-alex.mat';
opts.train.data.expDir = '/path/to/Imagenet/features'; %Change this path
opts.train.output_layer_id=16;
[~,imdb,~]=cnn_imagenet_evaluate(opts);%record the pool 5 features of imagenet
mkdir('Task1')
save('Task1/feat_dataset1.mat','imdb');
clear opts
%% Train Imagenet autoencoder
opts.expDir='Task1/Autoencoder/';
opts.imdbPath='Task1/feat_dataset1.mat';
opts.input_size=9216;
opts.nesterovUpdate = false;
opts.code_size=300;
opts.numEpochs=100;
opts.batchSize=5000;
cnn_autoencoder_with_classerror(opts);

%% Prepare the model for Scenes
clear opts
opts.split_layer=16;
opts.expDir = 'Task2/LwF_with_autoencoder' ;
opts.orgNetPath= 'imagenet-caffe-alex.mat';
opts.imdb_path='Task2/original_data.mat';
opts.outputnet_path='Task2/LwF_with_autoencoder/model-task-2-initial.mat';
opts.output_imdb_path='Task2/augmented_data.mat';
opts.train.learningRate = [0.0004*ones(1, 54)  0.1*0.0004*ones(1, 18)] ;
opts.freezeDir='Task2/FreezedNet';
opts.train.batchSize=128;
opts.aug_output_path='Task2/data/aug-dataset-2' ;
opts.old_aug_imdb_path='';
opts.autoencoder_dir = 'Task1/Autoencoder/';
opts.scale = 1 ;
opts.extract_images=true;
opts.alpha=1e-1;
add_new_task(opts);

%% Train the model for Scenes
tr_opts = opts;
tr_opts.imdbPath = 'Task2/augmented_data.mat';
tr_opts.modelPath='Task2/LwF_with_autoencoder/model-task-2-initial.mat';
cnn_lwf_with_encoder(tr_opts);


%% Contruct pool5-feature database for Scenes
last = findLastCheckpoint('Task2/LwF_with_autoencoder/');
net = get_last_task_network(sprintf('Task2/LwF_with_autoencoder/net-epoch-%d.mat',last));
if isfield(net, 'net'), net = net.net; end;

imdb = load(tr_opts.imdbPath);
if isfield(imdb, 'imdb'), imdb = imdb.imdb; end;

im = imdb.images.data;
sets= imdb.images.set;
imdb = [];
imdb.images=[];
imdb.images.data=[];
imdb.images.set = [];
for i=1:100:size(im,4)
    res = vl_simplenn_LwF_encoder(net,im(:,:,:,i:i+99));
    imdb.images.data = cat(4, imdb.images.data, reshape(res(16).x, 1,1,9216,[]));
    imdb.images.set = [imdb.images.set, sets(i:i+99)];
end;
save('Task2/feat_dataset2.mat', 'imdb');

%% Train autoencoder for Scenes
clear opts tr_opts;
opts.expDir='Task2/Autoencoder/';
opts.imdbPath='Task2/feat_dataset2.mat';
opts.input_size=9216;
opts.nesterovUpdate = false;
opts.code_size=100;
opts.numEpochs=100;
opts.batchSize=5000;
cnn_autoencoder_with_classerror(opts);
        
%% Prepare the model for Birds
clear opts
opts.split_layer=16;
opts.expDir = 'Task3/LwF_with_autoencoder' ;
opts.orgNetPath= sprintf('Task2/LwF_with_autoencoder/net-epoch-%d.mat',last);
opts.imdb_path='Task3/original_data.mat';
opts.outputnet_path='Task3/LwF_with_autoencoder/model-task-3-initial.mat';
opts.output_imdb_path='Task3/augmented_data.mat';
opts.train.learningRate = [0.0004*ones(1, 54)  0.1*0.0004*ones(1, 18)] ;
opts.freezeDir='Task3/FreezedNet';
opts.train.batchSize=128;
opts.aug_output_path='Task3/data/aug-dataset-3' ;
opts.old_aug_imdb_path='';
opts.autoencoder_dir = 'Task3/Autoencoder/';
opts.scale = 1 ;
opts.extract_images=true;
opts.alpha=1e-1;
add_new_task(opts);

%% Train the model for Birds
tr_opts = opts;
tr_opts.imdbPath = 'Task3/augmented_data.mat';
tr_opts.modelPath='Task3/LwF_with_autoencoder/model-task-2-initial.mat';
cnn_lwf_with_encoder(tr_opts);





