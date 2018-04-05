#!/bin/bash
	clear
	reconstruction_dir="/home/moyuan/Documents/RA/Data_Test"
	suncg_dir="/home/moyuan/Documents/RA/Data_raw/house/"

	scenes=`ls $reconstruction_dir`
	$empty_num=0
	$scene_num=0

	for eachfile in $scenes
	do
		echo $eachfile

		if  [[ $eachfile != "timelog.txt" ]] ;
		then
			# remove previous views
			cd $suncg_dir$eachfile
			scene_num=$((scene_num+1))
			if [ -f $FILE ]; then
				if [ -s outputcamerafile ] ;
				then
					empty_num=$((empty_num+1))
					echo $empty_num;
				fi
			else
				echo "error: no outputcamera file!!"
			fi

		fi
	done