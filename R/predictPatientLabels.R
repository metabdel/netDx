#' assign patient class when ranked by multiple GM predictors
#'
#' @param resSet (list) output of getPatientRankings, each key for a different
#' predictor. names(resSet) contain predictor label
#' @param verbose (logical) print detailed messages
#' @return data.frame: ID, similarityScore, PRED_CLASS
#' @examples 
#' data(predRes); predClass <- predictPatientLabels(predRes)
#' @export
predictPatientLabels <- function(resSet, verbose = TRUE) {
    type_rank <- NULL
    for (k in seq_len(length(resSet))) {
        x <- resSet[[k]]$fullmat
        idx <- which(colnames(x) == "GM_score")
        if (any(idx)) 
            colnames(x)[idx] <- "similarityScore"
        if (is.null(type_rank)) 
            type_rank <- x[, c("ID", "similarityScore")] else {
            if (all.equal(x$ID, type_rank$ID) != TRUE) {
                stop("predictPatientLabels: ids don't match")
            }
            type_rank <- cbind(type_rank, x[, "similarityScore"])
        }
        rnkCol <- paste(names(resSet)[k], "SCORE", sep = "_")
        colnames(type_rank)[ncol(type_rank)] <- rnkCol
    }
    
    na_sum <- rowSums(is.na(type_rank[, -1]))
    if (verbose) {
        if (any(na_sum > 0)) 
            message(sprintf(paste("*** %i rows have an NA prediction ", 
							"(probably query samples that were not not ranked\n", 
                sep = ""), sum(na_sum > 0)))
    }
    type_rank <- na.omit(type_rank)
    
    # finally, select the class with the highest rank as the subject label.
    maxScore <- rep(NA, nrow(type_rank))
    for (k in seq_len(nrow(type_rank))) {
        maxScore[k] <- colnames(type_rank)[which.max(type_rank[k, -1]) + 1]
    }
    patClass <- sub("_SCORE", "", maxScore)
    type_rank <- cbind(type_rank, PRED_CLASS = patClass)
    type_rank$PRED_CLASS <- as.character(type_rank$PRED_CLASS)
    
    type_rank
}
