# ncov-tools-automation
Automate ncov-tools from connor-lab pipeline

Will install mamba into your base conda environment to create the needed environment. Not working on Illumina data yet as I didn't get to it.

## Help Statement

```
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
```
