#!/bin/sh

# Assign the command passed as arguments to a variable.
# The "$*" captures all command-line arguments as a single string.
# For example, running `./proc-runner.sh sleep 100` will store "sleep 100" in command_to_run.
command_to_run="$*"

echo "Starting process. Running command: $command_to_run" >&2

# Start the specified command in the background and store its process ID (PID).
# The "$!" variable holds the PID of the most recently executed background process.
$command_to_run &
command_pid="$!"

echo "PID $$ has started child process $command_pid" >&2

# Define a signal handler for SIGRTMIN+1 (a real-time signal).
# When this signal is received, the script will:
# 1. Gracefully terminate the child process by sending the SIGTERM signal.
# 2. Start a dummy process (in this case, `tail -f /dev/null`) to keep the container running.
# This is useful in containerized environments where stopping the main process would otherwise cause the container to exit.
#
# Example: To trigger this behavior, run `kill -35 <PID>` where `<PID>` is the process ID of this script.
#
# We're using `35` as the signal rather than `RTMIN+1` because it seems like Bourne shell treats 35 as `RT35` rather than `RTMIN+1`
#
# shellcheck disable=SC2172
trap 'echo "Sending TERM to child process $command_pid"; kill -TERM $command_pid; echo "Starting dummy process"; tail -f /dev/null' 35

# The wait command pauses the script and waits for all background
# processes to complete.  Here it waits for the child process to
# finish. If the signal is caught, the handler will run instead.
wait
