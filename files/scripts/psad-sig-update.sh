#!/bin/bash
#
# This script updates the psad signature tables and loads the new signatures
# Author: Robert Strasser <avasilencia@pc-tiptop.de>
psad --sig-update
psad -H
