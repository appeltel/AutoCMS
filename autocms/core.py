"""Common functions and classes for AutoCMS components."""

__version__ = '3.0.4'

import re
import os
import cPickle as pickle


class JobRecord(object):
    """Complete information about a specific AutoCMS test job.

    A JobRecord may store arbitrarily many properties about a completed job
    depending on how the test is configured, but these are not guaranteed to
    exist until the logs are parsed and only if the corresponding token
    exists in the output log.

    The following attributes are set during construction and should be
    guaranteed to exist (with the specified type if listed):

        seq - the integer passed to the job execution script.
        jobid - the scheduler job id or 1 submission failed from time out, 2 for other reasons.
        submit_time (int): timestamp of submission time.
        submit_status (int): exit code of the submission command.
        start_time (int): timestamp of when the job started running
                          or zero if the job is not yet completed.
        end_time (int): timestamp of when the job completed
                        or zero if the job is not yet completed.
        node: hostname of the worker node that runs the job or None.
        logfile: Expected file containing standard output of the job reported
                 through the scheduler. Note that due to scheduler errors
                 this file may never actually exist.
        completed (boolean): completion status of the job.
        exit_code (int): exit code returned by the job script
        exit_string: string describing the reason for job failure.
    """

    def __init__(self, counter, jobid, subtime, retval, log):
        """Construct JobRecord object from job submission information.

        Arguments:
            counter - value of the sequence counter for the job
            jobid - the jobid from the scheduler
            subtime - the unix timestamp of submission
            retval - the return value of the submission command
            log - name of the expected log file
        """
        self.seq = int(counter)
        self.submit_time = int(subtime)
        self.jobid = jobid
        self.submit_status = int(retval)
        self.logfile = log
        if self.submit_status == 0:
            self.node = None
            self.start_time = 0
            self.end_time = 0
            self.exit_code = 255
            self.error_string = "Job did not report success."
            self.completed = False
        else:
            self.node = None
            self.start_time = self.submit_time
            self.end_time = self.submit_time
            self.exit_code = self.submit_status
            self.error_string = ("ERROR in job submission code " +
                                 str(self.submit_status))
            self.completed = True

    @classmethod
    def create_from_stamp(cls, stamp):
        """Construct a JobRecord object from a submission stamp.

        A submission stamp is just a space-delimited line of text with
        the AutoCMS submission counter, scheduler jobid,
        submission timestamp, submission return value, and log filename."""
        stamp = stamp.split()
        if len(stamp) != 5:
            raise MalformedStamp("Wrong number of arguments in stamp string.")
        for index in range(0, 5):
            if stamp[index] == 'None':
                stamp[index] = None
        return cls(stamp[0], stamp[1], stamp[2], stamp[3], stamp[4])

    def stamp(self):
        """Return a submission stamp from a JobRecord object.

        A submission stamp is just a space-delimited line of text with
        the AutoCMS submission counter, scheduler jobid,
        submission timestamp, submission return value, and log filename."""
        return (str(self.seq) + ' ' +
                str(self.jobid) + ' ' +
                str(self.submit_time) + ' ' +
                str(self.submit_status) + ' ' +
                str(self.logfile))

    def run_time(self):
        """Return total wall clock running time in seconds."""
        return self.end_time - self.start_time

    def wait_time(self):
        """Return total wall clock queued time in seconds."""
        return self.start_time - self.submit_time

    def is_success(self):
        """Return boolean job success status."""
        if self.exit_code == 0:
            return True
        else:
            return False

    def is_retry(self):
        """Return boolean job retry status."""
        if self.jobid == 1:
            return True
        else:
            return False

    def parse_output(self, testname, config):
        """Parse job information from the log file."""
        tokens = [s for s in config.keys()
                  if re.match(r'AUTOCMS_.*_TOKEN', s)]
        logpath = os.path.join(config['AUTOCMS_BASEDIR'],
                               testname,
                               self.logfile)
        # jobs that do not specifically report success will
        # be marked as failed.
        reported_success = False
        with open(logpath, 'r') as handle:
            log = handle.read().splitlines()
        for line in log:
            for tok in tokens:
                if re.match(config[tok], line):
                    t_name = tok.replace('AUTOCMS_', '').replace('_TOKEN', '')
                    t_val = line.replace(config[tok], '')
                    if t_name == 'SUCCESS':
                        reported_success = True
                        self.exit_code = 0
                        self.error_string = ''
                    else:
                        setattr(self, t_name, t_val)
        # ensure that required attributes remain ints - oddball log could
        # mess this up
        self.exit_code = int(self.exit_code)
        self.start_time = int(self.start_time)
        self.end_time = int(self.end_time)
        # odd log could result in zero for start, end times
        # set to reasonable values
        if self.start_time == 0:
            self.start_time = self.submit_time
        if self.end_time == 0:
            self.end_time = self.start_time
        # make sure jobs not reporting success are marked failed
        if (not reported_success) and (self.exit_code == 0):
            self.exit_code = 255

    def __repr__(self):
        """Describe object id, submission time, and counter."""
        return ('<{0}.{1} object at {2} seq: {3} '
                'submit_time: {4}>'.format(
                    self.__class__.__module__,
                    self.__class__.__name__,
                    hex(id(self)),
                    self.seq,
                    self.submit_time))

    def __str__(self):
        """Return readable string of JobRecord object attributes."""
        attr_list = (attr for attr in dir(self)
                     if not attr.startswith('__') and
                     not callable(getattr(self, attr)))
        jrs = "JobRecord object"
        for attr in attr_list:
            jrs += "\n    {0}={1}".format(attr, repr(getattr(self, attr)))
        return jrs


class MalformedStamp(Exception):
    """Raised when loading a JobRecord from improperly formatted stamp."""
    def __init__(self, message):
        super(MalformedStamp, self).__init__(message)
        self.message = message

    def __str__(self):
        return repr(self.message)


def load_configuration(filename):
    """Return configuration dict from filename."""
    config = dict()
    with open(filename, 'r') as handle:
        config_raw = handle.read().splitlines()
    for line in config_raw:
        if re.match(r'export', line):
            key = line.split('=')[0]
            key = key.replace("export", "")
            key = key.strip()
            val = line.split('=')[1]
            val = val.strip()
            val = val.strip('"')
            config[key] = val
    return config


def load_records(testname, config):
    """Get the JobRecord list from the pickle or make a new one."""
    filepath = os.path.join(config['AUTOCMS_BASEDIR'],
                            testname,
                            'records.pickle')
    if os.path.isfile(filepath):
        records = pickle.load(open(filepath, "rb"))
    else:
        records = []
    return records


def save_records(records, testname, config):
    """Write the JobRecord list to a pickle."""
    filepath = os.path.join(config['AUTOCMS_BASEDIR'],
                            testname,
                            'records.pickle')
    pickle.dump(records, open(filepath, "wb"))
