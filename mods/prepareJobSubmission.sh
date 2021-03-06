#!/bin/sh

#
# General template for submitting a job 
#

#INPUTS
while [ "$1" != "" ]; do
    case $1 in
	-k | --toolkit )        shift; CONFIG=$1 ;;    # location of the NGSANE repository
	-i | --input )          shift; ORIGIN=$1 ;;    # subfile in $SOURCE
	-e | --fileending )     shift; ENDING=$1 ;;    # select source files of a specific ending
	-t | --task )           shift; TASK=$1 ;;      # what to do
	-n | --nodes )          shift; NODES=$1;;
	-c | --cpu    )         shift; CPU=$1 ;;       # CPU used
	-m | --memory )         shift; MEMORY=$1;;     # min Memory required
	-w | --walltime )       shift; WALLTIME=$1;;
	-p | --command )        shift; COMMAND=$1;;
	--postcommand )         shift; POSTCOMMAND=$1;;
	--postnodes )           shift; POSTNODES=$1;;
	--postcpu )             shift; POSTCPU=$1 ;;   # CPU used for postcommand
	--postmemory )          shift; POSTMEMORY=$1;; # Memory used for postcommand
	--postwalltime )        shift; POSTWALLTIME=$1;;
	-r | --reverse )        REV="1";;
	-d | --nodir )          NODIR="nodir";;
	-a | --armed )          ARMED="armed";;
	--keep )                KEEP="keep";;
	--direct )              DIRECT="direct";;
	--first )               FIRST="first";;
	--postonly )            POSTONLY="postonly" ;;
	-h | --help )           usage ;;
	* )                     echo "prepareJobSubmission.sh: don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

echo "********* $TASK $NODIR"

#echo $COMMAND

if [ ! -d $QOUT/$TASK ]; then mkdir -p $QOUT/$TASK; fi

## Select files in dir to run
if [ ! -e $QOUT/$TASK/runnow.tmp ]; then
    for dir in ${DIR[@]}; do
      #ensure dirs are there...
      if [ ! -n "$NODIR" ]; then
 	 if [ ! -d $OUT/$dir/$TASK ]; then mkdir -p $OUT/$dir/$TASK; fi
      fi
      # print out 
      if [ -n "$REV" ]; then
	  for f in $( ls $SOURCE/$dir/$ORIGIN/*$ENDING); do
              echo $f >> $QOUT/$TASK/runnow.tmp
          done
      else
	  for f in $( ls $SOURCE/$ORIGIN/$dir/*$ENDING); do
	      echo $f >> $QOUT/$TASK/runnow.tmp
	  done
      fi
  done
fi

MYPBSIDS="" # collect job IDs for postcommand
DIR=""
FILES=""
for i in $(cat $QOUT/$TASK/runnow.tmp); do

    n=$(basename $i) 
    # ending : fastq/xx or xx/bwa
    dir=$(dirname $i | gawk '{n=split($1,arr,"/"); print arr[n]}')
    if [ -n "$REV" ]; then dir=$(dirname $i | gawk '{n=split($1,arr,"/"); print arr[n-1]}'); fi
    name=${n/$ENDING/}
    echo ">>>>>"$dir"/"$name
                

    COMMAND2=${COMMAND//<FILE>/$i} # insert files for which parallele jobs are submitted
    COMMAND2=${COMMAND2//<DIR>/$dir} # insert output dir
    COMMAND2=${COMMAND2//<NAME>/$name} # insert ??

    DIR=$DIR" $dir"
    FILES=$FILES" $i"

    # only postcommand 
    if [[ -n "$POSTONLY" || -z "$COMMAND" ]]; then continue; fi

    echo $COMMAND2

    if [ -n "$DIRECT" ]; then eval $COMMAND2; fi

    if [ -n "$ARMED" ]; then

    echo $ARMED

    # remove old submission output logs
    if [ -e $QOUT/$TASK/$dir'_'$name.out ]; then rm -rf $QOUT/$TASK/$dir'_'$name.*; fi

    # submit and collect pbs scheduler return
    #RECIPT=$($BINQSUB -j oe -o $QOUT/$TASK/$dir'_'$name'.out' -w $(pwd) -l $NODES \
    #    -l vmem=$MEMORY -N $TASK'_'$dir'_'$name -l walltime=$WALLTIME $QSUBEXTRA \
    #    -command "$COMMAND2")
    
    # record task in log file
    cat $CONFIG ${NGSANE_BASE}/conf/header.sh > $QOUT/$TASK/job.$(date "+%Y%m%d").log

    RECIPT=$($BINQSUB -a "$QSUBEXTRA" -k $CONFIG -m $MEMORY -n $NODES -c $CPU -w $WALLTIME \
	-j $TASK'_'$dir'_'$name -o $QOUT/$TASK/$dir'_'$name'.out' \
	--command "$COMMAND2")
    echo -e "Jobnumber $RECIPT"
    MYPBSIDS=$MYPBSIDS":"$RECIPT
#    MYPBSIDS=$MYPBSIDS":"$(echo "$RECIPT" | gawk '{print $(NF-1); split($(NF-1),arr,"."); print arr[1]}' | tail -n 1)

    # if only the first task should be submitted as test
    if [ -n "$FIRST" ]; then exit; fi
    
    fi
done


if [ -n "$POSTCOMMAND" ]; then
   # process for postcommand
    DIR=$(echo -e ${DIR// /\\n} | sort -u | gawk 'BEGIN{x=""};{x=x"_"$0}END{print x}' | sed 's/__//')
    FILES=$(echo -e $FILES | sed 's/ /,/g')
    POSTCOMMAND2=${POSTCOMMAND//<FILE>/$FILES}
    POSTCOMMAND2=${POSTCOMMAND2//<DIR>/$DIR}

    echo ">>>>>"$DIR" wait for "$MYPBSIDS
    echo $POSTCOMMAND2

    if [[ -n "$DIRECT" || -n "$FIRST" ]]; then eval $POSTCOMMAND2; exit; fi
    if [[ -n "$ARMED" ||  -n "$POSTONLY" ]]; then

    # remove old submission output logs
    if [ -e $QOUT/$TASK/$DIR'_postcommand.out' ]; then rm -rf $QOUT/$TASK/$DIR"_postcommand.out"; fi

    # record task in log file
    cat $CONFIG ${NGSANE_BASE}/conf/header.sh > $QOUT/$TASK/job.$(date "+%Y%m%d").log

    # unless specified otherwise use HPC parameter from main job 
    if [ -z "$POSTNODES" ];    then POSTNODES=$NODES; fi
    if [ -z "$POSTCPU" ];      then POSTCPU=$CPU; fi
    if [ -z "$POSTMEMORY" ];   then POSTMEMORY=$MEMORY; fi
    if [ -z "$POSTWALLTIME" ]; then POSTWALLTIME=$WALLTIME; fi

    RECIPT=$($BINQSUB -a "$QSUBEXTRA" -W "$MYPBSIDS" -k $CONFIG -m $POSTMEMORY -n $POSTNODES -c $POSTCPU -w $POSTWALLTIME \
	-j $TASK'_'$DIR'_postcommand' -o $QOUT/$TASK/$DIR'_postcommand.out' \
	--command "$POSTCOMMAND2")

    echo -e "$RECIPT"

    fi
fi

if [ ! -n "$KEEP" ]; then  rm -f $QOUT/$TASK/runnow.tmp ; fi
