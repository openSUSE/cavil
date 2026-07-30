#!/bin/bash 

if test -e staging/do_not_commit/cavil.conf; then 

CAVIL_CONF=staging/do_not_commit/cavil.conf morbo script/cavil &
CAVIL_CONF=staging/do_not_commit/cavil.conf script/cavil minion worker

fi 
