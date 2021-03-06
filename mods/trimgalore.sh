#!/bin/bash

# Script to trim adapters using TRIMGALORE (tapping into CUTADAPT)
# It takes a <Run>/*.$FASTQ[.gz] file and gets the file containing the contaminats
# via config and writes out <Run>_trim/*.$FASTQ[.gz]
#
# author: Fabian Buske
# date: April. 2013

# messages to look out for -- relevant for the QC.sh script:
# QCVARIABLES,

echo ">>>>> readtrimming with TRIMGALORE "
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> trimgalore.sh $*"

while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of NGSANE
        -f | --file )           shift; f=$1 ;; # fastq file
        -o | --outdir )         shift; OUTDIR=$1 ;; # output dir
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

#JAVAPARAMS="-Xmx"$(expr $MEMORY_CUTADAPT - 1 )"G"
#echo "JAVAPARAMS "$JAVAPARAMS

echo "********** programs"
for MODULE in $MODULE_TRIMGALORE; do module load $MODULE; done  # save way to load modules that itself load other modules
export PATH=$PATH_TRIMGALORE:$PATH;
module list
echo "PATH=$PATH"
echo -e "--trim galore --\n "$(trim_galore --version  | grep version  | tr -d ' ')
[ -z "$(which trim_galore)" ] && echo "[ERROR] no trim_galore detected" && exit 1

#SAMPLENAME
# get basename of f
n=${f##*/}

#is paired ?
if [ -e ${f/$READONE/$READTWO} ]; then
    echo "[NOTE] PAIRED library"
    PAIRED="1"
else
    echo "[NOTE] SINGLE library"
    PAIRED="0"
fi

FASTQDIR=$(basename $(dirname $f))
o=${f/$FASTQDIR/$FASTQDIR"_trim"}
FASTQDIRTRIM=$(dirname $o)

if [ -n "$DMGET" ]; then
    dmget -a ${f/$READONE/"*"}
fi

echo $FASTQDIRTRIM
if [ ! -d $FASTQDIRTRIM ]; then mkdir -p $FASTQDIRTRIM; fi
echo $f "->" $o
if [ "$PAIRED" = "1" ]; then echo ${f/$READONE/$READTWO} "->" ${o/$READONE/$READTWO} ; fi

echo "********** get contaminators"

if [ ! -n "$TRIMGALORE_ADAPTER1" ] && [ ! -n "$TRIMGALORE_ADAPTER2" ];then echo "TRIMGALORE_ADAPTER1 and 2 not defined in $CONFIG, default to 'AGATCGGAAGAGC'"; fi
CONTAM=""
if [ -n "$TRIMGALORE_ADAPTER1" ]; then
	CONTAM="$CONTAM --adapter $TRIMGALORE_ADAPTER1"
fi
if [ "$PAIRED" = "1" ] && [ -n "$TRIMGALORE_ADAPTER2" ]; then
	CONTAM="$CONTAM --adapter2 $TRIMGALORE_ADAPTER2"
fi
echo $CONTAM

echo "********** trim"
# Paired read
if [ "$PAIRED" = "1" ]
then
    RUN_COMMAND="trim_galore $TRIMGALORE_OPTIONS $CONTAM --paired --output_dir $FASTQDIRTRIM $f ${f/$READONE/$READTWO}"
else
    RUN_COMMAND="trim_galore $TRIMGALORE_OPTIONS $CONTAM --output_dir $FASTQDIRTRIM $f"
fi
echo $RUN_COMMAND
eval $RUN_COMMAND

echo "********** rename files"
if [ "$PAIRED" = "1" ]; then
    mv $FASTQDIRTRIM/${n/$READONE.$FASTQ/$READONE"_val_1".fq.gz} $FASTQDIRTRIM/$n
    mv $FASTQDIRTRIM/${n/$READONE.$FASTQ/$READTWO"_val_2".fq.gz} $FASTQDIRTRIM/${n/$READONE/$READTWO}
else
    mv $FASTQDIRTRIM/${n/$READONE.$FASTQ/$READONE"_trimmed".fq.gz} $FASTQDIRTRIM/$n
fi

echo "********** zip"
$GZIP -t $FASTQDIRTRIM/$n 2>/dev/null
if [[ $? -ne 0 ]]; then
    $GZIP -f $FASTQDIRTRIM/$n
    mv $FASTQDIRTRIM/$n.gz $FASTQDIRTRIM/$n
    if [ "$PAIRED" = "1" ]; then
        $GZIP -f $FASTQDIRTRIM/${n/$READONE/$READTWO}
        mv $FASTQDIRTRIM/${n/$READONE/$READTWO}.gz $FASTQDIRTRIM/${n/$READONE/$READTWO}
    fi
fi

RUNSTATS=$OUT/runStats/$TASKTRIMGALORE
mkdir -p $RUNSTATS
mv $FASTQDIRTRIM/*_trimming_report.txt $RUNSTATS

echo ">>>>> readtrimming with TRIMGALORE - FINISHED"
echo ">>>>> enddate "`date`

