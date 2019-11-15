#' Create GeneMANIA database
#'
#' @details Creates a generic_db for use with GeneMania QueryRunner.
#' The database is in tab-delimited format, and indexes are built using Apache lucene.
#' NOTE: This pipeline expects input in the form of interaction networks
#' and not profiles.
#' Profile tables have patient-by-datapoint format (e.g. patient-by-genotype)
#' Interaction networks have pairwise similarity measures:
#' <PatientA>	<PatientB>	<similarity>
#' Documentation: https://github.com/GeneMANIA/pipeline/wiki/GenericDb
#' @param netDir (char) path to dir with input networks/profiles. All
#' networks in this directory will be added to the GM database. Note:
#' This needs to be an absolute path, not relative.
#' @param patientID (char) vector of patient IDs.
#' @param outDir (char) path to dir in which GeneMANIA database is created. 
#' The database will be under \code{outDir/dataset}.
#' @param simMetric (char) similarity measure to use in converting 
#' profiles to interaction networks. 
#' @param netSfx (char) pattern for finding network files in \code{netDir}.
#' @param verbose (logical) print messages
#' @param numCores (integer) num cores for parallel processing
#' @param P2N_threshType (char) Most users shouldn't have to change this.
#' ProfileToNetworkDriver's threshold option. One of "off|auto". 
#' unit testing
#' @param P2N_maxMissing (integer 5-100)
#' @param JavaMemory (integer) Memory for GeneMANIA (in Gb)
#' @param altBaseDir (char) Only use this if you're developing netDx. Used in
#' unit tests
#' @param ... params for \code{writeQueryBatchFile()}
#' @return (list). "dbDir": path to GeneMANIA database 
#' 	"netDir": path to directory with interaction networks. If profiles
#' are provided, this points to the INTERACTIONS/ subdirectory within 
#' the text-based GeneMANIA generic database
#' If the DB creation process results in an erorr, these values return 
#' NA
#' @examples
#' data(xpr,pheno,pathwayList);
#' # note: the paths in the calls below need to be absolute. If you 
#' # do not have write access to /tmp, change to a different directory.
#' tmpDir <- tempdir()
#' netDir <- sprintf("%s/nets",tmpDir)
#'	n <- makePSN_NamedMatrix(xpr,rownames(xpr),pathwayList,netDir,
#'		writeProfiles=TRUE); 
#' outDir <- sprintf("%s/dbdir",tmpDir)
#' dir.create(outDir)
#'	dob <- compileFeatures(netDir,pheno$ID,outDir)
#' @import doParallel
#' @export
compileFeatures <- function(netDir,patientID,outDir=tempdir(),
	simMetric="pearson",
	netSfx="_cont.txt$",verbose=TRUE,numCores=1L, P2N_threshType="off",
	P2N_maxMissing=100,JavaMemory=4L, altBaseDir=NULL,...) {
	# tmpDir/ is where all the prepared files are stored.
	# GeneMANIA uses tmpDir as input to create the generic database. 
	# The database itself will be in outDir/
	tmpDir <- sprintf("%s/tmp",outDir)
	dataDir <- sprintf("%s/dataset",outDir)
	GM_jar	<- getGMjar_path()

	if (P2N_maxMissing < 5) PSN_maxMissing <- 5
	if (P2N_maxMissing >100) PSN_maxMissing <- 100
	if (!P2N_threshType %in% c("off","auto")) P2N_threshType <- "off"

	if (file.exists(tmpDir))  unlink(tmpDir,recursive=TRUE)
	if (file.exists(dataDir)) unlink(dataDir,recursive=TRUE)
	dir.create(dataDir)

	curwd <- getwd()
	tryCatch( {
	
	system2('cp', args=c('-r',netDir,tmpDir))
	setwd(tmpDir)

	# write batch.txt and ids.txt, currently required 
	# for these scripts to work
	netList1 <- dir(path=netDir,pattern="profile$")
	# must copy networks dir to tmp instead of copying contents via
	# cp -r networks/* tmp
	# latter gives "argument list too long" error in OS/X.
	netList2	<- dir(path=netDir, pattern=netSfx)
	netList <- c(netList1,netList2)

	if (verbose) message(sprintf("Got %i networks",length(netList)))
	idFile	<- sprintf("%s/ids.txt",outDir)
	writeQueryBatchFile(netDir,netList,netDir,idFile,...)
	system2('cp',args=c(sprintf("%s/batch.txt",netDir), '.')) 
	write.table(patientID,file=idFile,sep="\t",
				row=FALSE,col=FALSE,quote=FALSE)

	#### Step 1. placeholder files
	if (verbose) message("\t* Creating placeholder files")

	# move files to tmpDir
	#file.copy(netDir,tmpDir,recursive=TRUE)
	file.copy(idFile, sprintf("%s/ids.txt",tmpDir))
	system2('chmod', args=c('u+w', '*.*'))

	fBasic <- c("ATTRIBUTES.txt", "ATTRIBUTE_GROUPS.txt",
				"ONTOLOGY_CATEGORIES.txt","ONTOLOGIES.txt", "TAGS.txt", 
				"NETWORK_TAG_ASSOC.txt", "INTERACTIONS.txt")
	for (f in fBasic) {
		file.create(f)
	}

	#### Step 2. recoding networks in a format GeneMANIA prefers
	# TODO this step uses a Python script. The script is simple enough 
	# that it should be written in R. Avoid calls to other languages 
	# unless there is additional value in 
	# doing so.
	if (verbose) message("\t* Populating database files, recoding identifiers")
	dir.create("profiles")
	if (!is.null(altBaseDir)) {
		baseDir <- altBaseDir
	} else {
		baseDir <- path.package("netDx")
	}
	procNet <- paste(baseDir,"python/process_networks.py",sep="/")

	system2('python2', args=c(procNet, 'batch.txt'),wait=TRUE)
	# using new jar file
	#### Step 3. (optional). convert profiles to interaction networks.
	### TODO. This step is currently inefficient. We are writing all the
	### profile files (consumes disk space) in makePSN_NamedMatrix.R
	### and then converting them 
	### enmasse to interaction networks here. 
	### Necessary because process_networks.py is prereq for ProfileToNetwork
	### Driver and that doesn't get called until the step above.
	if (length(netList1)>0) {
		if (verbose) message("\t* Converting profiles to interaction networks")

		cl	<- makeCluster(numCores,outfile=sprintf("%s/P2N_log.txt",tmpDir))
		registerDoParallel(cl)
	
		if (simMetric=="pearson") {
			corType <- "PEARSON"
		} else if (simMetric == "MI") {
			corType <- "MUTUAL_INFORMATION"
		}

		args <- c(sprintf("-Xmx%iG",JavaMemory),'-cp', GM_jar)
		args <- c(args,'org.genemania.engine.core.evaluation.ProfileToNetworkDriver')
		args <- c(args, c('-proftype', 'continuous','-cor', corType))
		args <- c(args, c('-threshold', P2N_threshType,'-maxmissing',
				sprintf("%1.1f",P2N_maxMissing)))
		profDir <- sprintf("%s/profiles",tmpDir)
		netOutDir <- sprintf("%s/INTERACTIONS",tmpDir)
		tmpsfx <- sub("\\$","",netSfx)

		print(system.time(
		foreach (curProf=dir(path=profDir,pattern="profile$")) %dopar% {
			args2 <- c('-in', sprintf("%s/%s",profDir,curProf))
			args2 <- c(args2, '-out', sprintf("%s/%s",netOutDir, 
				sub(".profile",".txt",curProf)))
			args2 <- c(args2, '-syn', sprintf("%s/1.synonyms",tmpDir),
				'-keepAllTies', '-limitTies')
			system2('java', args=c(args, args2),wait=TRUE,stdout=NULL)
		}
		))
		stopCluster(cl)
		netSfx=".txt"
		netList2 <- dir(path=netOutDir,pattern=netSfx)

		if (verbose) message(sprintf("Got %i networks from %i profiles", 
			length(netList2),length(netList)))
		netDir <- netOutDir
		netList <- netList2; rm(netOutDir,netList2)
	}

	#### Step 4. Build GeneMANIA index
	if (verbose) message("\t* Build GeneMANIA index")
	setwd(dataDir)
	args <- c('-Xmx10G','-cp',GM_jar)
	args <- c(args,'org.genemania.mediator.lucene.exporter.Generic2LuceneExporter')
	args <- c(args, sprintf("%s/db.cfg",tmpDir),tmpDir,
	sprintf("%s/colours.txt",tmpDir))
	system2('java', args,wait=TRUE)

	system2('mv', args=c(sprintf("%s/lucene_index/*",dataDir), 
		sprintf("%s/.",dataDir)))

	#### Step 5. Build GeneMANIA cache
	if (verbose) message("\t* Build GeneMANIA cache")
	args <- c('-Xmx10G','-cp',GM_jar,'org.genemania.engine.apps.CacheBuilder')
	args <- c(args,'-cachedir','cache','-indexDir','.',
		'-networkDir',sprintf("%s/INTERACTIONS",tmpDir),
		'-log',sprintf("%s/test.log",tmpDir))
	system2('java',args=args,stdout=NULL)

	#### Step 6. Cleanup.
	if (verbose) message("\t * Cleanup")
	GM_xml	<- sprintf("%s/extdata/genemania.xml",baseDir)
	system2('cp', args=c(GM_xml, sprintf("%s/.",dataDir))) 

	}, error=function(ex) {
		print(ex)
		return(NA)
	}, finally={
		setwd(curwd)
	})

	return(list(dbDir=dataDir,netDir=netDir))
}