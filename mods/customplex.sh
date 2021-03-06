#!/bin/bash

# Custom de multiplexing
# author: Denis Bauer 
# date: Nov. 2011



# messages to look out for -- relevant for the QC.sh script:
# QCVARIABLES,


echo ">>>>> customplex with fastXtoolkit "
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> customplex.sh $*"


function usage {
echo -e "usage: $(basename $0) -k NGSANE -f FASTA -r REFERENCE -o OUTDIR [OPTIONS]

Script

required:
  -k | --toolkit <path>     config file 
  -f | --fastq <file>       fastq file
  -b | --barcode <file>     barcode
  -o | --outdir <path>      output dir

"
exit
}

if [ ! $# -gt 3 ]; then usage ; fi

#DEFAULTS
THREADS=1

#INPUTS
while [ "$1" != "" ]; do
    case $1 in
        -k | toolkit )          shift; CONFIG=$1 ;; # ENSURE NO VARIABLE NAMES FROM CONFIG
        -t | --threads )        shift; THREADS=$1 ;; # number of CPUs to use
        -f | --fastq )          shift; f=$1 ;; # fastq file
        -b | --barcode )        shift; BARCODR=$1 ;; # reference genome
        -o | --outdir )         shift; OUTDIR=$1 ;; # output dir
        -p | --prefix )         shift; PREFIX=$1 ;; # prefix for the line
        -h | --help )           usage ;;
        * )                     usage
    esac
    shift
done


#PROGRAMS (note, both configs are necessary to overwrite the default, here:e.g.  TASKTOPHAT)
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

echo $OUTDIR
# get basename of f
n=${f##*/}

if [[ $f = *.fastq.gz ]]; then
    echo "unzip first"
    f=${f/fastq.gz/fastq}
    if [ ! -e $f ]; then gunzip -c $f.gz >$f; fi
    if [ ! -e ${f/$READONE/$READTWO} ]; then gunzip -c ${f/$READONE/$READTWO}.gz >${f/$READONE/$READTWO} ; fi
    n=${n/fastq.gz/fastq}
fi


# put read1 and read2 side by side
echo "********* read1-read2"
perl ${NGSANE_BASE}/bin/shuffleSequences_fastq_sidebyside.pl $f ${f/$READONE/$READTWO} \
    $OUTDIR/${n/$READONE/"sidebyside_R1"}

# demultiplex them
echo "********* read1-read2 demult"
cat $OUTDIR/${n/$READONE/"sidebyside_R1"} | $FASTXTK/fastx_barcode_splitter.pl  \
    --bcfile $CUSTOMBARCODE --bol --mismatches 1 --prefix $OUTDIR/$PREFIX"_R1_" \
    --suffix "_seq.fastq" > $OUTDIR/$PREFIX"_R1_read_counts"

# find unmatched
echo "********* read1-read2 unmatched"
perl ${NGSANE_BASE}/bin/splitintoforandrevreads.pl $OUTDIR/$PREFIX"_R1_unmatched"

# put for the unmached read one first
echo "********* read2-read1"
perl ${NGSANE_BASE}/bin/shuffleSequences_fastq_sidebyside.pl \
    $OUTDIR/$PREFIX"_R1_unmatched_2_seq.fastq" \
    $OUTDIR/$PREFIX"_R1_unmatched_1_seq.fastq" \
    $OUTDIR/${n/$READONE/"sidebyside_R2"}

# demultiplex with read2/read1
echo "********* read2-read1 demult"
cat $OUTDIR/${n/$READONE/"sidebyside_R2"} | $FASTXTK/fastx_barcode_splitter.pl \
    --bcfile $CUSTOMBARCODE --bol --mismatches 1 --prefix $OUTDIR/$PREFIX"_R2_" \
    --suffix "_seq.fastq" > $OUTDIR/$PREFIX"_R2_read_counts"

echo "********* cat and trim"
for p in $( ls $OUTDIR/$PREFIX"_R1"*.fastq ); do

    # skip the unmatched ones
    if ( $p == *unmatched* ); then continue; fi

    RONE=${p/_seq.fastq/}
    RTWO=${RONE/R1/R2}

    echo $RONE
    echo $RTWO

    # unconcatinate again
    perl ${NGSANE_BASE}/bin/splitintoforandrevreads.pl $RONE
    perl ${NGSANE_BASE}/bin/splitintoforandrevreads_2readfirst.pl $RTWO

    # get read1 and read2
    cat $RONE"_1_seq.fastq" $RTWO"_1_seq.fastq" > ${RONE/"_R1"/}"_read1untr_seq.fastq"
    cat $RONE"_2_seq.fastq" $RTWO"_2_seq.fastq" > ${RTWO/"_R2"/}"_read2untr_seq.fastq"

    # trim 
    #echo "trimming with sanger quality score (-Q 33) "${RONE/"_R1"/}"_read1untr_seq.fastq"
    $FASTXTK/fastx_trimmer -Q 33 -f 7 -z -i ${RONE/"_R1"/}"_read1untr_seq.fastq" -o ${RONE/"_R1"/}"_"$READONE.fastq.gz
    #echo "trimming with sanger quality score (-Q 33) "${RTWO/"_R2"/}"_read2untr_seq.fastq"
    $FASTXTK/fastx_trimmer -Q 33 -f 7 -z -i ${RTWO/"_R2"/}"_read2untr_seq.fastq" -o ${RTWO/"_R2"/}"_"$READTWO.fastq.gz

    rm $RONE"_seq.fastq" $RTWO"_seq.fastq"
    rm $RONE"_1_seq.fastq" $RTWO"_1_seq.fastq"
    rm $RONE"_2_seq.fastq" $RTWO"_2_seq.fastq"
    rm ${RONE/"_R1"/}"_read1untr_seq.fastq"
    rm ${RTWO/"_R2"/}"_read2untr_seq.fastq"
 
done

rm $OUTDIR/$PREFIX"_R1_unmatched_seq.fastq"
rm $OUTDIR/$PREFIX"_R2_unmatched_seq.fastq"
rm $OUTDIR/${n/$READONE/"sidebyside_R1"}
rm $OUTDIR/${n/$READONE/"sidebyside_R2"}

echo ">>>>> customplex with fastXtoolkit - FINISHED"
echo ">>>>> enddate "`date`



exit

#######3
# this is just with one read
######

# need to deal with read one and read two
# split accodrint to barcodes
less $f | $FASTXTK/fastx_barcode_splitter.pl --bcfile $CUSTOMBARCODE --bol --mismatches 2 \
    --prefix $OUTDIR/$PREFIX --suffix ".fastq"

# trim barcode sequence and gzip
for f in $( ls $OUTDIR/*fastq ); do
    #less $f | $FASTXTK/fastx_trimmer -f 7 -z -o ${f/.fastq/.r1} -Q 33
    $FASTXTK/fastx_trimmer -f 7 -z -i $f -o ${f/.fastq/.fastq.gz} -Q 33
done


