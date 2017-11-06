#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem-per-cpu=2G
#SBATCH --output=skim_test.slurm.o%A.log
#SBATCH --time=0-12:00:00
#SBATCH --job-name="skim_test"

main ()
{

  # run the system bashrc
  if [ -f /etc/bashrc ]; then
  	. /etc/bashrc
  fi

  # run the AutoCMS Configuration File
  source $AUTOCMS_CONFIGFILE

  echo "${AUTOCMS_start_time_TOKEN}$(date +%s)"
  echo "SKIM_TEST: Beginning at $(date)"
  echo "${AUTOCMS_node_TOKEN}${HOSTNAME}"

  #-----------------------------------------------------------------------
  printbanner "Setting up enviornment"

  AUTODIR=$AUTOCMS_BASEDIR
  cd $AUTODIR/skim_test/
  export SCRAM_ARCH=slc6_amd64_gcc491
  echo "Set SCRAM_ARCH to $SCRAM_ARCH"
  setpkgs -a lio

  #-----------------------------------------------------------------------
  printbanner "Checking Input File"

  # determine input file to be used by picking a line in the file list
  # indicated by the counter
  AUTOCMS_COUNTER=$(( $AUTOCMS_COUNTER % `wc -l < myfiles.dat` ))
  INPUTFILE=$( sed ${AUTOCMS_COUNTER}'q;d' myfiles.dat)


  if [ -n "$INPUTFILE" ]; then
    echo "${AUTOCMS_input_file_TOKEN}${INPUTFILE}"
    echo "-------------------------------------"
    echo "Running lio-inspection on $INPUTFILE"
    lio_inspect -i 20 -d 20 -log /tmp/inspect.${SLURM_JOB_ID} ${INPUTFILE/file:/} | tee /tmp/check.${SLURM_JOB_ID}
    [ "$(grep 'Submitted: 0' /tmp/check.${SLURM_JOB_ID})" == "" ] && rm /tmp/inspect.${SLURM_JOB_ID}
    /bin/rm /tmp/check.${SLURM_JOB_ID}
    echo "-------------------------------------"

  else
    echo "${AUTOCMS_input_file_TOKEN}Default"
    echo "SKIM_TEST: WARNING: no input file specified, using default"
  fi

  #-----------------------------------------------------------------------
  printbanner "Setting up SCRAM environment"

  # I don't know why this is a problem, but if one runs a 
  # 'setpkgs -a python' from the submitting node, then 
  # the CMS environment breaks python on the worker node
  # unsetting the PYTHONAPATH fixes this.
  unset PYTHONPATH

  source /cvmfs/cms.cern.ch/cmsset_default.sh
  SCRAM_TEST_RESULT=$?
  if [ $SCRAM_TEST_RESULT -eq 0 ]; then
    echo "SKIM_TEST: SCRAM Enviornment setup from /cvmfs OK"
  else
    echo "${AUTOCMS_error_string_TOKEN}SCRAM Enviornment setup ERROR $SCRAM_TEST_RESULT"
    exitclean $SCRAM_TEST_RESULT
  fi

  #-----------------------------------------------------------------------
  printbanner "Making tmp working directory and testing tmp filesystem"

  TMP_WORKDIR=/tmp/${AUTOCMS_UNAME}-${SLURM_JOB_ID}

  mkdir $TMP_WORKDIR
  cd $TMP_WORKDIR

  touch tmpfs_test
  TEMPFS_TEST_RESULT=$?
  if [ $TEMPFS_TEST_RESULT -eq 0 ]; then
    echo "SKIM_TEST: touch in directory $TMP_WORKDIR OK"
  else
    echo "${AUTOCMS_error_string_TOKEN}touch in directory $TMP_WORKDIR ERROR $TEMPFS_TEST_RESULT"
    exitclean $TEMPFS_TEST_RESULT
  fi

  #-----------------------------------------------------------------------
  printbanner "Setting up CMSSW project area"

  scram p CMSSW $AUTOCMS_CMSSW_VERSION
  PROJECT_TEST_RESULT=$?
  if [ $PROJECT_TEST_RESULT -eq 0 ]; then
    echo "SKIM_TEST: CMSSW project area setup OK"
  else
    echo "${AUTOCMS_error_string_TOKEN}CMSSW project area setup ERROR $PROJECT_TEST_RESULT"
    exitclean $PROJECT_TEST_RESULT
  fi

  #-----------------------------------------------------------------------
  printbanner "Initializing CMSSW runtime environment and copying python configuration"

  cd $AUTOCMS_CMSSW_VERSION
  echo "Evaluating 'scramv1 runtime -sh'"
  eval `scramv1 runtime -sh`
  echo "Copying $AUTODIR/skim_test/skimTestIvars.py to current directory"
  cp $AUTODIR/skim_test/skimTestIvars.py .

  #-----------------------------------------------------------------------
  printbanner "Running CMSSW Skim Job"

  echo;echo "Current system load:";echo
  dstat --nocolor -cdngy 1 10

  CMSRUNPROCBEFORE=$(ps aux | grep "[c]msRun" | grep -v "/usr/bin/time" | wc -l)
  echo;echo "Number of cmsRun processes on node: $CMSRUNPROCBEFORE ";echo

  NODEJOBBEFORE=$( squeue --nodes=$HOSTNAME  -h | wc -l)
  echo;echo "Number of SLURM jobs running on node: $NODEJOBBEFORE ";echo


  echo;echo;echo;echo "BEGIN CMSSW EXECUTION: $(date)";echo;echo
  if [ -z "$INPUTFILE" ]; then
    /usr/bin/timeout --signal=KILL $SKIMTEST_CMSRUN_TIMEOUT cmsRun skimTestIvars.py
    CMSSW_TEST_RESULT=$?
  else
    /usr/bin/timeout --signal=KILL $SKIMTEST_CMSRUN_TIMEOUT cmsRun skimTestIvars.py inputFiles=$INPUTFILE
    CMSSW_TEST_RESULT=$?
  fi
  echo;echo;echo;echo "END CMSSW EXECUTION: $(date)";echo;echo

  CMSRUNPROCAFTER=$(ps aux | grep "[c]msRun" | grep -v "/usr/bin/time" | wc -l)
  echo;echo "Number of cmsRun processes on node: $CMSRUNPROCAFTER ";echo

  NODEJOBAFTER=$( squeue --nodes=$HOSTNAME  -h | wc -l)
  echo;echo "Number of SLURM jobs running on node: $NODEJOBAFTER ";echo

  CMSRUNPROCAVG=$(echo "($CMSRUNPROCBEFORE + $CMSRUNPROCAFTER ) / 2.0" | bc -l)
  echo "${AUTOCMS_cmsrun_proc_count_TOKEN}${CMSRUNPROCAVG}"

  NODEJOBAVG=$(echo "($NODEJOBBEFORE + $NODEJOBAFTER ) / 2.0" | bc -l)
  echo "${AUTOCMS_node_jobs_count_TOKEN}${NODEJOBAVG}"

  echo;echo "Current system load:";echo
  dstat --nocolor -cdngy 1 10

  if [ $CMSSW_TEST_RESULT -eq 0 ]; then
    echo "SKIM_TEST: CMSSW execution OK"
  else
    if [  $CMSSW_TEST_RESULT -eq 137 ]; then
      echo "${AUTOCMS_error_string_TOKEN}CMMSW received KILL signal (likely excessive wall clock time) ERROR $CMSSW_TEST_RESULT"
    else
      echo "${AUTOCMS_error_string_TOKEN}CMSSW execution ERROR $CMSSW_TEST_RESULT"
    fi
    exitclean $CMSSW_TEST_RESULT
  fi

  #-----------------------------------------------------------------------
  printbanner "Checking output file and stageout scripts"

  echo "Checking output file:"
  ls -l hiHighPt.root

  echo "-------------------------"
  echo "Checking Stageout scripts"
  echo "-------------------------"
  echo "Running: ls -lh /usr/local/cms-stageout/"
  ls -lh /usr/local/cms-stageout/
  echo "-------------------------"
  echo "Running: md5sum /usr/local/cms-stageout/vandy.cfg"
  md5sum /usr/local/cms-stageout/vandy.cfg
  echo "Running: md5sum /usr/local/cms-stageout/vandyCp.sh"
  md5sum /usr/local/cms-stageout/vandyCp.sh
  echo "Running: md5sum /usr/local/cms-stageout/vandyRm.sh"
  md5sum /usr/local/cms-stageout/vandyRm.sh
  echo "-------------------------"

  #-----------------------------------------------------------------------
  printbanner "Uploading output file to /lio/lfs"


  echo "construct output file name for upload"
  export DFILE=testoutput_${SLURM_JOB_ID}_hiHighPt.root
  echo "Uploading to $SKIMTEST_STAGEOUT_DIR/$DFILE"
  echo; echo "============== Begin VandyCp Log =============="; echo
  $AUTOCMS_VANDYCP hiHighPt.root $SKIMTEST_STAGEOUT_DIR/$DFILE verbose
  UPLOAD_TEST_RESULT=$?
  echo; echo "============== End VandyCp Log =============="; echo
  if [ $UPLOAD_TEST_RESULT -eq 0 ]; then
    echo "SKIM_TEST: lio Upload OK"
  else
    echo "${AUTOCMS_error_string_TOKEN}lio Upload ERROR $UPLOAD_TEST_RESULT"
    exitclean $UPLOAD_TEST_RESULT
  fi


  echo "Running stat on uploaded file via LFS"
  echo "====================================="
  time stat $SKIMTEST_STAGEOUT_DIR/$DFILE
  echo "====================================="
  echo
  echo "Checking that the uploaded file size is correct"
  LOCAL_OUTPUT_SIZE=$(ls -l hiHighPt.root | awk '{print $5}')
  LSTORE_OUTPUT_SIZE=$( lio_ls @:$SKIMTEST_STAGEOUT_DIR/$DFILE | tail -n 1 | awk '{print $4}')
  echo "    Local size = $LOCAL_OUTPUT_SIZE"
  echo "    LStore size = $LSTORE_OUTPUT_SIZE"
  if [ $LOCAL_OUTPUT_SIZE -ne $LSTORE_OUTPUT_SIZE ]; then
    echo "${AUTOCMS_error_string_TOKEN}ERROR vandyCp returned 0 but file sizes do not match!"
    exitclean 255
  fi 

  echo;echo "Checking user.cms_user_x509 attribute:"
  FILE_DN=$(lio_getattr -al user.cms_user_x509 -new_obj "" -end_obj "" -attr_fmt "%s#%s\n" ${SKIMTEST_STAGEOUT_DIR}/${DFILE} | sed 's/^user.cms_user_x509#//')
  echo "   user.cms_user_x509 = $FILE_DN"; echo

  #-----------------------------------------------------------------------
  printbanner "Deleting output file from /lio/lfs"

  echo "-------------------------------------"
  echo "run lio-inspection on the output file before deleting it"
  lio_inspect -i 20 $SKIMTEST_STAGEOUT_DIR/$DFILE
  echo "-------------------------------------"

  echo "remove the output and check that it is gone"

  echo; echo "============== Begin VandyRm Log =============="; echo
  $AUTOCMS_VANDYRM $SKIMTEST_STAGEOUT_DIR/$DFILE verbose
  DELETE_TEST_RESULT=$?
  echo; echo "============== End VandyRm Log =============="; echo

  if [ $DELETE_TEST_RESULT -eq 0 ]; then
    echo "SKIM_TEST: /lio/lfs file delete OK"
  else
    echo "${AUTOCMS_error_string_TOKEN}/lio/lfs file delete ERROR $DELETE_TEST_RESULT"
    exitclean $DELETE_TEST_RESULT
  fi

  echo "${AUTOCMS_SUCCESS_TOKEN}" 
  exitclean 0
}

exitclean ()
{
    printbanner "Cleaning up /tmp and Exiting"
    if [ -e $TMP_WORKDIR/tmpfs_test ]; then
      rm $TMP_WORKDIR/tmpfs_test
    fi
    if [ -e $TMP_WORKDIR/$AUTOCMS_CMSSW_VERSION ]; then
      rm -r $TMP_WORKDIR/$AUTOCMS_CMSSW_VERSION
      rmdir $TMP_WORKDIR
    fi
    echo -n "SKIM_TEST: Ending at "; date
    echo "${AUTOCMS_end_time_TOKEN}$(date +%s)"
    echo "${AUTOCMS_exit_code_TOKEN}$1"
    exit $1
}

printbanner ()
{
  echo -e "\n\n\n"
  echo "*****************************************************"
  echo "*"
  echo "* $1"
  echo "*"
  echo "*****************************************************"
  echo -e "\n\n\n"

}


main
