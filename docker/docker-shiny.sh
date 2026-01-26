#!/bin/bash

xtail /var/log/shiny-server/ &
exec shiny-server 2>&1
