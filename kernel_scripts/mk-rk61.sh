#!/bin/bash

export PATH=/usr/local/clang/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
#/usr/local/bin/limit_cpufreq.sh

ENV_FILE="/usr/src/krockchip-6.1.env"
MAKE_SCRIPT="/usr/src/make-kernel.sh"

${MAKE_SCRIPT} ${ENV_FILE} $@
exit $?
