#!/bin/bash
username=$PAM_USER
if [ $(date +%a) = "Wed" ]  || [ $(date +%a) = "Sun" ]; then
  if getent group admin | grep -q "\b${username}\b"; then
        exit 0
      else
        exit 1
    fi
  else 
    exit 0
fi
