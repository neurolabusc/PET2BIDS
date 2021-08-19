#!/usr/bin/env bash

# specify ecat headers file
ECAT_HEADERS='../ecat_headers.json'
COPIED_ECAT_HEADERS='ecat_headers.json'

# collect ecat headers file
cp ${ECAT_HEADERS} ./

# run pyinstaller

pyinstaller -F --add-data "ecat_headers.json:." main.py -n ecat_converter

rm -rf ${COPIED_ECAT_HEADERS}
