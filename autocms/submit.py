"""Functions to submit and register new jobs."""

import os
import time

from .scheduler import create_scheduler


def submit_and_stamp(counter, testname, scheduler, config):
    """Submit a job to the scheduler and produce a newstamp file.

    The full path of the newstamp file is returned."""
    retry = 0
    while retry < 6:
      result = scheduler.submit_job(counter, testname)
      stamp_filename = ('stamp.' +
                        str(result.submit_time) + '.' +
                        str(counter))
      stamp_path = os.path.join(config['AUTOCMS_BASEDIR'],
                                testname,
                                stamp_filename)
      with open(stamp_path, 'w') as stampfile:
          stampfile.write(result.stamp())
      if result.jobid != 1:
        return stamp_path
        break
      retry = retry + 1
      time.sleep(10)
      return stamp_path

def get_job_counter(testname, config):
    """Return an integer for the counter to pass to the next job."""
    counter_path = os.path.join(config['AUTOCMS_BASEDIR'],
                                testname,
                                'counter')
    if os.path.exists(counter_path):
        with open(counter_path) as handle:
            count = handle.read()
    else:
        count = 1
    return int(count)


def set_job_counter(count, testname, config):
    """Write the job counter to file."""
    counter_path = os.path.join(config['AUTOCMS_BASEDIR'],
                                testname,
                                'counter')
    with open(counter_path, 'w') as handle:
        handle.write(str(count))


def perform_test_submission(num_jobs, testname, config):
    """Submit up to num_jobs depending on the queue, incrementing counter."""
    # Ensure that we don't have too many jobs already waiting
    scheduler = create_scheduler(config['AUTOCMS_SCHEDULER'], config)
    jobcount = scheduler.enqueued_job_count()
    available_slots = int(config['AUTOCMS_MAXENQUEUE']) - jobcount
    counter = get_job_counter(testname, config)
    while num_jobs > 0 and available_slots > 0:
        submit_and_stamp(counter, testname, scheduler, config)
        num_jobs -= 1
        available_slots -= 1
        counter += 1
    set_job_counter(counter, testname, config)
