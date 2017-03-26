#!/usr/bin/env bash

detect_cgroup_mem_limit() {
  local cgroup_mem_limit_file
  # location of memory limit in bytes
  cgroup_mem_limit=/sys/fs/cgroup/memory/memory.limit_in_bytes

  echo $(cat $cgroup_mem_limit | awk '{printf("%d", $1/1024^2)}')
}

detect_system_mem_limit() {
  echo $(awk '/MemTotal:/ {if($3 == 'kB'); printf("%d", $2 / 1024)}' /proc/meminfo)
}

calc_jvm_heap_size() {
  # pass in two args: mem_limit and jvm_heap_ratio
  local cgroup_limit mem_limit jvm_heap_ratio

  mem_limit=$(detect_system_mem_limit)
  cgroup_limit=$(detect_cgroup_mem_limit)
  default_limit=512 # default to pretending 512MB limit

  # memory limit under k8s defaults to 64-bit max signed int.
  # if the limit is larger than amount of mem in system, set to default value
  if [ $cgroup_limit -lt $mem_limit ] ; then
    mem_limit=$cgroup_limit
  else
    mem_limit=$default_limit
  fi

  jvm_heap_ratio=${JVM_HEAP_RATIO:-0.75} # default heap allocation to 75% of mem limit

  echo $(echo $mem_limit $jvm_heap_ratio | awk '{printf("%d", $1 * $2)}')
}

set_default_jvm_opts() {
  # set jvm memory settings based on cgroup memory limits if set, otherwise
  # base them on system memory. if mem below set size, reduce jvm stack size

  local jvm_stack_arg min_mem_normal_stack small_stack_size

  # use smaller stack size heap less than this in MiB
  min_mem_for_normal_stack=512
  small_stack_size=512k

  jvm_heap_size=$(calc_jvm_heap_size $mem_limit)

  if [ $jvm_heap_size -lt $min_mem_for_normal_stack ] ; then
    jvm_stack_arg="-Xss${small_stack_size}"
  fi

  default_java_mem_opts="-Xmx${jvm_heap_size}m $jvm_stack_arg"
 }

# calc defaults
set_default_jvm_opts

# shamelessly borrowed structure from heroku-buildpack-jvm-common
if [[ "${JAVA_OPTS}" == *-Xmx* ]]; then
  export JAVA_TOOL_OPTIONS=${JAVA_TOOL_OPTIONS:-"-Dfile.encoding=UTF-8"}
else
  echo "Setting -Xmx to ${jvm_heap_size}m based on detected memory limits."
  echo "    Adjust limits and \$JVM_HEAP_RATIO to tweak."
  echo "Setting JAVA_OPTS based on detected memory size. Custom env will override them."
  default_java_opts="${default_java_mem_opts} -Dfile.encoding=UTF-8"
  export JAVA_OPTS="${default_java_opts} $JAVA_OPTS"
  if [[ "${DYNO}" != *run.* ]]; then
    export JAVA_TOOL_OPTIONS=${JAVA_TOOL_OPTIONS:-${default_java_opts}}
  fi
  if [[ "${DYNO}" == *web.* ]]; then
    echo "Setting JAVA_TOOL_OPTIONS defaults based on dyno size. Custom settings will override them."
  fi
fi
