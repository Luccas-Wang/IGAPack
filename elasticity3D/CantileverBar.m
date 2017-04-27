%script CantileverBar.m
% implement a cantilever bar domain with PHT splines
% use base with 3x3 patches and the bar as patch #10
% use GIFT mapping

close all
clear all

p = 3;
q = 3;
r = 3;

numPatchesU = 3;
numPatchesV = 3;
targetScale = 0.5;

numPatches = numPatchesU * numPatchesV+1;

tic
target_rel_error = 1e-2;
addpath ./PHTutils
addpath ./ExampleData


%dimensions of the domain
L = 3;  %length of the domain
W = 3;  %width of the domain
H = 1;  %height of the domain

E0           = 1e5;  % Young's modulus
nu0          = 0.3;  % Poisson's ratio
bound_disp = 0.1;   %imposed displacement on the boundary

% Define the elasticity (compliance) matrix
Cmat=zeros(6,6);
Cmat(1:3,1:3)=E0/(1+nu0)/(1-2*nu0)*[ 1-nu0 nu0 nu0;
    nu0 1-nu0 nu0;
    nu0 nu0 1-nu0];
Cmat(4:6,4:6)=E0/(1+nu0)*eye(3)/2;


tic
dimBasis = zeros(1, numPatches);
GIFTmesh = init3DGeometryGIFTMP('CantileverBar',L,W,H,numPatches,numPatchesU,numPatchesV);

octupleList = cell(numPatches,1);
PHTelem = cell(numPatches, 1);
for i=1:numPatches
    
    [PHTelem{i}, dimBasis(i)] = initPHTmesh3D(p,q,r);
    octupleList{i} = 2:9;
end

% patchBoundaries = cell(numPatches-1, 4);
% for indexPatch = 1:numPatches-1
%     %define the boundary between patch i and patch i+1
%     patchBoundaries{indexPatch, 1} = indexPatch;
%     patchBoundaries{indexPatch, 2} = indexPatch+1;
%     patchBoundaries{indexPatch, 3} = 2;
%     patchBoundaries{indexPatch, 4} = 4;
% end

patchBoundaries = {1,2,2,4;2,3,2,4;1,4,3,1;3,6,3,1;[2,4,6],5,[3,2,4],[1,4,2];4,7,3,1;6,9,3,1;[5,7,9],8,[3,2,4],[1,4,2];5,10,6,5};
keep_refining = 1;
num_steps = 0;
%
while keep_refining
    num_steps = num_steps + 1;
    toc
    disp(['Step ', num2str(num_steps)])
    
    plotPHTMesh3DMP(PHTelem, GIFTmesh)
    [ PHTelem, dimBasis, octupleList ] = checkConforming3D( PHTelem, dimBasis, patchBoundaries, p, q, r, octupleList );
    
    [ PHTelem, sizeBasis ] = zipConforming3D( PHTelem, dimBasis, patchBoundaries, p, q, r);
    
    
    sizeBasis
    
    %
    toc
    %assemble the linear system
    disp('Assembling the linear system...')
    [ stiff, rhs ] = assembleGalerkinSysGIFTMP( PHTelem, GIFTmesh, sizeBasis, p, q, r, Cmat, octupleList);
    
    %impose boundary conditions
    toc
    disp('Imposing boundary conditions...')
    [ stiff, rhs, bcdof, bcval ] = imposeDirichletCantileverBar(stiff, rhs, PHTelem, p, q, r, bound_disp);
    
    size(stiff)
    
    toc
    disp('Solving the linear system...')
    sol0 = stiff\rhs;
    
%     alpha = max(sum(abs(stiff),2)./diag(stiff))-2
%     L1 = ichol(stiff, struct('type','ict','droptol',1e-3,'diagcomp',alpha));
%     [sol0,fl1,rr1,it1,rv1] = pcg(stiff,rhs,1e-14,num_steps*1000,L1,L1');
%     fprintf('PCG exited with flag %d\n', fl1)
%     fprintf('Residual value: %1.15g\n', rr1)
%     fprintf('Number of iterations: %d\n', it1)
    
    
    toc
    vtuFile = ['CantileverBarSol_p=',num2str(p),'_step',num2str(num_steps),'.vtu'];
    plotStressDisp3DVM_20pt(PHTelem, GIFTmesh, sol0, p, q, r, Cmat, vtuFile)
    toc
            
    % error estimation
    [octupleRef, estErrorGlobTotal, estError] = recoverDerivEstGalMPAll(PHTelem, GIFTmesh, sol0, target_rel_error, octupleList, p, q, r, Cmat, targetScale);
    estErrorGlobTotal
    
    %adaptive refinement
    indexOctuple = cell(1, numPatches);
    keep_ref = ones(1, numPatches);
    for patchIndex = 1:numPatches
        indexOctuple{patchIndex} = find(octupleRef{patchIndex} > 0);
        
        if isempty(indexOctuple{patchIndex}) || (estErrorGlobTotal < target_rel_error)
            disp(['Done refining in geometric patch ', num2str(patchIndex), ' after ',num2str(num_steps), ' steps!'])
            keep_ref(patchIndex) = 0;
        else
            numNewOctuples = length(indexOctuple{patchIndex});
            toc
            disp(['In geometric patch ', num2str(patchIndex), ' refining ',num2str(numNewOctuples), ' octuples out of ', num2str(size(octupleList{patchIndex},1))])
            [octupleList{patchIndex}, PHTelem{patchIndex}, dimBasis(patchIndex)] = refineMesh3D(octupleRef{patchIndex}, octupleList{patchIndex}, PHTelem{patchIndex}, p, q, r, dimBasis(patchIndex));
        end
    end
    
    %stop refinment if the sum of keep_ref is zero.
    keep_refining=sum(keep_ref);
    toc
end


