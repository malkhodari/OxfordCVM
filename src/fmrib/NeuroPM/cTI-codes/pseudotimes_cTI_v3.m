function [keep_indices,global_pseudotimes,mappedX,contrasted_data,Node_contributions,Expected_contribution] = pseudotimes_cTI_v3(data,starting_point,classes_for_colours,final_subjects,method,max_cPCs)

%-- INPUTS:
%     data: [Nsubjects, Nfeatures] data matrix.
%     starting_point: indices of the background subjects.
%     classes_for_colours(optional): [Nsubjects, 1] subjects categories/labels, if
%         available, only for results visualization.
%     final_subjects (optional): you may specify the indices of a target group (a subgroup of the 
%         whole population, e.g. subjects a advanced disease pathology). By
%     default, the algorithm takes all the subjects that don't belong to the
%         background.
%     method: 'cPCA', 'PCA' or 'UMAP'. Notice that the original cTI method uses
%         cPCA by definition, PCA and UMAP should be considered only for comparison analyses.
%     max_cPCs (optional): maximum number of principal components to consider.
%     Default: 10.
%
%-- OUTPUTS:
%     global_ordering: subjects ordering in the pseudotime line.
%     global_pseudotimes
%     mappedX: obtained contrasted Principal Components (cPCs).
%     contrasted_data: reconstructed data considering only the final cPCs (of note, output 
%         may not be in the same scale that the initial data).
%     Node_contributions: contribution of each node to the final representation space.
%     Expected_contribution: expected nodes contribution assuming equal weights
%         in the final representation space (usefull as cut-off value).

% Reducing dimensionality
% define disease/background and number of patients in the dataset
starting_point = starting_point(:);
final_subjects = final_subjects(:);

% define range of alphas to compute
n_alphas = 200;
alphas_all = logspace(-2, 2, n_alphas);

% define original indices to remove patients from
ind_remove_mask = zeros(size(data, 1), 1);

% define counters/storage arrays
max_iter          = 1;    % maximum number of iterations
is_accurate       = false; % is current model accurate
prev_alpha        = 75;    % initialze alpha
iter              = 1;     % iteration counter
n_removed         = [0];   % number of outliers removed in each iteration
n_removed_disease = [0];   % number of disease outliers removed in each iteration

% while loop to continuously loop through
while iter <= max_iter && ~is_accurate
    
    % define alphas, make sure range is always within range provided
    n_points = 5;
    mid_point = find(alphas_all >= prev_alpha);
    mid_point = mid_point(1);
    mid_point = max([mid_point, 1 + n_points]);
    mid_point = min([mid_point, n_alphas - n_points]);
    alphas_iter = alphas_all((mid_point - n_points):(mid_point + n_points));

    % perform contrastive PCA (using background and disease as priors into PCA)
    [cPCs,gap_values,alphas,no_dims,contrasted_data,Vmedoid,Dmedoid] = ... 
            cPCA(data,starting_point,final_subjects,max_cPCs,classes_for_colours,alphas_iter);
    
    % filter out large cPCs
    %cPCs(abs(cPCs) > std(cPCs,0,"all")*3) = 0;
    
    % store the output values
    [~,j]           = max(gap_values); % the optimun alpha should maximizes the clusterization in the target dataset
    mappedX         = cPCs(:,1:no_dims(j),j);
    Node_Weights    = Vmedoid(:,1:no_dims(j),j);
    Lambdas         = Dmedoid(1:no_dims(j),j);
    contrasted_data = contrasted_data(:,:,j);

    % print some output metrics (number of PCs and final alpha of Cd - alpha*Cb)
    disp(['Iteration ' num2str(iter) ' Number of cPCs: ' num2str(no_dims(j))]);
    disp(['Iteration ' num2str(iter) ' Alpha Selected: ' num2str(alphas(j))]);
    disp(['Iteration ' num2str(iter) ' Number of Outliers Removed: ' num2str(n_removed(iter))]);
    disp(['Iteration ' num2str(iter) ' Number of Diseased Outliers Removed: ' num2str(n_removed_disease(iter))]);

    % use alpha to determine the range of alphas to search in next iteration
    prev_alpha = alphas(j);

    % compute nodal weightings (values of the final eigen vectors)
    Node_contributions = (100*(Node_Weights.^2)./repmat(sum(Node_Weights.^2,1),size(Node_Weights,1),1))*Lambdas;
    Expected_contribution = sum(100*1/size(Node_Weights,1)*Lambdas);

    % Node-node distance
    dist_matrix = double(L2_distance(mappedX', mappedX'));

    % Minimal spanning tree across all the points
    % Specifying which node is the root, the closest one to all the starting points
    [~,j] = min(sum(dist_matrix(starting_point, starting_point),2));
    Root_node = j;

    % subset background and diseased groups
    in_background_target = [starting_point(:); final_subjects(:)];
    dist_matrix0 = dist_matrix;   
    out_background_target = setdiff(1:size(data, 1), in_background_target)';
    dist_matrix = dist_matrix(in_background_target, in_background_target);

    % calculate minimum spanning tree
    rng('default'); % For reproducibility
    Tree = graphminspantree(sparse(dist_matrix), Root_node);
    Tree(Tree > 0) = dist_matrix(Tree > 0);
    MST = full(Tree + Tree'); %alternate: MST = minspantree(graph(dist_matrix, "upper"));

    % Shortest paths to the starting point(s) and pseudotimes
    datas = dijkstra(MST, Root_node');
    dijkstra_F = datas.F; % dijkstra father nodes for trajectory analysis
    max_distance = max(datas.A(~isinf(datas.A)));
    
    % initialie and define pseudotimes array
    global_pseudotimes = zeros(size(data, 1), 1);
    global_pseudotimes(in_background_target, 1) = datas.A/max_distance;

    % extrapolate between group values
    temp_dist = dist_matrix0(out_background_target, in_background_target);
    [~, j] = min(temp_dist,[],2);
    global_pseudotimes(out_background_target, 1) = global_pseudotimes(in_background_target(j), 1);

    % evaluate current model efficacy
    Q1_disease = quantile(global_pseudotimes(classes_for_colours == 3), 0.25);
    lower_disease = min(global_pseudotimes(classes_for_colours == 3));

    Q1_between = quantile(global_pseudotimes(classes_for_colours == 2), 0.25);
    Q2_between = quantile(global_pseudotimes(classes_for_colours == 2), 0.5);
    
    Q3_background = quantile(global_pseudotimes(classes_for_colours == 1), 0.75);
    
    % define conditions for model efficacy
    condition_1 = lower_disease > Q3_background; % minimal overlap for background and disease
    condition_2 = Q1_disease > Q2_between;       % no overlap for IQR of disease and between
    condition_3 = Q1_between > Q3_background;    % no overlap for IQR of between and background
    is_accurate = condition_1 && condition_2 && condition_3;

    % increment counter
    iter = iter + 1;

    % only remove outlier if this is not the last iteration and model is not accurate
    if iter <= max_iter && ~is_accurate

        % store visualization in each iteration
        f = figure('visible', 'off');
        boxplot(global_pseudotimes, classes_for_colours);
        title(['Iteration ' num2str(iter - 1) ' (Removed ' num2str(sum(ind_remove_mask == 1)) ' Outliers)']);
        set(gcf, 'PaperPosition', [0 0 10 15]);
        saveas(f, ['io/results' num2str(iter - 1) '.png']);

        % find distribution (boxplot) thresholds & define upper threshold for scores
        score_lim = quantile(global_pseudotimes(classes_for_colours == 3), 0.99);

        % defines patients who will be removed
        remove_ind = find(global_pseudotimes >= score_lim);
        remove_ind_disease = find(global_pseudotimes(classes_for_colours == 3) >= score_lim);

        % store points removed
        n_removed         = [n_removed, length(remove_ind)];
        n_removed_disease = [n_removed_disease, length(remove_ind_disease)];
    
        % filter out patients with large scores in the original inputs
        data                = data(global_pseudotimes < score_lim, :);
        classes_for_colours = classes_for_colours(global_pseudotimes < score_lim);
        starting_point      = find(classes_for_colours == 1)';
        final_subjects      = find(classes_for_colours == 3)';
        
        % update list of indices for patients we are still keeping
        temp = ind_remove_mask(ind_remove_mask == 0);
        temp(remove_ind) = 1;
        ind_remove_mask(ind_remove_mask == 0) = temp;

    end

end

% convert MST from adjacency matrix into graph object
MST_graph = graph(MST);

% produce visualization and save the plots
colours_healthy_disease = classes_for_colours(classes_for_colours ~= 2);
f = figure('visible','off');
subplot(1,2,1);
boxplot(global_pseudotimes,classes_for_colours);
title('Disease Score By Group');
subplot(1,2,2);
p = plot(MST_graph);
highlight(p, MST_graph, 'EdgeColor', 'black', 'LineWidth',1);
highlight(p, find(colours_healthy_disease==1), 'NodeColor', 'g', 'MarkerSize',2);
highlight(p, find(colours_healthy_disease==3), 'NodeColor', 'r', 'MarkerSize',2);
highlight(p, Root_node, 'NodeColor', 'black', 'Marker', '^', 'MarkerSize', 5);
title('Minimum Spanning Tree (Background/Disease)');
set(gcf, 'PaperPosition', [0 0 30 10]);
saveas(f, 'io/results_final.png');

% save MST labels as table to output file
MST_groups = colours_healthy_disease';
MST_groups(MST_groups==3) = 2;
MST_labels = table(MST_groups, global_pseudotimes(in_background_target,1), ...
                   'VariableNames', {'bp_group', 'pseudotime', });
writetable(MST_labels,'io/MST.csv', 'WriteVariableNames', true);

% clear and save variables
clear Tree dist_matrix0 dist_matrix
save('io/PC_Transform.mat','Node_Weights'); % eigen matrix to perform transformation into PCA space
save('io/dijkstra.mat','dijkstra_F'); % dijkstra father nodes of every node for computing trajectories
save('io/MST.mat','MST'); % save minimum spanning tree individually
%save('io/all.mat'); % save all variables to workspace to study intermediary values

% re-use useless variable global_ordering to output indices to keep 
keep_indices = find(ind_remove_mask == 0);

return;

function [theta,varargout] = subspacea(F,G,A)
%SUBSPACEA angles between subspaces
%  subspacea(F,G,A)
%  Finds all min(size(orth(F),2),size(orth(G),2)) principal angles
%  between two subspaces spanned by the columns of matrices F and G 
%  in the A-based scalar product x'*A*y, where A
%  is Hermitian and positive definite. 
%  COS of principal angles is called canonical correlations in statistics.  
%  [theta,U,V] = subspacea(F,G,A) also computes left and right
%  principal (canonical) vectors - columns of U and V, respectively.
%
%  If F and G are vectors of unit length and A=I, 
%  the angle is ACOS(F'*G) in exact arithmetic. 
%  If A is not provided as a third argument, than A=I and 
%  the function gives the same largest angle as SUBSPACE.m by Andrew Knyazev,
%  see
%  http://www.mathworks.com/matlabcentral/fileexchange/Files.jsp?type=category&id=&fileId=54
%  MATLAB's SUBSPACE.m function is still badly designed and fails to compute 
%  some angles accurately.
%
%  The optional parameter A is a Hermitian and positive definite matrix,
%  or a corresponding function. When A is a function, it must accept a
%  matrix as an argument. 
%  This code requires ORTHA.m, Revision 1.5.8 or above,
%  which is included. The standard MATLAB version of ORTH.m
%  is used for orthonormalization, but could be replaced by QR.m.
%  
%  Examples: 
%  F=rand(10,4); G=randn(10,6); theta = subspacea(F,G);
%  computes 4 angles between F and G, while in addition 
%  A=hilb(10); [theta,U,V] = subspacea(F,G,A);
%  computes angles relative to A and corresponding vectors U and V. 
%  
%  The algorithm is described in A. V. Knyazev and M. E. Argentati,
%  Principal Angles between Subspaces in an A-Based Scalar Product: 
%  Algorithms and Perturbation Estimates. SIAM Journal on Scientific Computing, 
%  23 (2002), no. 6, 2009-2041.
%  http://epubs.siam.org/sam-bin/dbq/article/37733

%  Tested under MATLAB R10-14
%  Copyright (c) 2000 Andrew Knyazev, Rico Argentati
%  Contact email: knyazev@na-net.ornl.gov
%  License: free software (BSD)
%  $Revision: 4.5 $  $Date: 2005/6/27
% Function downloaded from https://www.mathworks.com/matlabcentral/fileexchange/55-subspacea-m

threshold=sqrt(2)/2; % Define threshold for determining when an angle is small

if size(F,1) ~= size(G,1)
   subspaceaError(['The row dimension ' int2str(size(F,1)) ...
         ' of the matrix F is not the same as ' int2str(size(G,1)) ...
         ' the row dimension of G'])
end

if nargin<3  % Compute angles using standard inner product
   
   % Trivial column scaling first, if ORTH.m is used later 
   for i=1:size(F,2),
     normi=norm(F(:,i),inf);
     %Adjustment makes tol consistent with experimental results
     if normi > eps^.981
       F(:,i)=F(:,i)/normi;
       % Else orth will take care of this
     end
   end
   for i=1:size(G,2),
     normi=norm(G(:,i),inf);
     %Adjustment makes tol consistent with experimental results
     if normi > eps^.981
       G(:,i)=G(:,i)/normi;
       % Else orth will take care of this
     end
   end

  % Compute angle using standard inner product
  
  QF = orth(F);      %This can also be done using QR.m, in which case
  QG = orth(G);      %the column scaling above is not needed 
  
  q = min(size(QF,2),size(QG,2));
  [Ys,s,Zs] = svd(QF'*QG,0);
  if size(s,1)==1
    % make sure s is column for output
    s=s(1);
  end
  s = min(diag(s),1);
  theta = max(acos(s),0);
  U = QF*Ys;
  V = QG*Zs;
  indexsmall = s > threshold;
  if max(indexsmall) % Check for small angles and recompute only small   
    RF = U(:,indexsmall); 
    RG = V(:,indexsmall); 
    %[Yx,x,Zx] = svd(RG-RF*(RF'*RG),0);
    [Yx,x,Zx] = svd(RG-QF*(QF'*RG),0); % Provides more accurate results
    if size(x,1)==1
      % make sure x is column for output
      x=x(1);
    end
    Tmp = fliplr(RG*Zx);
    V(:,indexsmall) = Tmp(:,indexsmall);
    U(:,indexsmall) = RF*(RF'*V(:,indexsmall))*...   
    diag(1./s(indexsmall)); 
    x = diag(x);               
    thetasmall=flipud(max(asin(min(x,1)),0));
    theta(indexsmall) = thetasmall(indexsmall);
  end     
  
  % Compute angle using inner product relative to A
  else 
    [m,n] = size(F);
    if ~isstr(A)
      [mA,mA] = size(A);
      if any(size(A) ~= mA)
        subspaceaError('Matrix A must be a square matrix or a string.')
      end
    if size(A) ~= m
       subspaceaError(['The size ' int2str(size(A)) ...
             ' of the matrix A is not the same as ' int2str(m) ...
             ' - the number of rows of F'])
    end
  end
  
  [QF,AQF]=ortha(A,F);
  [QG,AQG]=ortha(A,G);
  q = min(size(QF,2),size(QG,2));
  [Ys,s,Zs] = svd(QF'*AQG,0);
  if size(s,1)==1
    % make sure s is column for output
    s=s(1);
  end
  s=min(diag(s),1);
  theta = max(acos(s),0);
  U = QF*Ys;
  V = QG*Zs;
  indexsmall = s > threshold;  
  if max(indexsmall) % Check for small angles and recompute only small     
    RG = V(:,indexsmall); 
    AV = AQG*Zs;
    ARG = AV(:,indexsmall);  
    RF = U(:,indexsmall);
    %S=RG-RF*(RF'*(ARG));
    S=RG-QF*(QF'*(ARG));% A bit more cost, but seems more accurate
      
    % Normalize, so ortha would not delete wanted vectors
    for i=1:size(S,2),
      normSi=norm(S(:,i),inf);
      %Adjustment makes tol consistent with experimental results
      if normSi > eps^1.981
        QS(:,i)=S(:,i)/normSi;
        % Else ortha will take care of this
      end
    end

    [QS,AQS]=ortha(A,QS);
    [Yx,x,Zx] = svd(AQS'*S);
    if size(x,1)==1
      % make sure x is column for output
      x=x(1);
    end
    x = max(diag(x),0);
     
    Tmp  = fliplr(RG*Zx);
    ATmp = fliplr(ARG*Zx);
    V(:,indexsmall) = Tmp(:,indexsmall);
    AVindexsmall = ATmp(:,indexsmall);   
    U(:,indexsmall) = RF*(RF'*AVindexsmall)*...
                       diag(1./s(indexsmall)); 
    thetasmall=flipud(max(asin(min(x,1)),0));
    
    %Add zeros if necessary
    if sum(indexsmall)-size(thetasmall,1)>0
      thetasmall=[zeros(sum(indexsmall)-size(thetasmall,1),1)',...
           thetasmall']';
    end
    
    theta(indexsmall) = thetasmall(indexsmall);
  end
end
varargout(1)={U(:,1:q)};
varargout(2)={V(:,1:q)};

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [Q,varargout]=ortha(A,X)
%ORTHA Orthonormalization Relative to matrix A
%  Q=ortha(A,X)
%  Q=ortha('Afunc',X)
%  Computes an orthonormal basis Q for the range of X, relative to the 
%  scalar product using a positive definite and selfadjoint matrix A.
%  That is, Q'*A*Q = I, the columns of Q span the same space as
%  columns of X, and rank(Q)=rank(X).
%
%  [Q,AQ]=ortha(A,X) also gives AQ = A*Q.
%
%  Required input arguments:
%  A : either an m x m positive definite and selfadjoint matrix A
%  or a linear operator A=A(v) that is positive definite selfadjoint;
%  X : m x n matrix containing vectors to be orthonormalized relative 
%  to A.
%
%  ortha(eye(m),X) spans the same space as orth(X)
%
%  Examples:
%  [q,Aq]=ortha(hilb(20),eye(20,5))
%  computes 5 column-vectors q spanned by the first 5 coordinate vectors,
%  and orthonormal with respect to the scalar product given by the
%  20x20 Hilbert matrix,
%  while an attempt to orthogonalize (in the same scalar product)
%  all 20 coordinate vectors using
%  [q,Aq]=ortha(hilb(20),eye(20))
%  gives 14 column-vectors out of 20. 
%  Note that rank(hilb(20)) = 13 in double precision. 
%
%  Algorithm:
%  X=orth(X), [U,S,V]=SVD(X'*A*X), then Q=X*U*S^(-1/2)
%  If A is ill conditioned an extra step is performed to
%  improve the result. This extra step is performed only
%  if a test indicates that the program is running on a
%  machine that supports higher precison arithmetic
%  (greater than 64 bit precision).
%
%  See also ORTH, SVD
%
%  Copyright (c) 2000 Andrew Knyazev, Rico Argentati
%  Contact email: knyazev@na-net.ornl.gov
%  License: free software (BSD)
%  $Revision: 1.5.8 $  $Date: 2001/8/28
%  Tested under MATLAB R10-12.1

% Check input parameter A
[m,n] = size(X);
if ~isstr(A)
  [mA,mA] = size(A);
  if any(size(A) ~= mA)
    subspaceaError('Matrix A must be a square matrix or a string.')
  end
  if size(A) ~= m
    subspaceaError(['The size ' int2str(size(A)) ...
           ' of the matrix A does not match with ' int2str(m) ...
           ' - the number of rows of X'])
  end
end

% Normalize, so ORTH below would not delete wanted vectors
for i=1:size(X,2),
  normXi=norm(X(:,i),inf);
  %Adjustment makes tol consistent with experimental results
  if normXi > eps^.981
    X(:,i)=X(:,i)/normXi;
    % Else orth will take care of this
  end
end

% Make sure X is full rank and orthonormalize 
X=orth(X); %This can also be done using QR.m, in which case
           %the column scaling above is not needed 

%Set tolerance           
[m,n]=size(X);
tol=max(m,n)*eps;

% Compute an A-orthonormal basis
if ~isstr(A)
  AX = A*X;
else
  AX = feval(A,X);
end
XAX = X'*AX;

XAX = 0.5.*(XAX' + XAX);
[U,S,V]=svd(XAX);

if n>1 s=diag(S);
  elseif n==1, s=S(1);
  else s=0;
end

%Adjustment makes tol consistent with experimental results  
threshold1=max(m,n)*max(s)*eps^1.1;

r=sum(s>threshold1);
s(r+1:size(s,1))=1;
S=diag(1./sqrt(s),0);
X=X*U*S;
AX=AX*U*S;
XAX = X'*AX;

% Check subspaceaError against tolerance 
subspaceaError=normest(XAX(1:r,1:r)-eye(r));
% Check internal precision, e.g., 80bit FPU registers of P3/P4
precision_test=[1 eps/1024 -1]*[1 1 1]'; 
if subspaceaError<tol | precision_test==0;
  Q=X(:,1:r);
  varargout(1)={AX(:,1:r)};
  return
end

% Complete another iteration to improve accuracy
% if this machine supports higher internal precision 
if ~isstr(A)
  AX = A*X;
else
  AX = feval(A,X);
end
XAX = X'*AX;

XAX = 0.5.*(XAX' + XAX);
[U,S,V]=svd(XAX);

if n>1 s=diag(S);
  elseif n==1, s=S(1);
  else s=0;
end
   
threshold2=max(m,n)*max(s)*eps;
r=sum(s>threshold2);
S=diag(1./sqrt(s(1:r)),0);
Q=X*U(:,1:r)*S(1:r,1:r);
varargout(1)={AX*U(:,1:r)*S(1:r,1:r)};
