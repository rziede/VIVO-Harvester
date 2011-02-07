#!/bin/bash

# Copyright (c) 2010 Christopher Haines, Dale Scheppler, Nicholas Skaggs, Stephen V. Williams.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the new BSD license
# which accompanies this distribution, and is available at
# http://www.opensource.org/licenses/bsd-license.html
# 
# Contributors:
#     Christopher Haines, Dale Scheppler, Nicholas Skaggs, Stephen V. Williams - initial API and implementation
#	  James Pence

# Set working directory
set -e

DIR=$(cd "$(dirname "$0")"; pwd)
cd $DIR
cd ..

HARVESTER_TASK=dsr

if [ -f scripts/env ]; then
  . scripts/env
else
  exit 1
fi
echo "Full Logging in $HARVESTER_TASK.log"

# Setting variables for cleaner script lines.
BASEDIR=harvested-data/dsr
RAWRHDIR=$BASEDIR/rh-raw
RAWRHDBURL=jdbc:h2:$RAWRHDIR/store
RDFRHDIR=$BASEDIR/rh-rdf
RDFRHDBURL=jdbc:h2:$RDFRHDIR/store
MODELDIR=$BASEDIR/model
MODELDBURL=jdbc:h2:$MODELDIR/store
SCOREINPUT="-i $H2MODEL -ImodelName=dsrTempTransfer -IdbUrl=$MODELDBURL"
SCOREDATA="-s $H2MODEL -SmodelName=dsrScoreData -SdbUrl=$MODELDBURL"
ALTSCOREDATA="-s $H2MODEL -S modelName=dsrAltScoreData -S dbUrl=$MODELDBURL"
CNFLAGS="$SCOREINPUT -v $VIVOCONFIG -n http://vivo.ufl.edu/individual/"
EQTEST="org.vivoweb.harvester.score.algorithm.EqualityTest"
RDFTYPE="http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
RDFSLABEL="http://www.w3.org/2000/01/rdf-schema#label"
UFID="http://vivo.ufl.edu/ontology/vivo-ufl/ufid"
UFDEPTID="http://vivo.ufl.edu/ontology/vivo-ufl/deptID"

#clear old fetches
rm -rf $RAWRHDIR

# Execute Fetch
$JDBCFetch -X config/tasks/dsr.jdbcfetch.xml -o $H2RH -OdbUrl=$RAWRHDBURL

# backup fetch
BACKRAW="raw"
backup-path $RAWRHDIR $BACKRAW
# uncomment to restore previous fetch
#restore-path $RAWRHDIR $BACKRAW

# clear old translates
rm -rf $RDFRHDIR

# Execute Translate
$XSLTranslator -i $H2RH -IdbUrl=$RAWRHDBURL -o $H2RH -OdbUrl=$RDFRHDBURL -x config/datamaps/dsr-to-vivo.xsl

# backup translate
BACKRDF="rdf"
backup-path $RDFRHDIR $BACKRDF
# uncomment to restore previous translate
#restore-path $RDFRHDIR $BACKRDF

# Clear old H2 transfer model
rm -rf $MODELDIR

# Execute Transfer to import from record handler into local temp model
$Transfer -o $H2MODEL -OmodelName=dsrTempTransfer -OdbUrl=$MODELDBURL -h $H2RH -HdbUrl=$RDFRHDBURL -n http://vivo.ufl.edu/individual/

# backup H2 transfer Model
BACKMODEL="model"
backup-path $MODELDIR $BACKMODEL
# uncomment to restore previous H2 transfer Model
#restore-path $MODELDIR $BACKMODEL

# Execute score to match with existing VIVO
# The -n flag value is determined by the XLST file
# The -A -W -F & -P flags need to be internally consistent per call
# Scoring on UF ID person
$Score -v $VIVOCONFIG $SCOREINPUT $SCOREDATA -Aufid=$EQTEST -Wufid=1.0 -Fufid=$UFID -Pufid=$UFID -n http://vivoweb.org/harvest/dsr/person/

# Scoring on Dept ID
$Score -v $VIVOCONFIG $SCOREINPUT $SCOREDATA -AdeptID=$EQTEST -WdeptID=1.0 -FdeptID=$UFDEPTID -PdeptID=$UFDEPTID -n http://vivoweb.org/harvest/dsr/org/

# Scoring sponsors by labels
$Score -v $VIVOCONFIG $SCOREINPUT $SCOREDATA -Alabel=$EQTEST -Wlabel=1.0 -Flabel=$RDFSLABEL -Plabel=$RDFSLABEL -n http://vivoweb.org/harvest/dsr/sponsor/

# Scoring of PIs
$Score -v $VIVOCONFIG $SCOREINPUT $SCOREDATA -Atype=$EQTEST -Wtype=1.0 -Ftype=$RDFTYPE -Ptype=$RDFTYPE -Aufid=$EQTEST -Wufid=1.0 -Fufid=$UFID -Pufid=$UFID -n http://vivoweb.org/harvest/dsr/piRole/

# Scoring of coPIs
$Score -v $VIVOCONFIG $SCOREINPUT $SCOREDATA -Atype=$EQTEST -Wtype=1.0 -Ftype=$RDFTYPE -Ptype=$RDFTYPE -Aufid=$EQTEST -Wufid=1.0 -Fufid=$UFID -Pufid=$UFID -n http://vivoweb.org/harvest/dsr/coPiRole/

# Find matches using scores and rename nodes to matching uri
$Match $SCOREINPUT $SCOREDATA -t 1.0 -r -c

# Execute a score on the previous harvest.
# Should remove duplication issues
$Score -v $VIVOCONFIG -VmodelName=http://vivoweb.org/ingest/dsr $TEMPINPUT $ALTSCOREDATA -Aufid=$EQTEST -Wufid=1.0 -FContractNumber=http://vivo.ufl.edu/ontology/vivo-ufl/psContractNumber -PContractNumber=http://vivo.ufl.edu/ontology/vivo-ufl/psContractNumber -n http://vivoweb.org/harvest/dsr/grant/

$Match $SCOREINPUT $ALTSCOREDATA -t 1.0 -r

# Execute ChangeNamespace to get grants into current namespace
# the -o flag value is determined by the XSLT used to translate the data
$ChangeNamespace $CNFLAGS -o http://vivoweb.org/harvest/dsr/grant/

# Execute ChangeNamespace to get orgs into current namespace
# the -o flag value is determined by the XSLT used to translate the data
$ChangeNamespace $CNFLAGS -o http://vivoweb.org/harvest/dsr/org/

# Execute ChangeNamespace to get sponsors into current namespace
# the -o flag value is determined by the XSLT used to translate the data
$ChangeNamespace $CNFLAGS -o http://vivoweb.org/harvest/dsr/sponsor/

# Execute ChangeNamespace to get people into current namespace
# the -o flag value is determined by the XSLT used to translate the data
$ChangeNamespace $CNFLAGS -o http://vivoweb.org/harvest/dsr/person/

# Execute ChangeNamespace to get PI roles into current namespace
# the -o flag value is determined by the XSLT used to translate the data
$ChangeNamespace $CNFLAGS -o http://vivoweb.org/harvest/dsr/piRole/

# Execute ChangeNamespace to get co-PI roles into current namespace
# the -o flag value is determined by the XSLT used to translate the data
$ChangeNamespace $CNFLAGS -o http://vivoweb.org/harvest/dsr/coPiRole/

# backup H2 matched Model
BACKMATCHED="matched"
backup-path $MODELDIR $BACKMATCHED
# uncomment to restore previous H2 matched Model
#restore-path $MODELDIR $BACKMATCHED

# Backup pretransfer vivo database, symlink latest to latest.sql
BACKPREDB="pretransfer"
backup-mysqldb $BACKPREDB
# uncomment to restore pretransfer vivo database
#restore-mysqldb $BACKPREDB

PREVHARVESTMODEL="http://vivoweb.org/ingest/dsr"
ADDFILE="$BASEDIR/additions.rdf.xml"
SUBFILE="$BASEDIR/subtractions.rdf.xml"

# Find Subtractions
$Diff -m $VIVOCONFIG -MmodelName=$PREVHARVESTMODEL -McheckEmpty=$CHECKEMPTY -s $H2MODEL -ScheckEmpty=$CHECKEMPTY -SdbUrl=$MODELDBURL -SmodelName=dsrTempTransfer -d $SUBFILE
# Find Additions
$Diff -m $H2MODEL -McheckEmpty=$CHECKEMPTY -MdbUrl=$MODELDBURL -MmodelName=dsrTempTransfer -s $VIVOCONFIG -ScheckEmpty=$CHECKEMPTY -SmodelName=$PREVHARVESTMODEL -d $ADDFILE

# Backup adds and subs
backup-file $ADDFILE adds.rdf.xml
backup-file $SUBFILE subs.rdf.xml

# Apply Subtractions to Previous model
$Transfer -o $VIVOCONFIG -OcheckEmpty=$CHECKEMPTY -OmodelName=$PREVHARVESTMODEL -r $SUBFILE -m
# Apply Additions to Previous model
$Transfer -o $VIVOCONFIG -OcheckEmpty=$CHECKEMPTY -OmodelName=$PREVHARVESTMODEL -r $ADDFILE
# Apply Subtractions to VIVO
$Transfer -o $VIVOCONFIG -OcheckEmpty=$CHECKEMPTY -r $SUBFILE -m
# Apply Additions to VIVO
$Transfer -o $VIVOCONFIG -OcheckEmpty=$CHECKEMPTY -r $ADDFILE

# Backup posttransfer vivo database, symlink latest to latest.sql
BACKPOSTDB="posttransfer"
backup-mysqldb $BACKPOSTDB
# uncomment to restore posttransfer vivo database
#restore-mysqldb $BACKPOSTDB

#Restart Tomcat
#Tomcat must be restarted in order for the harvested data to appear in VIVO
/etc/init.d/tomcat restart
