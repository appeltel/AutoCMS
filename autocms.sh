#!/bin/bash

main ()
{
  if [ -f ~/.bashrc ]; then
	. ~/.bashrc
  elif [ -f /etc/bashrc ]; then
        . 
  fi
  source autocms.cfg

  case "${commandline_args[0]}" in
  
    print) autocms_print
      ;;
    start) autocms_start
      ;;
    stop) autocms_stop
      ;;
    submit) autocms_submit
      ;;
    logharvest) autocms_logharvest
      ;;
    report) autocms_report
      ;;
    statsharvest) autocms_statsharvest
      ;;
    travis_setup) autocms_travis_setup
      ;;
    *) if [ -n "${commandline_args[0]}" ]; then 
         echo "${commandline_args[0]} is not a valid command"
       fi
      ;;

  esac

  echo "Usage \"autocms.sh command [testname]\" "
  echo "Please see: "
  echo "  https://github.com/appeltel/AutoCMS"
  echo "for additional documentation."

}

autocms_print ()
{

  print_autocms_crontab
  echo
  echo "Crontab lines for autocms below:"
  echo "=================================================="
  cat autocms.crontab
  echo "=================================================="
  echo "These lines are also saved in the file \"autocms.crontab\""
  echo
  exit 0

}

autocms_start ()
{
  crontab_overwrite_warning
  if [[ -f crontab_host.txt ]]
  then
    AUTOCMS_HOST=`cat crontab_host.txt`
    echo "ERROR: autocms instance already running on $AUTOCMS_HOST"
    echo "Exiting..."
  exit 1
  fi
  echo "Starting autocms..."
  echo $HOSTNAME > crontab_host.txt
  print_autocms_crontab
  crontab autocms.crontab
  exit 0
}

autocms_stop ()
{
  crontab_overwrite_warning
  if [[ ! -f crontab_host.txt ]]
  then
    echo "No running autocms instance detected. Exiting..."
    exit 1
  fi
  AUTOCMS_HOST=`cat crontab_host.txt`
  if [[ ! $AUTOCMS_HOST = $HOSTNAME ]]
  then
    echo "Attempting to stop autocms on $HOSTNAME "
    echo "but this instance of autocms is running on $AUTOCMS_HOST. "
    echo "Log into $HOSTNAME and try again."
    exit 1
  fi
  echo "Stopping autocms..." 
  crontab -r
  rm crontab_host.txt
  exit 0

}

autocms_submit ()
{
  if [ -d "${AUTOCMS_BASEDIR}/${commandline_args[1]}" ]; then
    NJOBS=1
    if [ ${#commandline_args[@]} -ge 3 ]; then
        NJOBS=${commandline_args[2]}
    fi
    ${AUTOCMS_PYTHON_EXECUTABLE} submitter.py ${commandline_args[1]} -n $NJOBS
    exit 0
  else
    echo "Request to submit non-existent test ${commandline_args[1]} failed"
    exit 1
  fi 
}

autocms_report ()
{
  if [ -d "${AUTOCMS_BASEDIR}/${commandline_args[1]}" ]; then
    ${AUTOCMS_PYTHON_EXECUTABLE} reporter.py ${commandline_args[1]}
    exit 0
  else
    echo "Request to report non-existent test ${commandline_args[1]} failed"
    exit 1
  fi
}

autocms_logharvest ()
{
  if [ -d "${AUTOCMS_BASEDIR}/${commandline_args[1]}" ]; then
    ${AUTOCMS_PYTHON_EXECUTABLE} logharvester.py ${commandline_args[1]} ${commandline_args[2]}
    exit 0
  else
    echo "Request to harvest non-existent test ${commandline_args[1]} failed"
    exit 1
  fi
}

autocms_statsharvest ()
{
  if [ -d "${AUTOCMS_BASEDIR}/${commandline_args[1]}" ]; then
    ${AUTOCMS_PYTHON_EXECUTABLE} statsharvester.py ${commandline_args[1]}
    exit 0
  else
    echo "Request to statsharvest non-existent test ${commandline_args[1]} failed"
    exit 1
  fi
}

print_autocms_crontab ()
{
  if [[ -f autocms.crontab ]] 
  then
    rm autocms.crontab 
  fi

  echo "MAILTO=\"\"" >> autocms.crontab
  SUBWAIT=( $( echo $AUTOCMS_TEST_SUBWAITS | tr ":" " " ) )
  SUBCOUNT=( $( echo $AUTOCMS_TEST_SUBCOUNTS | tr ":" " " ) )
  COUNT=0
  for TESTNAME in $( echo $AUTOCMS_TEST_NAMES | tr ":" "\n" ); do
    if [ ${SUBWAIT[$COUNT]} -lt 60 ]; then
      echo "*/${SUBWAIT[$COUNT]} * * * * cd $AUTOCMS_BASEDIR && $AUTOCMS_BASEDIR/autocms.sh submit $TESTNAME ${SUBCOUNT[$COUNT]}"  >> autocms.crontab
      echo "0,10,20,30,40,50 * * * * cd $AUTOCMS_BASEDIR && $AUTOCMS_BASEDIR/autocms.sh logharvest $TESTNAME" >> autocms.crontab
      echo "5,15,25,35,45,55 * * * * cd $AUTOCMS_BASEDIR && $AUTOCMS_BASEDIR/autocms.sh report $TESTNAME" >> autocms.crontab
    else
      SUBWAIT[$COUNT]=$(( ${SUBWAIT[$COUNT]} / 60 )) 
      echo "0 */${SUBWAIT[$COUNT]} * * * cd $AUTOCMS_BASEDIR && $AUTOCMS_BASEDIR/autocms.sh submit $TESTNAME ${SUBCOUNT[$COUNT]}"  >> autocms.crontab
      echo "10,40 * * * * cd $AUTOCMS_BASEDIR && $AUTOCMS_BASEDIR/autocms.sh logharvest $TESTNAME" >> autocms.crontab
      echo "20,50 * * * * cd $AUTOCMS_BASEDIR && $AUTOCMS_BASEDIR/autocms.sh report $TESTNAME" >> autocms.crontab
    fi
    echo "57 */${AUTOCMS_STAT_INTERVAL} * * * cd $AUTOCMS_BASEDIR && $AUTOCMS_BASEDIR/autocms.sh statsharvest $TESTNAME" >> autocms.crontab 
    (( COUNT++ ))
  done
}

crontab_overwrite_warning()
{
  echo "WARNING: Use of this command will overwrite your crontab on this host."
  echo "For manual setup, use \"autocms.sh print\" to print the"
  echo "crontab entry lines needed to run the system."
  echo "Current host: $HOSTNAME"

  read -p "Are you sure [y/n] ? " -n 1 -r
  echo; echo   
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    return
  else
    exit 0
  fi
}

autocms_travis_setup()
{
  mkdir ${TRAVIS_BUILD_DIR}/webdir
  cat autocms.cfg.vandy  | grep -v 'AUTOCMS_CONFIGFILE\|AUTOCMS_BASEDIR\|AUTOCMS_WEBDIR\|AUTOCMS_UNAME' > autocms.cfg
  echo "export AUTOCMS_CONFIGFILE=${TRAVIS_BUILD_DIR}/autocms.cfg" >> autocms.cfg
  echo "export AUTOCMS_BASEDIR=${TRAVIS_BUILD_DIR}" >> autocms.cfg
  echo "export AUTOCMS_UNAME=$(whoami)" >> autocms.cfg
  echo "export AUTOCMS_WEBDIR=${TRAVIS_BUILD_DIR}/webdir" >> autocms.cfg
  exit 0
}

# default autocms variables
export AUTOCMS_PYTHON_EXECUTABLE=${AUTOCMS_PYTHON_EXECUTABLE:-python}

commandline_args=("$@")
main
