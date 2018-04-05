%% Semantic 3D reconstruction of SUNCG indoor room dataset
%  - Reading of json scene hierarchy files
%  - Reconstruction of ceiling-floor-walls per room
%  - Reconstruction of indoor objects per room
%  - Saving of semantic 3D grid
%  - Saving of reconstructed rooms and its semantic components
%    into .wrl visualisation files

close all;

%% Read the path as input argument
suncgToolboxPath = 'ToolBox/';

addpath(suncgToolboxPath);
addpath(strcat(suncgToolboxPath,'/utils'));
addpath(strcat(suncgToolboxPath,'/benchmark'));

load(fullfile(suncgToolboxPath, 'ClassMapping.mat'));
load(fullfile(suncgToolboxPath, 'suncgObjcategory.mat'));

% Compile C++
% mex -I"../Eigen/eigen" -outdir ToolBox/MyMexFiles -c ToolBox/MyMexFiles/ioTools.cpp
% mex -I"../Eigen/eigen" -outdir ToolBox/MyMexFiles -c ToolBox/MyMexFiles/volumetricFusionTools.cpp
% mex -I"../Eigen/eigen" -lpthread -lX11 ToolBox/MyMexFiles/ioTools.o ToolBox/MyMexFiles/volumetricFusionTools.o ToolBox/MyMexFiles/convertGrid.cpp

suncgDataPath = rawDataPath;

%% Result directory

% DEBUG
% Datetime as name folder
% timestamp = datestr(now,'dd-mm-yyyy_HH:MM:SS');
% outputFolder = strcat(outputdir,'/Results_');
% outputFolder = strcat(outputFolder, timestamp);
% outputFolder = strcat('../', outputFolder);

outputFolder = outputdir;
if(~exist(outputFolder))
    mkdir(outputFolder);
end

%% Load Frequent Objects into a map structure(input argument readMap)
[objectMap,scaleMap, maxObjs,minObjs] = computeFrequentObjects(readMap);
capacity = 800;

%% Color - Classes

colorPalette = distinguishable_colors(36);
mapIds = 0:36;
numClasses = length(mapIds);
[~,wallID] = getobjclassSUNCG('wall',objcategory);
[~,ceilID ] = getobjclassSUNCG('ceiling',objcategory);
[~,floorID] = getobjclassSUNCG('floor'  ,objcategory);

%% List of scenes

% Read all the scene directories
listScenes = dir( fullfile(suncgDataPath,'house'));
listScenes = listScenes(3:end);

% Random Shuffle of scenes
if suffle %&& size(listScenes,1)>rooms
    fprintf('\nRoom Order is Suffled...\n\n');
    rng('shuffle')
    listScenes = listScenes(randperm(length(listScenes)));
end


numScenes = size(listScenes,1);


% Pass the number of rooms to be generated as input argument
roomCounter = 1;
roomThreshold = 40;
minObjectsInRoom = 10;

%% Reconstruction Time Matrix

times = zeros(totalRooms,4);
bboxold = [];
resultFolder = [];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% Read files

% For all scenes
for sceneIdx = 1:numScenes

    try
        %% Read House file
        sceneID = listScenes(sceneIdx).name;
        fprintf('Reading Scene:%s \n\n',sceneID);
        fprintf('Loading house.json\n');
        house  = loadjson(fullfile(suncgDataPath,'house', sceneID,'house.json'));
        % Floor
        levels = house.levels;
        bboxold = [];

        % For all floors
        % for level_idx = 1:1%length(levels)
        
        % We only take the first floor
        level_idx = 1;
        
        % Rooms per floor
        nodes  = house.levels{level_idx}.nodes;

	roomCounter = 1;

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % For every room
        for node_idx = 1:length(nodes)

            if strcmp(nodes{node_idx}.type, 'Room')

                %%%%
                tic;
                %%%%

                room    = nodes{node_idx};
                bbox   = nodes{node_idx}.bbox;
                sceneOrigin = bbox.min;

                % Check if the previous room is included in the next room
                % or next room is included to previous one
                if(isempty(bboxold) || ~roomIncluded(bboxold, bbox))

                    % Voxel size as input argument
                    voxOriginWorld = bbox.min;
                    voxSize = bbox.max - bbox.min;
                    gridSize = floor(voxSize/voxUnit);

                    if discard && ( (isRoomVolumeInsufficient(voxSize, roomThreshold) || bbox.max(2) > 3.5 ) )
                        fprintf('\nRoom discarded due to insufficient size or content.\n\n\n');
                        continue;
                    end

                    %% Create a voxel grid
                    fprintf('Creating voxel grid\n');
                    [gridPtsWorldX, gridPtsWorldY, gridPtsWorldZ, gridPtsWorld, gridPtsLabel, inRoom] = ... 
                        constructGrid(voxOriginWorld, voxUnit, voxSize);

                else
                    if(~isempty(resultFolder))
                        status = rmdir(resultFolder,'s');
                    end
                    fprintf('\n\nThis room will be merged with the previous one. Old folder is removed!\n\n')
                end

                %%%%%%%%%%%%%%%%%%%%%%%%%%%
                times(roomCounter,1) = toc;
                %%%%%%%%%%%%%%%%%%%%%%%%%%%

                fprintf(sprintf('Reading room #%d\n', node_idx));

                %% Room structure
                fprintf('Loading room structure\n');

                % Load ceiling, floor, wall
                ceilPath  = [fullfile(suncgDataPath, 'room', sceneID, room.modelId) 'c.obj'];
                floorPath = [fullfile(suncgDataPath, 'room', sceneID, room.modelId) 'f.obj'];
                wallPath  = [fullfile(suncgDataPath, 'room', sceneID, room.modelId) 'w.obj'];

                %% Ceiling grid in the room

                fprintf('Reading ceiling\n');
                gridPtsLabel = generateCeilingFloor( ...
                                ceilPath, ceilID, size(inRoom), voxUnit, ...
                                voxOriginWorld, gridPtsWorld, ...
                                gridPtsWorldX, gridPtsWorldZ, ...
                                gridPtsLabel ...
                                );

                %% Floor grid in the room
                % exactly like ceiling part
                fprintf('Reading floor\n');                              
                gridPtsLabel = generateCeilingFloor(...
                                floorPath, floorID, ...
                                size(inRoom), voxUnit, voxOriginWorld, ...
                                gridPtsWorld, gridPtsWorldX, gridPtsWorldZ, ...
                                gridPtsLabel ...
                                );

                %% Walls grid in the room
                % exactly like ceiling part
                fprintf('Reading walls\n');
                gridPtsLabel  = generateWalls( ...
                                wallPath, wallID, size(inRoom), voxUnit, ...
                                voxOriginWorld, gridPtsWorld, ...
                                gridPtsWorldX, gridPtsWorldZ, ...
                                gridPtsLabel ...
                                );

                %%%%%%%%%%%%%%%%%%%%%%%%%%%
                times(roomCounter,2) = toc;
                %%%%%%%%%%%%%%%%%%%%%%%%%%%

                %% Object Read;
                fprintf('Reading objects');
                gridPtsLabel = generateObjects(objcategory, nodes, room, suncgDataPath, voxUnit, gridPtsWorld, gridPtsLabel, objectMap, scaleMap, minObjs, capacity, wallID, enabledGPU);

                %%%%%%%%%%%%%%%%%%%%%%%%%%%
                times(roomCounter,3) = toc;
                %%%%%%%%%%%%%%%%%%%%%%%%%%%

                %% Save file and visualize
                fprintf('Save and visualize scene\n');

                % Create folder
%                 resultFolder = strcat(outputFolder,'/', sceneID,'/','level',num2str(level_idx), '/','room','_',room.modelId);
                resultFolder = fullfile(outputFolder, sceneID, ...
                                        strcat('room','_',room.modelId));

                if(~exist(resultFolder))
                    mkdir(resultFolder);
                end

                % Create reconstruction files
                convertGrid(gridPtsLabel, [numClasses, gridSize], sceneOrigin, 'labels.txt', resultFolder);

                % Save configuration (in case)
                configfile = fullfile(outputFolder, sceneID, 'config.mat');
                save(configfile, 'suncgDataPath', ...
                                 'outputdir', ...
                                 'readMap', ...
                                 'discard', ...
                                 'voxUnit', ...
                                 'enabledGPU', ...
                                 'suffle' ...
                 );

                %%%%%%%%%%%%%%%%%%%%%%%%%%%
                times(roomCounter,4) = toc;
                %%%%%%%%%%%%%%%%%%%%%%%%%%%

                fprintf('\n---------------------------------\n');
                fprintf('Number of Generated Rooms: %d\n',roomCounter);
                fprintf('---------------------------------\n\n');

                % Increase Room Counter
                roomCounter = roomCounter + 1;
                bboxold = bbox;

                % Break when desired rooms are generated
                if roomCounter >= (totalRooms + 1)
                    break;
                end

            end
        end

        % Break all
        %if roomCounter >= (totalRooms + 1)
        %    break;
        %end
    
    catch
        warning('Problem while reading a file. Reconstruction continues...');
        sceneIdx = sceneIdx + 1;
    end
  


end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Print Time Statistics
% DEBUG
% times(:,4) = times(:,4) - times(:,3);
% times(:,3) = times(:,3) - times(:,2);
% times(:,2) = times(:,2) - times(:,1);
% 
% % save time log to txt
% resultFolder = strcat(outputFolder,'/', "timelog.txt");
% dlmwrite(resultFolder,times,'delimiter','\t','precision',3)

% Bar chart
%classes = categorical({'Grid Construction','Floor-Ceiling-Walls','Objects', 'Save & Visualize'});
%timemeans = mean(times);
%bar(classes,timemeans);


fprintf('Execution Completed!\n');
