#!/bin/bash

################
### SETTINGS ###
################

# DEFAULTS #
############
SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )" # Get script location which will be the signal base dir

# Function to check if element is in an array
containsElement () {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

# Base Parameters #
DIRECTORY=''
ILLUMINA=false
NANOPORE=false
PRIMER_SCHEME=0
CORES="2"
RUNNAME="run"
METADATA_TSV=''
PDF=false

# Values to Check #
schemeArray=('articV3' 'freed' 'resende' 'V2resende')

HELP="
USAGE:
    bash $SCRIPTPATH/run_signal.sh -p PRIMER_SCHEME -d CONNOR_LAB_RESULTS/ <OPTIONAL FLAGS>
    bash $SCRIPTPATH/run_signal.sh --update
    
Flags:
    NEEDED:
    -p  --primer-scheme  :  Specify input data primer scheme
                Available Primer Schemes: articV3, freed, resende, V2resende
    -d  --directory      :  Directory of the connor-lab pipeline results, normally 'results'

    OPTIONAL:
    -c  --cores          :  Number of Cores to use in Signal. Default is 2
    -n  --run-name       :  Run name for final ncov-tools outputs. Default is 'run'
    -m  --metadata       :  Add metadata to the run. Must be in TSV format with atleast columns called 'sample', 'date', and 'ct'
    --pdf                :  If you have pdflatex installed runs ncov-tools pdf output

    OTHER:
    --update  :  Passing --update will update ncov-tools pip dependencies, pangolin and pangoLEARN along with this repo and then exit
"

### END DEFAULTS ###

# INPUTS #
##########

# Check for Args #
if [ $# -eq 0 ]; then
    echo "$HELP"
    exit 0
fi

# Set Arguments #
while [ "$1" = "--directory" -o "$1" = "-d" -o "$1" = "--primer-scheme" -o "$1" = "-p" -o "$1" = "--cores" -o "$1" = "-c" -o "$1" = "--run-name" -o "$1" = "-n" -o "$1" = "-m" -o "$1" = "--metadata" -o "$1" = "--pdf" -o "$1" = "--update" ];
do
    if [ "$1" = "--directory" -o "$1" = "-d" ]; then
        shift
        DIRECTORY=$1
        shift
    elif [ "$1" = "--primer-scheme" -o "$1" = "-p" ]; then
        shift
        PRIMER_SCHEME=$1
        shift
    elif [ "$1" = "--cores" -o "$1" = "-c" ]; then
        shift
        CORES=$1
        shift
    elif [ "$1" = "--run-name" -o "$1" = "-n" ]; then
        shift
        RUNNAME=$1
        shift
    elif [ "$1" = "--metadata" -o "$1" = "-m" ]; then
        shift
        METADATA_TSV=$1
        shift
    elif [ "$1" = "--pdf" ]; then
        PDF=true
        shift
    elif [ "$1" = "--update" ]; then
        shift
        # Scripts
        cd $SCRIPTPATH
        git pull

        # ncov-tools Environment (not managed by snakemake unfortunately)
        eval "$(conda shell.bash hook)"
        printf "\n Updating ncov-tools environmen"
        conda activate ncov-qc
        pip install git+https://github.com/cov-lineages/pango-designation.git --upgrade
        pangolin --update
        pip install ncov-parser --upgrade
        pip install git+https://github.com/jts/ncov-watch.git --upgrade
        echo "Done"
        exit
    else
        shift
    fi
done

# CHECK INPUTS #
################

if [ -d "$DIRECTORY" ]; then
    
    if [ -d $DIRECTORY/articNcovNanopore_sequenceAnalysisNanopolish_articMinIONNanopolish ]; then
        echo "Nanopore data found"
        NANOPORE=true
        FILE_PATH=$(realpath $DIRECTORY/articNcovNanopore_sequenceAnalysisNanopolish_articMinIONNanopolish)
    else
        echo 'I dont have illumina set yet'
        exit 1
    fi
else
    if [ $DIRECTORY = 0 ]; then
        echo "ERROR: Please input a paired fastq directory with '-d'"
        echo "$HELP"
        exit 1
    else
        echo "ERROR: Directory '$DIRECTORY' does not exist"
        echo "Please input a valid paired fastq directory"
        exit 1
    fi
fi

if containsElement "$PRIMER_SCHEME" "${schemeArray[@]}"; then
    echo "Using primer scheme $PRIMER_SCHEME"
else
    if [ $PRIMER_SCHEME = 0 ]; then
        echo "ERROR: Please specify a primer scheme"
        echo "Primer schemes available are ${schemeArray[@]}"
        exit 1
    else
        echo "ERROR: $PRIMER_SCHEME unavailable"
        echo "Primer schemes available are ${schemeArray[@]}"
        exit 1
    fi
fi

if [[ $CORES == +([0-9]) ]]; then
    echo "Using $CORES cores for analysis"
else
    echo "ERROR: Cores input (-c) not an integer"
    exit 1
fi


if [ $METADATA_TSV = '' ]; then
    :
elif [ -f $METADATA_TSV ]; then
    echo "$METADATA_TSV file found, using it"
    FULL_PATH_METADATA=$(realpath $METADATA_TSV)
else
    echo "ERROR: Metadata input $METADATA_TSV was not found"
    exit 1
fi

################################
### OVERALL AUTOMATION SETUP ###
################################

# CONDA #
#########
eval "$(conda shell.bash hook)"

# Install mamba into base environment if not there
if [[ $(conda list | awk '{print $1}' | grep "^mamba"'$') ]]; then
    :
else
    echo "Installing mamba 'mamba-signal' environment to install needed dependencies"
    conda install -y mamba
fi

# Check if env exists in user envs. NOTE if it is a env not listed in `conda env list` it will error out
if [[ $(conda env list | awk '{print $1}' | grep "^ncov-qc"'$') ]]; then
    echo "ncov-qc environment found"
else
    echo "ncov-tools environment was not found. Attempting to make the environment"
    mamba env create -f=$SCRIPTPATH/data/environment.yml
fi

conda activate ncov-qc

# SETUP NCOV-TOOLS #
####################

# Get ncov-tools
git clone --depth 1 https://github.com/jts/ncov-tools
# config
cp $SCRIPTPATH/data/config.yaml ./ncov-tools

if [ $METADATA_TSV = 0 ]; then
    sed -i -e 's/^metadata/#metadata/' ./ncov-tools/config.yaml
else
    # Check if metadata has correct ncov-tools columns, if not we only append it to final output csv
    if $(head -n 1 $FULL_PATH_METADATA | grep -q ct) && $(head -n 1 $FULL_PATH_METADATA | grep -q date); then
        echo "Metadata contains correct ncov-tools headers"
    else
        echo "Metadata is missing ncov-tools headers, not adding"
        sed -i -e 's/^metadata/#metadata/' ./ncov-tools/config.yaml
    fi
    cp $FULL_PATH_METADATA ./ncov-tools/metadata.tsv
fi

cd ncov-tools
git clone https://github.com/phac-nml/primer-schemes.git

# Set Primer-Scheme in config
if [ "$PRIMER_SCHEME" == "articV3" ]; then
    echo "amplicon_bed: primer-schemes/nCoV-2019/artic_v3/ncov-qc_V3.scheme.bed" >> ./config.yaml
    echo "primer_bed: primer-schemes/nCoV-2019/artic_v3/nCoV-2019.bed" >> ./config.yaml

elif [ "$PRIMER_SCHEME" == "freed" ]; then
    echo "amplicon_bed: primer-schemes/nCoV-2019/freed/ncov-qc_freed.scheme.bed" >> ./config.yaml
    echo "primer_bed: primer-schemes/nCoV-2019/freed/nCoV-2019.bed" >> ./config.yaml

elif [ "$PRIMER_SCHEME" == "resende" ]; then
    echo "amplicon_bed: primer-schemes/nCoV-2019/2kb_resende/ncov-qc_resende.scheme.bed" >> ./config.yaml
    echo "primer_bed: primer-schemes/nCoV-2019/2kb_resende/nCoV-2019.bed" >> ./config.yaml

elif [ "$PRIMER_SCHEME" == "V2resende" ]; then
    echo "amplicon_bed: primer-schemes/nCoV-2019/2kb_resende_v2/nCoV-2019.bed" >> ./config.yaml
    echo "primer_bed: primer-schemes/nCoV-2019/2kb_resende_v2/ncov-qc_resende.scheme.bed" >> ./config.yaml
fi

# Get reference sequence and index it
cp primer-schemes/nCoV-2019/freed/nCoV-2019.reference.fasta ./
samtools faidx nCoV-2019.reference.fasta
echo "run_name: '$RUNNAME'" >> ./config.yaml

if [ "$ILLUMINA" = true ]; then
    echo "platform: illumina" >> ./config.yaml
else
    echo "platform: oxford-nanopore" >> ./config.yaml
    echo 'bam_pattern: "{data_root}/{sample}.sorted.bam"' >> ./config.yaml
    echo 'variants_pattern: "{data_root}/{sample}.pass.vcf.gz"' >> ./config.yaml
    ln -s $FILE_PATH ./files
    sed -i 's|/ARTIC/nanopolish||' ./files/*.consensus.fasta
    sed -i 's|/ARTIC/medaka||' ./files/*.consensus.fasta
fi

# If we have a matching negative control, we modify the config to make sure its gotten
# If we don't find any, then no negative controls are added
if $(ls ./files/ | grep -q -i "negative\|ntc\|water\|blank")
then
    for i in files/*.consensus.fasta; do echo $(basename ${i%%.*}); done >> file_names.txt
    negative_list=$(grep -i -e ntc -e negative -e water -e blank file_names.txt | cut -f 1 | sed 's/^/"/g' | sed 's/$/"/g' | tr "\n" ',' | sed 's/^/[/' | sed 's/$/]/')
    echo "negative_control_samples: ${negative_list}" >> ./config.yaml
fi


# Pipeline #
############

snakemake -s workflow/Snakefile --cores 1 build_snpeff_db
snakemake -s workflow/Snakefile all --cores $CORES

if [ "$PDF" = true ]; then
    snakemake -s workflow/Snakefile all_final_report --cores 1
fi

echo 'Done'
