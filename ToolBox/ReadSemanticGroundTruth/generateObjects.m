%% Reads and reconstructs each object of the room.
% Reads the bivox size and optains the object and its scale
% Converts object to world coordinates
% Applies segmentation on grid points of object
% Updates the label grid  

function [ gridPtsLabel ] = generateObjects(objcategory, nodes, room, suncgDataPath, voxUnit, gridPtsWorld, gridPtsLabel, objectMap, scaleMap, minObjs, capacity, wallID, enabledGPU)

    % If there are objects in room
    if isfield(room, 'nodeIndices')
        fprintf('Reading objects');

        obj_in_room = room.nodeIndices;

        % For every object
        for objId = obj_in_room
            object_struct = nodes{objId+1};

            if isfield(object_struct, 'modelId')
            fprintf('.');

                % Set segmentation class ID
                [~, classRootId] = getobjclassSUNCG(strrep(object_struct.modelId,'/','__'), objcategory);
%                 fprintf('Rootid: %d  , ModelId! %s\n',classRootId, strrep(object_struct.modelId,'/','__'));

                % Compute object bbox in world coordinates
                objBbox = [object_struct.bbox.min([1,2,3])',object_struct.bbox.max([1,2,3])'];

                % Load segmentation of object in object coordinates
                filename= fullfile(suncgDataPath,'object_vox/object_vox_data/',...
                                   strrep(object_struct.modelId,'/','__')  ,...
                                   [strrep(object_struct.modelId,'/','__') , '.binvox']);

                [objSegPts, scale]= loadObject(filename, objectMap, scaleMap, minObjs, capacity);

                %[voxels, scale, translate] = read_binvox(filename);
                %[x, y, z] = ind2sub(size(voxels),find(voxels(:)>0));
                %objSegPts = bsxfun(@plus,[x,y,z]*scale,translate([1,2,3])');

                % Convert object to world coordinates
                extObj2World_yup = reshape(object_struct.transform,[4,4]);
                objSegPts = extObj2World_yup*objSegPts;
                objSegPts = objSegPts([1,2,3],:);%[objSegPts(:,[1,3,2])';ones(1,size(x,1))];
                
                gridPtsObjWorldInd = gridPtsWorld(1,:) >= objBbox(1,1) - voxUnit & gridPtsWorld(1,:) <= objBbox(1,2) + voxUnit & ...
                                     gridPtsWorld(2,:) >= objBbox(2,1) - voxUnit & gridPtsWorld(2,:) <= objBbox(2,2) + voxUnit & ...
                                     gridPtsWorld(3,:) >= objBbox(3,1) - voxUnit & gridPtsWorld(3,:) <= objBbox(3,2) + voxUnit ;

                gridPtsObjWorld = gridPtsWorld(:,gridPtsObjWorldInd);

                % If object is a window or door, clear voxels in object bbox

                if (classRootId == 4 || classRootId == 5)
                   gridPtsObjClearInd = gridPtsObjWorldInd & gridPtsLabel==wallID;
                   gridPtsLabel(gridPtsObjClearInd) = 0;
                end


                % Apply segmentation to grid points of object
                if enabledGPU
                    [~, dists] = multiQueryKNNSearchImplGPU(pointCloud(objSegPts'), gridPtsObjWorld');
                else
                    [~, dists] = multiQueryKNNSearchImpl(pointCloud(objSegPts'), gridPtsObjWorld',1);
                end

                %[~, dists] = multiQueryKNNSearchImpl(pointCloud(objSegPts'), gridPtsObjWorld',1);
                objOccInd = sqrt(dists) <= sqrt(3)/2*scale;
                gridPtsObjWorldLinearIdx = find(gridPtsObjWorldInd);
                gridPtsLabel(gridPtsObjWorldLinearIdx(objOccInd)) = classRootId;

            end
        end

        fprintf('\n');
    end


end

