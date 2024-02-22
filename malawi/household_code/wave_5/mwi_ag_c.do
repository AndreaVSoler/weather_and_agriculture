* Project: WB Weather
* Created on: Feb 2024
* Created by: alj
* Edited on: 22 Feb 2024
* Edited by: alj 
* Stata v.18

* does
	* 

* assumes
	* 
* TO DO:
	* complete


* **********************************************************************
* 0 - setup
* **********************************************************************

* define paths
	loc		root 	= 	"$data/household_data/malawi/wave_5/raw"	
	loc		export 	= 	"$data/household_data/malawi/wave_5/refined"
	loc		logout 	= 	"$data/household_data/malawi/logs"

* open log
	cap 	log			close
	log 	using 		"`logout'/mwi_ag_mod_c", append


* **********************************************************************
* 1 - clean plot area 
* **********************************************************************

* load data
	use 			"`root'/ag_mod_c.dta", clear
	
* drop observations with missing plot id variable or garden id variable 
	summarize 		if missing(plotid)
	drop 			if missing(plotid)
	*** 0 dropped
	summarize 		if missing(gardenid)
	drop			if missing(gardenid)
	*** 0 dropped 
	isid 			case_id HHID gardenid plotid
	
* generate self-reported land area in hectares 
	tab 			ag_c04a, missing 
	generate		conversion = 1 if ag_c04b == 2 
	replace 		conversion = 0.40468564 if ag_c04b == 1
	replace 		conversion = 0.0001 if ag_c04b == 3 
	drop			if ag_c04b == 4 
	*** 8 observations dropped 
	generate 		selfreport = conversion * ag_c04a if ag_c04a!=0
	summarize		selfreport, detail	
	*** mean = 0.31, median = 0.20 
	
* generate GPS land area of plot in hectares 
* as a starting point, expect that GPS is more accurate than self-report 
	summarize 		ag_c04c, detail 
	generate 		gps = ag_c04c * 0.40468564 if ag_c04c!=0
	summarize 		gps, detail
	*** mean = 0.32, median = 0.24
	
* compare GPS and self-report & look for outliers 
	summarize 		gps, detail
	*** same command as above used in order to easily access r-class stored results
	list 			gps selfreport if !inrange(gps,`r(p50)'-(3*`r(sd)'),`r(p50)'+(3*`r(sd)')) & !missing(gps)	
	*** look at GPS and self-reported observations that are > ±3 Std. Dev's from the median 
	*** these appear to be incorrect GPS values, as the self-report is nowhere close, but there are a lot

* GPS on larger side of self-report 
	tabulate 		gps if gps>2, plot					
	*** a few high values but most look reasonable - largest is 15 
	list 			gps selfreport if gps>3 & !missing(gps), sep(0)	
	*** there are < 20 obs≤3 ha, so let's look more closely at the relationship between self-report & GPS for observations >3
	*** in this case GPS appear to be CLEAR errors: measured 15 hectares, but reported <1 (e.g.)
	
* GPS on the smaller side vs self-report 
	tabulate 		gps if gps<0.1						
	*** GPS data distribution is lumpy for small plots due to the precision constraints of the technology 
	*** in this group there are 3357 obs 
	list 			gps selfreport if gps<0.01, sep(0)		
	*** still lots of mismatches 
	
* correlations
	pwcorr 			selfreport gps
	*** 0.62 - okay but not great
	pwcorr 			selfreport gps if inrange(gps,0.002,4)
	*** not much higher = 0.65
	*** tested down to 0.001 to 1 - really no differences, always around 0.65
	*** my inclincation, in reviewing, is to not trust gps 
	scatter			selfreport gps

* make plotsize using GPS area if it is within reasonable range
	generate 		plotsize = gps if gps>0.002 & gps<4
	summarize 			selfreport gps plotsize	
	*** we have some self-report information where we are missing plotsize 
	summarize 			selfreport if missing(plotsize), detail

* prepare for imputation
* need district variables 
	merge m:1 case_id using "`root'/hh_mod_a_filt.dta", keepusing(district) assert (2 3) keep (3) nogenerate
	*** 17,685 matched
	
* impute missing plotsizes 
	mi 	set wide 
	mi 				xtset, clear
	mi 				register imputed plotsize
	mi 				impute pmm plotsize selfreport i.district, add(1) rseed(245780) noisily dots force knn(5) bootstrap 
	mi unset 

* summarize results of imputation
	tabulate 		mi_miss	
	*** this binary = 1 for the full set of observations where plotsize is missing
	tabstat 		gps selfreport plotsize plotsize_1_, ///
					by(mi_miss) statistics(n mean min max) columns(statistics) longstub format(%9.3g) 			
					
* cannot do anyting about missing plot sizes from above 
	list 			gps selfreport plotsize if missing(plotsize_1_), sep(0)
	drop 			if missing(plotsize_1_)
	* drop 28 observations 
	
* manipulate variables for export
	rename 			(plotsize plotsize_1_)(plotsize_raw plotsize)
	label 			variable plotsize		"Plot Size (ha)"

* restrict to variables of interest 
	keep  			case_id HHID gardenid plotid plotsize
	order 			case_id HHID gardenid plotid plotsize 

* **********************************************************************
* 2 - end matter, clean up to save
* **********************************************************************
	
	compress
	describe
	summarize 
	
* save data
	save 			"`export'/ag_mod_c.dta", replace

* close the log
	log			close


/* END */
