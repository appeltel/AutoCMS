"""Scheduler related classes to handle job submission and queue status."""

import os
import re
import subprocess
import time
import socket

from .core import JobRecord


class UnknownScheduler(Exception):
    """Exception for scheduler type not implemented."""
    def __init__(self, message):
        super(UnknownScheduler, self).__init__(message)
        self.message = message

    def __str__(self):
        return repr(self.message)


def create_scheduler(sched_type, config):
    """Factory function for creating Scheduler subclasses."""
    if sched_type == 'slurm':
        return SlurmScheduler(config)
    elif sched_type == 'local':
        return LocalScheduler(config)
    else:
        raise UnknownScheduler("Scheduler type '" +
                               sched_type +
                               "' is not implemented.")


def submission_failure_preamble(timestamp):
    """Return a string to be prepended to a submission failure log."""
    preamble = "Job submission failed at {0}\n".format(timestamp)
    preamble += "On node {0}\n".format(socket.gethostname())
    preamble += "Submission command output:\n\n"
    return preamble


class Scheduler(object):
    """Base class for schedulers."""

    def __init__(self, config):
        """Construct a scheduler object with AutoCMS config."""
        self.config = config

    def get_completed_jobs(self, joblist):
        """Return a list of recently completed jobs.

        Joblist is a list of jobids to check for completion."""
        raise NotImplementedError

    def enqueued_job_count(self):
        """Count the number of jobs that user has on the queue."""
        raise NotImplementedError

    def submit_job(self, counter, testname):
        """Submit a new job to the queue.

        Returns a JobRecord object with the status of the job.

        If the submission fails the jobid should be set to none. The
        scheduler should write the standard output and error of the
        submission command to a log file and pass the name of the
        log file to the JobRecord."""
        raise NotImplementedError


class SlurmScheduler(Scheduler):
    """Interface to slurm scheduler."""

    def __init__(self, config):
        Scheduler.__init__(self, config)

    def get_completed_jobs(self, joblist):
        cmd = ('sacct --state=CA,CD,F,NF,TO '
               '-S $(date +%Y-%m-%d -d @$(( $(date +%s) - 172800 )) ) '
               '--accounts={0} --user={1} -n -o "jobid" | '
               'grep -e "^[0-9]* "'.format(self.config['AUTOCMS_GNAME'],
                                           self.config['AUTOCMS_UNAME']))
        result = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
        output = result.communicate()[0].splitlines()
        completed_jobs = [line.strip() for line in output]
        for job in completed_jobs[:]:
            if not job in joblist:
                completed_jobs.remove(job)
        return completed_jobs

    def enqueued_job_count(self):
        cmd = ('squeue -h --user={0} --account={1} | '
               'wc -l'.format(self.config['AUTOCMS_UNAME'],
                              self.config['AUTOCMS_GNAME']))
        result = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
        output = result.communicate()[0].splitlines()
        count = int(output[0].strip())
        return count

    def submit_job(self, counter, testname):
        slurm_script = testname + '.slurm'
        testdir = os.path.join(self.config['AUTOCMS_BASEDIR'],
                               testname)
        # need to go ahead and export the config path in case
        # this was not called through autocms.sh
        cmd = ('cd {0}; export AUTOCMS_COUNTER={1}; '
               'export AUTOCMS_CONFIGFILE={2}; '
               'sbatch --account={3} {4} '
               '--export=AUTOCMS_COUNTER,AUTOCMS_CONFIGFILE '
               '2>&1'.format(testdir,
                             counter,
                             self.config['AUTOCMS_CONFIGFILE'],
                             self.config['AUTOCMS_GNAME'],
                             slurm_script))
        result = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
        timestamp = int(time.time())
        sub_output = result.communicate()[0]
        if result.returncode == 0:
            jobid = re.sub('Submitted batch job ',
                           '',
                           sub_output.splitlines()[0].strip())
            logfile = testname + '.' + 'slurm' + '.o' + str(jobid) + '.log'
        else:
            timeouterror = 'timed out'
            if timeouterror in sub_output:
               jobid = 1
            else: 
               jobid = 2
            logfile = (testname + '.' + 'submission' + '.o' +
                       str(timestamp) + "." + str(counter) + '.log')
            logpath = os.path.join(self.config['AUTOCMS_BASEDIR'],
                                   testname,
                                   logfile)
            sub_output = submission_failure_preamble(timestamp) + sub_output
            with open(logpath, 'w') as log:
                log.write(sub_output)
        return JobRecord(counter, jobid, timestamp, result.returncode, logfile)


class LocalScheduler(Scheduler):
    """Run jobs in the background of the local machine."""

    def __init__(self, config):
        Scheduler.__init__(self, config)

    def get_completed_jobs(self, joblist):
        cmd = ('ps -u {0}'.format(self.config['AUTOCMS_UNAME']))
        result = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
        output = result.communicate()[0].splitlines()
        running_procs = [line.split()[0] for line in output]
        completed_jobs = joblist[:]
        for job in joblist:
            if job in running_procs:
                completed_jobs.remove(job)
        return completed_jobs

    def enqueued_job_count(self):
        # there is no queue, return 0
        return 0

    def submit_job(self, counter, testname):
        local_script = testname + '.local'
        timestamp = int(time.time())
        logfile = (testname + '.local.o' + str(timestamp) +
                   '.' + str(counter) + '.log')
        testdir = os.path.join(self.config['AUTOCMS_BASEDIR'],
                               testname)
        cmd = ('cd {0}; export AUTOCMS_COUNTER={1}; '
               ' export AUTOCMS_CONFIGFILE={2}; '
               ' nohup bash {3} > {4} '
               ' 2>&1 &'.format(testdir,
                                counter,
                                self.config['AUTOCMS_CONFIGFILE'],
                                local_script,
                                logfile))
        result = subprocess.Popen(cmd,
                                  shell=True,
                                  stdout=subprocess.PIPE)
        sub_output = result.communicate()[0]
        if result.returncode == 0:
            jobid = result.pid
        else:
            jobid = None
            logpath = os.path.join(self.config['AUTOCMS_BASEDIR'],
                                   testname,
                                   logfile)
            sub_output = submission_failure_preamble(timestamp) + sub_output
            with open(logpath, 'w') as log:
                log.write(sub_output)
        return JobRecord(counter, jobid, timestamp, result.returncode, logfile)
