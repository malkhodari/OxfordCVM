library(data.table)
library(R.matlab)

# load outputs from NeuroPM
path = "NeuroPM/io"
path = "C:/Users/86155/Desktop/io - 6k full run+x_val"
# set K (for KNN)
K = 1

# load pseudotime scores
pseudotimes_full = read.csv(file.path(path, "pseudotimes.csv"), header=TRUE)
pseudotimes_full$err = NA
pseudotimes_full$knn_dist = NA
pseudotimes_full$sensitivity = NA
pseudotimes_full$specificity = NA

# load ukb raw variables
ukb_df = data.frame(fread(file.path(path, "ukb_num_norm.csv"), header=TRUE))

# load transformation matrix into PC space
PC_transform = readMat(file.path(path, "PC_Transform.mat"))$Node.Weights

# list X validation files
X_val_files = list.files(path)
X_val_files = X_val_files[grepl("pseudotimes_fold", X_val_files)]

# define number of folds used and number of classes
n_folds = length(X_val_files)
n_class = length(unique(pseudotimes_full$bp_group))

# define row indices for each fold to place into X validation matrix
ind = floor(seq(from = 1, to = nrow(pseudotimes_full), length = n_folds + 1))

# load pseudotime scores for each fold
for (i in 1:n_folds) {
  
  # load file from i'th fold
  pseudotimes = read.csv(file.path(path, paste0("pseudotimes_fold", i, 
                                                ".csv")), header=TRUE)
  
  # define pred/ground truths in a labelled structure
  y_pred = pseudotimes$global_pseudotimes[pseudotimes$bp_group != 0]
  y_true = ifelse(pseudotimes$bp_group[pseudotimes$bp_group != 0] == 1, 0, 1)

  # compute optimal threshold interval for prediction
  intervals = seq(0, 1, by = 0.001)
  threshold_mat = sapply(intervals, function(thres) ifelse(y_pred > thres, 1, 0))
  fpr = apply(threshold_mat, 2, function(x) 
                  sum(x == 1 & y_true == 0) / 
                    (sum(x == 1 & y_true == 0) + sum(x == 0 & y_true == 0)))
  tpr = apply(threshold_mat, 2, function(x)
                    sum(x == 1 & y_true == 1) / 
                      (sum(x == 1 & y_true == 1) + sum(x == 0 & y_true == 1)))
  opt_ind = which.max(1 - fpr + tpr)
  opt_thres = intervals[opt_ind]

  # create indices for indexing
  ind_i = (ind[i] + (i != 1)):ind[i + 1]
  
  # and reference labels and data for inference
  ref_label = pseudotimes_full$global_pseudotimes[-ind_i]
  ref_group = pseudotimes_full$bp_group[-ind_i]
  ref_data = unname(as.matrix(ukb_df[-ind_i, ])) %*% PC_transform

  # compute subset index of which have well defined disease scores
  max_background = max(pseudotimes$global_pseudotimes[
                                            pseudotimes$bp_group == 1])
  min_disease = min(pseudotimes$global_pseudotimes[
                                            pseudotimes$bp_group == 2])
  new_ind_i = (ref_label < (min_disease * 1) | 
                       ref_label > (max_background * 0.5)) & (ref_group != 0)
  
  # subset rows based on new row index filter
  ref_label = ref_label[new_ind_i]
  ref_group = ref_group[new_ind_i]
  ref_data = ref_data[new_ind_i, ]

  # extract data to predict
  pred_data = unname(as.matrix(ukb_df[ind_i, ]))

  # create dataframe of ground truth and predictions for disease score
  eval = data.frame(gt = pseudotimes_full$global_pseudotimes[ind_i],
                    group = pseudotimes_full$bp_group[ind_i],
                    pred = 0,
                    knn_dist = 0)
  
  # perform KNN to infer disease score
  for (j in 1:nrow(pred_data)) {
    
    # transform data into cPC space
    # do this one at a time to demonstrate speed/applicability
    pred_PC = (pred_data[j,] %*% PC_transform)[1,]

    # compute distance with each row
    dist_j = rowMeans(t(abs(t(ref_data) - pred_PC)), na.rm = TRUE)
    
    # compute KNN and prediction
    sorted_ind = order(dist_j)[1:K]
    eval$pred[j] = sum(ref_label[sorted_ind])/K
    eval$knn_dist[j] = mean(dist_j[sorted_ind])
    
  }

  # compute err
  eval$err = sqrt((eval$pred - eval$gt)**2)

  # define prediction and ground truth
  y_true = ifelse(eval$gt > opt_thres, 1, 0)
  y_pred = ifelse(eval$pred > opt_thres, 1, 0)

  # compute true/false positive/negatives
  tp = sum(y_true == 1 & y_pred == 1)
  tn = sum(y_true == 0 & y_pred == 0)
  fp = sum(y_true == 0 & y_pred == 1)
  fn = sum(y_true == 1 & y_pred == 0)

  # compute metrics
  sensitivity = tp / (tp + fn) * 100
  specificity = tn / (tn + fp) * 100
  f1 = 2 * tp / (2 * tp + fp + fn) * 100

  # display summaries, also by group
  print(sprintf("------------------------------ Evaluating Fold %.0f", i))
  print(sprintf("RMSE = %0.3f (N = %.0f)", mean(eval$err), length(ind_i)))
  print(sprintf(paste0("Optimal Threshold at %0.3f (Sensitivity = %0.1f%%, ",
                       "Specificity = %0.1f%%, F1 = %0.1f%%)"),
                opt_thres, sensitivity, specificity, f1))
  
  # append
  pseudotimes_full$err[ind_i] = eval$err
  pseudotimes_full$knn_dist[ind_i] = eval$knn_dist
  pseudotimes_full$sensitivity[ind_i] = sensitivity
  pseudotimes_full$specificity[ind_i] = specificity
  
}

# display overall results
print(sprintf(paste0("Overall: %.0f-Fold X-Validation Results in an RMSE of %0.3f,",
                    " Sensitivity of %0.1f%%, Specificity of %0.1f%%"),
              n_folds,
              mean(pseudotimes_full$err),
              mean(pseudotimes_full$sensitivity),
              mean(pseudotimes_full$specificity)))
print(sprintf("Mean by Group:"))
print(aggregate(pseudotimes_full[, c("err", "knn_dist")],
                list(pseudotimes_full$bp_group), 
                function(x) mean(x, na.rm = TRUE)))