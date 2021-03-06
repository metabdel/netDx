% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/setupFeatureDB.R
\name{setupFeatureDB}
\alias{setupFeatureDB}
\title{setup database of features for feature selection}
\usage{
setupFeatureDB(pheno, prepDir)
}
\arguments{
\item{pheno}{(data.frame) patient metadata. Must contain ID column}

\item{prepDir}{(char) directory in which to setup database}
}
\value{
(data.frame) internal numerical id for patients (INTERNAL_ID) and
user-provided ID (ID)
}
\description{
Creates all the input files for the collection of features used in 
feature selection.
}
\examples{
data(xpr,pheno)
pathwayList <- list(pathA=rownames(xpr)[1:10],pathB=rownames(xpr)[21:50])

dataList <- list(rna=xpr)  #only one layer type
groupList <- list(rna=pathwayList) # group genes by pathways

makeNets <- function(dataList, groupList, netDir,...) {
    netList <- makePSN_NamedMatrix(dataList[['rna']],
		rownames(dataList[['rna']]),
     groupList[['rna']],netDir,verbose=FALSE,
			writeProfiles=TRUE,...)
    unlist(netList)
}
tmpDir <- tempdir(); netDir <- sprintf('\%s/nets',tmpDir)
dir.create(netDir,recursive=TRUE)

pheno_id <- setupFeatureDB(pheno,netDir)
}
